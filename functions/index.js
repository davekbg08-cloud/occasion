const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");
const { randomUUID } = require("node:crypto");

initializeApp({
  storageBucket: "occasion-10cdb.firebasestorage.app",
});

const db = getFirestore();
const fcm = getMessaging();
const storageBucket = getStorage().bucket();

/**
 * Chemin objet Cloud Storage à partir d'une URL de téléchargement Firebase
 * (`.../o/<chemin-encodé>?alt=media&token=...`). Retourne `null` si l'URL ne
 * correspond pas au format attendu (jamais bloquant : appelant doit ignorer
 * silencieusement une suppression Storage impossible plutôt que faire
 * échouer la suppression Firestore).
 */
function storagePathFromDownloadUrl(url) {
  if (!url) return null;
  try {
    const match = new URL(url).pathname.match(/\/o\/(.+)$/);
    return match ? decodeURIComponent(match[1]) : null;
  } catch {
    return null;
  }
}

/**
 * Copie le fichier Storage d'un média transféré (`forwardChatMessage`) vers
 * le dossier du chat CIBLE (`chatMedia/{targetChatId}/{targetSenderId}/
 * {targetReceiverId}/...`) : sans cette copie, le message transféré
 * référencerait toujours le fichier du chat D'ORIGINE, et `storage.rules`
 * (participants encodés dans le chemin) protégerait ce fichier pour les
 * participants du chat source, pas ceux du chat cible qui le reçoivent
 * réellement — un participant du chat cible jamais présent dans le chat
 * source obtiendrait quand même accès au média. Si la copie échoue (ex.
 * fichier source déjà supprimé), on se rabat sur l'URL d'origine plutôt
 * que de bloquer le transfert entier pour un problème de média.
 */
function chatMediaDownloadUrl(destPath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${storageBucket.name}/o/${encodeURIComponent(destPath)}?alt=media&token=${token}`;
}

async function copyChatMediaToTargetChat(
  sourceMediaUrl,
  targetChatId,
  targetSenderId,
  targetReceiverId,
  clientMessageId
) {
  const sourcePath = storagePathFromDownloadUrl(sourceMediaUrl);
  if (!sourcePath) return sourceMediaUrl;

  const extMatch = sourcePath.match(/\.([a-zA-Z0-9]+)$/);
  const ext = extMatch ? extMatch[1] : "jpg";
  // Même schéma de chemin que `ChatMediaUploadService.upload`
  // (`chatMedia/{chatId}/{senderId}/{receiverId}/{fichier}`) : `storage.rules`
  // encode les deux participants directement dans le chemin (aucune lecture
  // croisée Firestore, qui s'est avérée systématiquement en échec en
  // production sur ce projet — voir l'historique de `storage.rules`).
  const destPath = `chatMedia/${targetChatId}/${targetSenderId}/${targetReceiverId}/${clientMessageId}.${ext}`;
  const destFile = storageBucket.file(destPath);
  const token = randomUUID();

  try {
    // `ifGenerationMatch: 0` : n'écrit QUE si aucun objet n'existe déjà à
    // ce chemin exact. Sans cette précondition atomique, un `clientMessageId`
    // déjà occupé par un AUTRE message (rejeu réseau, ou tentative hostile
    // visant un id qu'elle ne possède pas) verrait son fichier écrasé par
    // cette copie AVANT même que `writeChatMessage` ait pu rejeter l'écriture
    // Firestore pour collision d'id — l'écrasement, lui, resterait définitif.
    await storageBucket.file(sourcePath).copy(destFile, {
      metadata: { metadata: { firebaseStorageDownloadTokens: token } },
      preconditionOpts: { ifGenerationMatch: 0 },
    });
    return chatMediaDownloadUrl(destPath, token);
  } catch (err) {
    if (err?.code === 412) {
      // L'objet existe déjà à ce chemin : soit un rejeu légitime du MÊME
      // transfert (même `clientMessageId`, réessayé après une coupure
      // réseau une fois la copie Storage déjà passée), soit une collision
      // sur un id détenu par quelqu'un d'autre — dans les deux cas, ne
      // jamais écraser, réutiliser le fichier déjà en place. Si l'id
      // appartient à un autre expéditeur, `writeChatMessage` rejette de
      // toute façon l'écriture Firestore juste après.
      const [meta] = await destFile.getMetadata().catch(() => [null]);
      const existingToken = meta?.metadata?.firebaseStorageDownloadTokens
        ?.split(",")[0];
      if (existingToken) {
        return chatMediaDownloadUrl(destPath, existingToken);
      }
    }
    console.error(`Erreur copie média transféré ${sourcePath} -> ${destPath} :`, err);
    return sourceMediaUrl;
  }
}

const ESCROW_AUTO_RELEASE_DAYS = 3;

/**
 * Configuration du barème de points de fidélité (référence commerciale,
 * pas un placeholder à remplacer plus tard) — modifier uniquement les
 * valeurs ci-dessous pour ajuster le taux, sans toucher à la logique
 * (`pointsForAmount`, `creditOrderLoyaltyPoints`, tout le flux d'échange).
 *
 * Méthode de calcul : points = floor(montant dépensé/vendu * taux),
 * compté indépendamment par devise — jamais de conversion FC/USD inventée
 * (même principe que `sellerStatistics.revenue`, qui garde aussi les
 * devises séparées).
 *
 * Taux en vigueur depuis la version 1.1.1 (stabilisation) :
 *   - FC  : 1 point pour 1000 FC dépensés/vendus (1/1000).
 *   - USD : 1 point pour 1 USD dépensé/vendu (1/1).
 */
const LOYALTY_POINTS_RATE = { FC: 1 / 1000, USD: 1 };
const NOTIFICATIONS_COLLECTION = "notifications";
const NOTIFICATION_ENTITY_FIELDS = [
  "chatId",
  "listingId",
  "statusId",
  "orderId",
  "paymentIntentId",
  "entityId",
];

/** Topic FCM auquel tout acheteur est abonné dès l'enregistrement de son
 * appareil — sert uniquement à annoncer les nouveaux statuts (voir
 * `onNewStatus` plus bas), jamais lu/écrit ailleurs. */
const NEW_STATUS_TOPIC = "new_status";

/**
 * Canal de notification Android correspondant à un `type` de notification —
 * doit rester synchronisé avec les canaux déclarés côté client
 * (`lib/services/notification_service.dart`), chacun avec sa propre
 * vibration explicite.
 */
function androidChannelIdForType(type) {
  switch (type) {
    case "message":
      return "occasion_messages";
    case "order":
    case "subscription":
    case "subscription_request":
      return "occasion_orders";
    case "status":
    case "search_alert":
      return "occasion_listings";
    default:
      return "occasion_general";
  }
}
exports.androidChannelIdForType = androidChannelIdForType;

/**
 * Jetons FCM actifs d'un utilisateur, un par appareil connecté
 * (`users/{uid}/devices/{deviceId}`, remplace l'ancien champ unique
 * `fcmToken` pour supporter plusieurs appareils par compte).
 */
async function deviceTokensFor(uid) {
  const devicesSnap = await db
    .collection("users")
    .doc(uid)
    .collection("devices")
    .get();
  return devicesSnap.docs
    .map((doc) => ({ id: doc.id, token: doc.data()?.token }))
    .filter((device) => !!device.token);
}

/** Durée de bail d'une réservation d'envoi push (voir `claimPushSlot`) : une
 * Function arrêtée en plein envoi (crash, timeout) ne doit pas bloquer
 * indéfiniment la notification — passé ce délai, une nouvelle tentative est
 * autorisée à réclamer le slot. */
const PUSH_LEASE_MS = 2 * 60 * 1000;

/**
 * Crée le document de notification s'il n'existe pas encore, avec son état
 * initial complet (`isRead: false`, `createdAt`, `pushState: pending`). S'il
 * existe déjà (redélivrance du trigger appelant), ne met à jour QUE le
 * contenu (titre/corps/route/data/champs d'entité) — ne touche jamais
 * `isRead`, `readAt` ni `createdAt` : une notification déjà lue par
 * l'utilisateur ne doit jamais redevenir non lue à cause d'une redélivrance.
 */
async function upsertNotificationContent({
  notifRef,
  recipientId,
  senderId,
  type,
  title,
  body,
  route,
  data,
  entityFields,
}) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(notifRef);
    if (!snap.exists) {
      tx.set(notifRef, {
        recipientId,
        senderId,
        type,
        title,
        body,
        route,
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
        pushState: "pending",
        ...entityFields,
        data,
      });
      return;
    }

    tx.update(notifRef, {
      title,
      body,
      route,
      data,
      ...entityFields,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

/**
 * Marque la notification comme n'ayant pu être poussée sur aucun appareil,
 * sans jamais régresser un état déjà "sent" (ex. tous les appareils ont été
 * désinscrits après un envoi réussi antérieur). Le document Firestore
 * (historique in-app) reste conservé dans tous les cas.
 */
async function markNoDevicePush(notifRef) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(notifRef);
    if (snap.data()?.pushState === "sent") return;
    tx.update(notifRef, { pushState: "pending_no_device" });
  });
}

/**
 * Réserve atomiquement (transaction) le droit d'envoyer le push d'une
 * notification donnée. États possibles (`pushState`) : `pending` (jamais
 * tenté), `sending` (réservation posée, envoi en cours), `sent` (au moins un
 * succès FCM réel), `failed` (tenté, zéro succès — retentable),
 * `pending_no_device` (aucun appareil au moment de l'appel).
 *
 * Une redélivrance du trigger appelant, ou deux invocations concurrentes, ne
 * peuvent jamais toutes les deux gagner la réservation : la première pose
 * `pushState: sending` avec un bail (`pushLeaseUntil`) ; toute autre tentative
 * tant que ce bail est valide échoue. Si la Function s'arrête après avoir
 * réservé (crash/timeout, jamais de résultat FCM appliqué), le bail expire et
 * une nouvelle tentative peut réclamer le slot — la notification ne reste
 * jamais bloquée indéfiniment en "sending".
 *
 * Exportée pour être testée isolément (voir `functions/test/`), sans
 * dépendre d'un envoi FCM réel.
 */
async function claimPushSlot(notifRef) {
  const now = Date.now();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(notifRef);
    const notif = snap.data() ?? {};

    if (notif.pushSentAt || notif.pushState === "sent") {
      return { claimed: false };
    }

    if (notif.pushState === "sending") {
      const leaseUntilMs = notif.pushLeaseUntil?.toMillis?.() ?? 0;
      if (leaseUntilMs > now) {
        return { claimed: false };
      }
      // Bail expiré : une nouvelle réservation est permise (voir doc ci-dessus).
    }

    const pushClaimId = db.collection(NOTIFICATIONS_COLLECTION).doc().id;
    tx.update(notifRef, {
      pushState: "sending",
      pushClaimId,
      pushClaimedAt: FieldValue.serverTimestamp(),
      pushLeaseUntil: Timestamp.fromMillis(now + PUSH_LEASE_MS),
      lastPushAttemptAt: FieldValue.serverTimestamp(),
    });
    return { claimed: true, pushClaimId };
  });
}

/**
 * Applique le résultat (réel ou simulé) d'un envoi `sendEachForMulticast` au
 * document de notification et nettoie les jetons définitivement invalides.
 * Extraite de `sendToUser` pour être testable sans appeler FCM réellement
 * (voir `functions/test/`, qui lui passe un `result` fabriqué).
 *
 * Ne marque `pushState: sent` que si au moins un appareil a réellement reçu
 * le push (`successCount > 0`) — un envoi dont tous les jetons ont échoué
 * reste `failed` et retentable, jamais faussement marqué comme envoyé.
 *
 * Pour une notification de type `message` (`type`/`data.chatId`/
 * `data.messageId` fournis), un succès FCM réel (`successCount > 0`) fait
 * aussi passer le message correspondant de `sent` à `delivered` — "livré"
 * signifie ici qu'au moins un appareil du destinataire a effectivement reçu
 * le push, distinct de "lu" (`markChatAsRead`). Ne régresse jamais un
 * message déjà `read` (lu avant que le push n'ait fini d'être traité).
 */
async function applyPushResult({ notifRef, recipientId, devices, result, type, data }) {
  const successCount = result.successCount ?? 0;
  const failureCount = result.failureCount ?? 0;

  await Promise.all(
    (result.responses ?? []).map((res, i) => {
      const code = res.error?.code;
      const isDefinitivelyInvalid =
        !res.success &&
        (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token");
      if (!isDefinitivelyInvalid) return null;
      return db
        .collection("users")
        .doc(recipientId)
        .collection("devices")
        .doc(devices[i].id)
        .delete()
        .catch(() => {});
    })
  );

  if (successCount > 0) {
    await notifRef.update({
      pushState: "sent",
      pushSentAt: FieldValue.serverTimestamp(),
      pushSuccessCount: successCount,
      pushFailureCount: failureCount,
      pushLeaseUntil: FieldValue.delete(),
    });

    if (type === "message" && data?.chatId && data?.messageId) {
      const msgRef = db
        .collection("chats")
        .doc(data.chatId)
        .collection("messages")
        .doc(data.messageId);
      await db
        .runTransaction(async (tx) => {
          const snap = await tx.get(msgRef);
          if (!snap.exists) return;
          if (snap.data()?.status !== "sent") return; // jamais régresser "read"
          tx.update(msgRef, { status: "delivered", deliveredAt: FieldValue.serverTimestamp() });
        })
        .catch((err) => console.error(`Erreur marquage delivered ${data.chatId}/${data.messageId} :`, err));
    }
  } else {
    await notifRef.update({
      pushState: "failed",
      pushFailureCount: failureCount,
      lastPushError: result.responses?.find((res) => res.error)?.error?.code ?? "unknown",
      pushClaimId: FieldValue.delete(),
      pushLeaseUntil: FieldValue.delete(),
    });
  }
}

/**
 * Nombre de messages de conversation non lus d'un utilisateur, source
 * unique du badge natif (`users/{uid}.unreadMessageCount`, tenu à jour par
 * `incrementChatUnread`/`markChatAsRead`, jamais modifiable côté client —
 * voir `firestore.rules`). Extraite en fonction nommée (plutôt qu'inlinée
 * dans `sendToUser`) pour être testée isolément sans dépendre d'un envoi
 * FCM réel, même pattern que `claimPushSlot`/`applyPushResult`.
 */
async function badgeCountForUser(uid) {
  const snap = await db.collection("users").doc(uid).get();
  return snap.data()?.unreadMessageCount ?? 0;
}

/**
 * Persiste une notification (historique in-app, lue par le client via
 * `notifications/{id}`) et l'envoie en push à tous les appareils du
 * destinataire. `notificationId` déterministe = idempotent (les retries
 * Cloud Functions ne créent jamais de doublon, et ne font jamais redevenir
 * "non lue" une notification déjà lue par l'utilisateur — voir
 * `upsertNotificationContent`). L'envoi push lui-même est réservé
 * atomiquement (voir `claimPushSlot`) et son résultat réel appliqué au
 * document (voir `applyPushResult`) : jamais marqué "envoyé" sans au moins
 * un succès FCM réel.
 */
async function sendToUser({
  recipientId,
  notificationId,
  senderId = null,
  type,
  title,
  body,
  route = null,
  data = {},
}) {
  if (!recipientId) return;

  // Promeut au premier niveau du document les identifiants d'entité connus
  // du modèle client `AppNotification` (chatId, orderId, ...), en plus de
  // les garder dans `data` (nécessaire pour le payload push).
  const entityFields = {};
  for (const key of NOTIFICATION_ENTITY_FIELDS) {
    if (data[key] !== undefined) entityFields[key] = data[key];
  }

  const docId = notificationId || db.collection(NOTIFICATIONS_COLLECTION).doc().id;
  const notifRef = db.collection(NOTIFICATIONS_COLLECTION).doc(docId);

  await upsertNotificationContent({
    notifRef,
    recipientId,
    senderId,
    type,
    title,
    body,
    route,
    data,
    entityFields,
  });

  const devices = await deviceTokensFor(recipientId);
  if (devices.length === 0) {
    await markNoDevicePush(notifRef);
    return;
  }

  const claim = await claimPushSlot(notifRef);
  if (!claim.claimed) return;

  // Badge natif de l'icône de l'app (iOS) : uniquement le nombre de
  // MESSAGES de conversation non lus (`users/{uid}.unreadMessageCount`,
  // tenu à jour par `incrementChatUnread`/`markChatAsRead`), pas toutes les
  // notifications (publications, commandes, abonnements...) — se met à
  // jour via push même quand l'app n'est pas ouverte.
  const badge = await badgeCountForUser(recipientId);

  const pushData = {
    type,
    route: route ?? "",
    title: title ?? "",
    body: body ?? "",
    ...Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
  };

  try {
    const result = await fcm.sendEachForMulticast({
      tokens: devices.map((device) => device.token),
      notification: { title, body },
      data: pushData,
      android: {
        priority: "high",
        notification: { channelId: androidChannelIdForType(type) },
      },
      apns: { payload: { aps: { sound: "default", badge } } },
    });
    await applyPushResult({ notifRef, recipientId, devices, result, type, data });
  } catch (err) {
    console.error(`Erreur envoi notif -> ${recipientId} :`, err);
    // Échec global (pas un simple jeton invalide, déjà géré par
    // `applyPushResult`) : libère la réservation pour qu'une redélivrance
    // ultérieure du trigger appelant puisse retenter l'envoi.
    await notifRef
      .update({
        pushState: "failed",
        lastPushError: String(err?.code ?? err?.message ?? "erreur inconnue").slice(0, 300),
        pushClaimId: FieldValue.delete(),
        pushLeaseUntil: FieldValue.delete(),
      })
      .catch(() => {});
  }
}

const SELLER_STATISTICS_COLLECTION = "sellerStatistics";

/**
 * Incrémente un ou plusieurs compteurs de `sellerStatistics/{sellerId}`.
 * `increments` est un objet de chemins de champs (notation pointée pour les
 * champs imbriqués) -> delta, ex. `{ totalViews: 1 }` ou
 * `{ totalSales: 1, "revenue.FC": 15000 }`. Construit un objet imbriqué
 * (plutôt qu'une clé littérale contenant un point) pour que `set(...,
 * {merge:true})` fusionne correctement sans écraser les autres clés du même
 * champ imbriqué (ex. les autres devises sous `revenue`). Toujours une
 * écriture serveur (Admin SDK), jamais accessible en écriture client.
 */
async function bumpSellerStats(sellerId, increments) {
  if (!sellerId) return;
  const data = { updatedAt: FieldValue.serverTimestamp() };
  for (const [path, delta] of Object.entries(increments)) {
    const parts = path.split(".");
    let node = data;
    for (let i = 0; i < parts.length - 1; i++) {
      node[parts[i]] = node[parts[i]] ?? {};
      node = node[parts[i]];
    }
    node[parts[parts.length - 1]] = FieldValue.increment(delta);
  }
  await db
    .collection(SELLER_STATISTICS_COLLECTION)
    .doc(sellerId)
    .set(data, { merge: true });
}

const LOYALTY_POINTS_COLLECTION = "loyaltyPoints";

function loyaltyPointsDocId(buyerId, sellerId) {
  return `${buyerId}_${sellerId}`;
}

/** Points de fidélité pour un montant donné, comptés par devise (voir
 * `LOYALTY_POINTS_RATE`) — jamais de conversion FC/USD inventée. */
function pointsForAmount(currency, amount) {
  const rate = LOYALTY_POINTS_RATE[currency];
  if (!rate || !amount) return 0;
  return Math.floor(amount * rate);
}

const LOYALTY_POINTS_LEDGER_COLLECTION = "loyaltyPointsLedger";

/**
 * Crédite les points d'une commande de façon idempotente : un marqueur
 * `{orderId}_{sellerId}` empêche qu'une redélivrance du trigger
 * `onOrderCompleted` (les Cloud Functions livrent "au moins une fois") ne
 * crédite les mêmes points deux fois. Retourne `false` (no-op) si déjà
 * crédité, `true` si ce crédit vient d'avoir lieu.
 */
async function creditOrderLoyaltyPoints({ orderId, sellerId, buyerId, points }) {
  const ledgerRef = db
    .collection(LOYALTY_POINTS_LEDGER_COLLECTION)
    .doc(`${orderId}_${sellerId}`);
  const pointsRef = db
    .collection(LOYALTY_POINTS_COLLECTION)
    .doc(loyaltyPointsDocId(buyerId, sellerId));

  return db.runTransaction(async (tx) => {
    const ledgerSnap = await tx.get(ledgerRef);
    if (ledgerSnap.exists) return false;

    tx.set(ledgerRef, {
      orderId,
      sellerId,
      buyerId,
      points,
      creditedAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      pointsRef,
      {
        buyerId,
        sellerId,
        balance: FieldValue.increment(points),
        lifetimeEarned: FieldValue.increment(points),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return true;
  });
}

/**
 * Incrémente le compteur non-lu du DESTINATAIRE réel sur `chats/{chatId}`
 * (`buyerUnreadCount`/`sellerUnreadCount` selon `receiverId`), en remplacement
 * de l'ancien incrément client (interdit par les règles Firestore, qui
 * empêchent désormais toute modification client de ces compteurs — voir
 * `markChatAsRead`).
 *
 * Deux marqueurs distincts posés sur le message lui-même, dans la même
 * transaction que la décision/l'incrément, remplacent l'ancien
 * `unreadCounted` ambigu :
 * - `unreadProcessed: true` — la Cloud Function a déjà décidé du sort de ce
 *   message (une redélivrance "au moins une fois" du trigger `onNewMessage`
 *   ne le retraite jamais) ;
 * - `unreadIncrementApplied: true` — le compteur du destinataire a
 *   RÉELLEMENT été incrémenté pour ce message précis. Nécessaire pour que
 *   `markChatAsRead` sache exactement de combien décrémenter (voir plus
 *   bas) : un message déjà marqué lu avant le passage d'`onNewMessage`
 *   (course avec `markChatAsRead`) ne doit jamais incrémenter le compteur,
 *   donc `markChatAsRead` ne doit pas non plus le décompter à la lecture.
 *
 * Incrémente aussi, dans la même transaction, `users/{receiverId}.
 * unreadMessageCount` — le compteur global qui alimente le badge natif de
 * l'icône (voir `sendToUser`/`badgeCountForUser`), tenu à jour par les
 * mêmes marqueurs que le compteur par conversation.
 */
async function incrementChatUnread({ chatId, messageId, receiverId }) {
  const chatRef = db.collection("chats").doc(chatId);
  const msgRef = chatRef.collection("messages").doc(messageId);
  const receiverUserRef = db.collection("users").doc(receiverId);

  await db.runTransaction(async (tx) => {
    const msgSnap = await tx.get(msgRef);
    if (!msgSnap.exists) return;
    const msg = msgSnap.data();
    if (msg?.unreadProcessed === true) return;

    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) return;

    const buyerId = chatSnap.data()?.buyerId;
    const sellerId = chatSnap.data()?.sellerId;
    if (receiverId !== buyerId && receiverId !== sellerId) return;
    const unreadField = receiverId === buyerId ? "buyerUnreadCount" : "sellerUnreadCount";

    // Course avec `markChatAsRead` : le message a déjà été marqué lu avant
    // qu'`onNewMessage` ne s'exécute (redélivrance tardive du trigger, par
    // exemple) — ne jamais incrémenter un compteur pour un message déjà lu.
    if (msg?.status === "read") {
      tx.update(msgRef, {
        unreadProcessed: true,
        unreadIncrementApplied: false,
        unreadProcessedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    tx.update(msgRef, {
      unreadProcessed: true,
      unreadIncrementApplied: true,
      unreadProcessedAt: FieldValue.serverTimestamp(),
    });
    tx.update(chatRef, { [unreadField]: FieldValue.increment(1) });
    tx.set(receiverUserRef, { unreadMessageCount: FieldValue.increment(1) }, { merge: true });
  });
}

exports.onNewMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const msg = event.data.data();
    const receiverId = msg.receiverId;
    const senderId = msg.senderId;
    const chatId = event.params.chatId;
    const messageId = event.params.messageId;

    await incrementChatUnread({ chatId, messageId, receiverId }).catch((err) =>
      console.error(`Erreur incrementChatUnread ${chatId}/${messageId} :`, err)
    );

    const [senderDoc, receiverDoc] = await Promise.all([
      db.collection("users").doc(senderId).get(),
      db.collection("users").doc(receiverId).get(),
    ]);
    const senderName = senderDoc.data()?.name ?? "Quelqu'un";
    const content = msg.content ?? "";
    const body = content.length > 80 ? `${content.substring(0, 80)}...` : content;

    await sendToUser({
      recipientId: receiverId,
      notificationId: `message_${chatId}_${messageId}`,
      senderId,
      type: "message",
      title: `💬 ${senderName}`,
      body,
      route: `/chat/${chatId}`,
      data: { chatId, messageId },
    });

    if (receiverDoc.data()?.role === "seller") {
      await bumpSellerStats(receiverId, { totalMessages: 1 }).catch((err) =>
        console.error(`Erreur bumpSellerStats totalMessages ${receiverId} :`, err)
      );
    }

    return null;
  }
);

/**
 * Historise chaque changement de prix d'une annonce (sous-collection
 * `annonces/{annonceId}/priceHistory`, lecture publique — voir
 * `firestore.rules`) et alerte les utilisateurs ayant mis l'annonce en
 * favori quand le prix baisse (jamais à la hausse, jamais le vendeur
 * lui-même). `notificationId` inclut `event.id` (identifiant CloudEvent
 * stable pour une redélivrance du même évènement) : une redélivrance "au
 * moins une fois" du trigger ne renvoie donc jamais deux fois la même
 * alerte, tout en laissant chaque baisse de prix réelle créer sa propre
 * notification (`sendToUser` gère déjà la dédoublonnage par id de
 * document).
 */
exports.onAnnonceUpdated = onDocumentUpdated(
  "annonces/{annonceId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const annonceId = event.params.annonceId;

    const oldPrice = before.price;
    const newPrice = after.price;
    if (typeof newPrice !== "number" || typeof oldPrice !== "number" || oldPrice === newPrice) {
      return null;
    }

    const currency = after.currency ?? after.devise ?? "FC";

    // Id déterministe (event.id, stable pour une redélivrance du même
    // évènement) plutôt que .add() : une redélivrance "au moins une fois"
    // du trigger écrase donc la même entrée au lieu d'en dupliquer une.
    await db
      .collection("annonces")
      .doc(annonceId)
      .collection("priceHistory")
      .doc(event.id)
      .set({
        oldPrice,
        newPrice,
        currency,
        changedAt: FieldValue.serverTimestamp(),
      });

    if (newPrice >= oldPrice) {
      return null;
    }

    const sellerId = after.sellerId ?? after.vendeurId ?? after.userId ?? null;
    const title = after.title ?? after.titre ?? "Une annonce";

    const favorisSnap = await db
      .collection("favoris")
      .where("annonceId", "==", annonceId)
      .get();

    const recipientIds = [
      ...new Set(
        favorisSnap.docs
          .map((doc) => doc.data().utilisateurId)
          .filter((uid) => uid && uid !== sellerId)
      ),
    ];

    await Promise.all(
      recipientIds.map((recipientId) =>
        sendToUser({
          recipientId,
          notificationId: `priceDropped_${annonceId}_${recipientId}_${event.id}`,
          type: "price_drop",
          title: "📉 Baisse de prix",
          body: `${title} : le prix vient de baisser.`,
          route: `/annonce/${annonceId}`,
          data: { annonceId, listingId: annonceId },
        }).catch((err) =>
          console.error(`Erreur sendToUser priceDropped ${annonceId} -> ${recipientId} :`, err)
        )
      )
    );

    return null;
  }
);

/**
 * Alertes de recherche sauvegardée : à la publication d'une nouvelle
 * annonce, notifie chaque utilisateur ayant enregistré une alerte qui
 * correspond (mot-clé contenu dans titre/description, ville/catégorie
 * égales si renseignées dans l'alerte) — jamais le vendeur lui-même.
 * Scan complet de `searchAlerts` à chaque nouvelle annonce : le volume
 * d'usage actuel de l'app ne justifie pas un index/sharding plus complexe
 * (à revisiter si le volume grandit). `notificationId` déterministe
 * (alertId + annonceId) : idempotent sur une redélivrance du trigger.
 */
exports.onAnnonceCreated = onDocumentCreated(
  "annonces/{annonceId}",
  async (event) => {
    const annonce = event.data.data();
    const annonceId = event.params.annonceId;
    if (annonce.isPublished !== true) return null;

    const sellerId = annonce.sellerId ?? annonce.vendeurId ?? annonce.userId ?? null;
    const title = (annonce.title ?? annonce.titre ?? "").toString();
    const description = (annonce.description ?? "").toString();
    const haystack = `${title} ${description}`.toLowerCase();
    const city = annonce.city ?? annonce.ville ?? null;
    const category = annonce.category ?? annonce.categorie ?? null;

    const alertsSnap = await db.collection("searchAlerts").get();
    const matches = alertsSnap.docs.filter((doc) => {
      const alert = doc.data();
      if (!alert.userId || alert.userId === sellerId) return false;
      if (alert.keyword && !haystack.includes(String(alert.keyword).toLowerCase())) {
        return false;
      }
      if (alert.city && alert.city !== city) return false;
      if (alert.category && alert.category !== category) return false;
      return true;
    });

    await Promise.all(
      matches.map((doc) =>
        sendToUser({
          recipientId: doc.data().userId,
          notificationId: `searchAlertMatch_${doc.id}_${annonceId}`,
          type: "search_alert",
          title: "🔔 Nouvelle annonce pour ta recherche",
          body: title || "Une nouvelle annonce vient d'être publiée.",
          route: `/annonce/${annonceId}`,
          data: { annonceId, listingId: annonceId },
        }).catch((err) =>
          console.error(`Erreur sendToUser searchAlertMatch ${doc.id} -> ${annonceId} :`, err)
        )
      )
    );

    return null;
  }
);

/**
 * Cloud Function callable qui remplace l'écriture directe côté client de
 * `ChatService.sendMessage` (ancien `chat_service.dart`) : le client ne
 * choisit plus jamais `senderId`/`receiverId`/`status`, et
 * `clientMessageId` — généré localement une seule fois par l'appelant,
 * jamais régénéré sur retry — sert directement d'id de document Firestore.
 * Un rejeu (retry réseau, double appel) sur le même `clientMessageId` ne
 * crée donc jamais de doublon : la transaction détecte le document déjà
 * existant et retourne `alreadyExisted: true` sans rien réécrire (en
 * particulier sans jamais régresser `lastMessage`/`lastMessageAt` si un
 * message plus récent a été envoyé entre-temps).
 *
 * Le document créé sous `chats/{chatId}/messages/{clientMessageId}` reste
 * strictement identique à ce que le trigger `onNewMessage` attend (même
 * collection, mêmes champs) : aucune duplication de logique, le pipeline
 * d'incrément du compteur non lu et de notification s'applique tel quel.
 */
// Identifiant compatible avec un id de document Firestore : non vide,
// longueur bornée, jamais de '/' (séparateur de chemin), jamais '.'/'..'
// (nom réservé). Utilisé pour valider `chatId` et `clientMessageId` reçus
// du client avant de les utiliser dans un chemin Firestore.
function isValidDocId(value, maxLength) {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= maxLength &&
    !value.includes("/") &&
    value !== "." &&
    value !== ".."
  );
}

const CHAT_MEDIA_TYPES = new Set(["image", "video"]);

/**
 * Une URL de média n'est acceptée dans un message que si elle pointe
 * réellement vers le dossier Storage de CE chat (`chatMedia/{chatId}/...`,
 * voir `storage.rules`) : l'upload lui-même est déjà verrouillé à ce même
 * chatId côté Storage (l'appelant doit être participant pour écrire sous ce
 * chemin), cette vérification est une double protection bon marché côté
 * écriture du message — empêche qu'un participant réutilise ici l'URL d'un
 * média appartenant à une AUTRE conversation.
 */
function isValidChatMediaUrl(url, chatId) {
  if (typeof url !== "string" || url.length === 0 || url.length > 2000) {
    return false;
  }
  try {
    const parsed = new URL(url);
    // L'hôte des URLs de téléchargement Firebase Storage est toujours ce
    // domaine, quel que soit le projet/bucket (le bucket apparaît dans le
    // chemin, pas dans l'hôte) — sans ce contrôle, seul le chemin étant
    // vérifié, n'importe quelle URL externe contenant `/chatMedia/{chatId}/`
    // dans son chemin passerait la validation.
    if (parsed.hostname !== "firebasestorage.googleapis.com") {
      return false;
    }
    const pathname = decodeURIComponent(parsed.pathname);
    return pathname.includes(`/chatMedia/${chatId}/`);
  } catch {
    return false;
  }
}

/**
 * Cœur transactionnel partagé par `sendChatMessage` et
 * `forwardChatMessage` : valide la conversation cible, dérive le
 * destinataire, applique l'idempotence sur `clientMessageId` (rejeu
 * légitime vs collision hostile), écrit le document et met à jour les
 * métadonnées du chat (`lastMessage`/`lastMessageAt`/`lastSenderId`).
 * Jamais appelé directement par un client — chaque callable a déjà validé
 * ses propres paramètres avant d'entrer ici (voir `isValidChatMediaUrl`
 * pour `sendChatMessage`, qui n'est volontairement PAS réappliquée ici :
 * `forwardChatMessage` a déjà copié le média vers le dossier Storage du
 * chat CIBLE avant d'appeler cette fonction, voir
 * `copyChatMediaToTargetChat` — sauf échec de copie, auquel cas l'URL
 * d'origine est réutilisée telle quelle en dernier recours).
 */
async function writeChatMessage({
  uid,
  chatId,
  clientMessageId,
  content,
  mediaUrl,
  mediaType,
  mediaWidth,
  mediaHeight,
  forwardedFromChatId,
  forwardedFromMessageId,
}) {
  const chatRef = db.collection("chats").doc(chatId);
  const msgRef = chatRef.collection("messages").doc(clientMessageId);

  return db.runTransaction(async (tx) => {
    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) {
      throw new HttpsError("not-found", "Conversation introuvable.");
    }
    const chatData = chatSnap.data();

    // Une conversation corrompue (participants manquants/identiques) ne
    // doit jamais permettre l'envoi d'un message : mieux vaut refuser que
    // de dériver un receiverId incohérent.
    const buyerId = chatData.buyerId;
    const sellerId = chatData.sellerId;
    if (
      typeof buyerId !== "string" ||
      buyerId.length === 0 ||
      typeof sellerId !== "string" ||
      sellerId.length === 0 ||
      buyerId === sellerId
    ) {
      throw new HttpsError("failed-precondition", "Conversation invalide.");
    }
    if (uid !== buyerId && uid !== sellerId) {
      throw new HttpsError("permission-denied", "Vous ne participez pas à cette conversation.");
    }
    // Le serveur détermine seul le destinataire à partir des participants
    // réels du chat — jamais une valeur envoyée par le client.
    const receiverId = uid === buyerId ? sellerId : buyerId;
    if (!receiverId || receiverId === uid) {
      throw new HttpsError("failed-precondition", "Conversation invalide.");
    }

    // Un blocage (dans un sens ou l'autre) empêche tout nouveau message :
    // le client ne filtre aujourd'hui que sa PROPRE liste de conversations
    // (voir chat_list_screen.dart) — sans cette vérification serveur,
    // "cette personne ne pourra plus vous contacter" (promesse affichée à
    // l'écran de blocage) serait fausse, un utilisateur bloqué pouvant
    // toujours techniquement écrire dans la conversation existante.
    const [blockedByReceiver, blockedBySender] = await Promise.all([
      tx.get(
        db.collection("users").doc(receiverId).collection("blockedUsers").doc(uid)
      ),
      tx.get(
        db.collection("users").doc(uid).collection("blockedUsers").doc(receiverId)
      ),
    ]);
    if (blockedByReceiver.exists || blockedBySender.exists) {
      throw new HttpsError(
        "permission-denied",
        "Message bloqué : contact impossible entre ces deux utilisateurs."
      );
    }

    const msgSnap = await tx.get(msgRef);
    if (msgSnap.exists) {
      const existing = msgSnap.data();
      // Rejeu légitime (retry, double-tap, réponse callable perdue) :
      // même expéditeur, même contenu, même média, même id — ne rien
      // réécrire.
      if (
        existing.senderId === uid &&
        existing.clientMessageId === clientMessageId &&
        existing.content === content &&
        (existing.mediaUrl ?? null) === (mediaUrl ?? null)
      ) {
        return { chatId, messageId: clientMessageId, alreadyExisted: true };
      }
      // Collision hostile : quelqu'un d'autre a déjà utilisé cet id (jamais
      // le même expéditeur) — refuser sans rien modifier.
      if (existing.senderId !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Ce clientMessageId appartient déjà à un autre expéditeur."
        );
      }
      // Même expéditeur mais contenu différent : un vrai rejeu ne doit
      // jamais différer, refuser plutôt que de silencieusement écraser ou
      // ignorer un contenu différent.
      throw new HttpsError(
        "already-exists",
        "Un message différent existe déjà avec cet identifiant."
      );
    }

    const sentAt = Date.now();
    const doc = {
      senderId: uid,
      receiverId,
      content,
      status: "sent",
      clientMessageId,
      sentAt,
      createdAt: FieldValue.serverTimestamp(),
      unreadProcessed: false,
    };
    if (mediaUrl) {
      doc.mediaUrl = mediaUrl;
      doc.mediaType = mediaType;
      if (mediaWidth) doc.mediaWidth = mediaWidth;
      if (mediaHeight) doc.mediaHeight = mediaHeight;
    }
    if (forwardedFromChatId && forwardedFromMessageId) {
      doc.forwardedFromChatId = forwardedFromChatId;
      doc.forwardedFromMessageId = forwardedFromMessageId;
    }
    tx.set(msgRef, doc);

    const lastMessagePreview =
      content || (mediaType === "video" ? "📹 Vidéo" : "📷 Photo");
    tx.update(chatRef, {
      lastMessage: lastMessagePreview,
      lastMessageAt: sentAt,
      lastSenderId: uid,
    });
    return { chatId, messageId: clientMessageId, alreadyExisted: false };
  });
}

exports.sendChatMessage = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
  const chatId = request.data?.chatId;
  if (!isValidDocId(chatId, 200)) {
    throw new HttpsError("invalid-argument", "chatId invalide.");
  }
  const clientMessageId = request.data?.clientMessageId;
  if (!isValidDocId(clientMessageId, 128)) {
    throw new HttpsError("invalid-argument", "clientMessageId invalide.");
  }
  const rawContent = request.data?.content;
  const content = typeof rawContent === "string" ? rawContent.trim() : "";

  // Média optionnel : un message peut être une simple légende sans texte
  // tant qu'une photo/vidéo l'accompagne, mais jamais un message totalement
  // vide (ni texte ni média).
  const rawMediaUrl = request.data?.mediaUrl;
  let mediaUrl;
  let mediaType;
  if (rawMediaUrl !== undefined && rawMediaUrl !== null) {
    const rawMediaType = request.data?.mediaType;
    if (!CHAT_MEDIA_TYPES.has(rawMediaType)) {
      throw new HttpsError("invalid-argument", "mediaType invalide.");
    }
    if (!isValidChatMediaUrl(rawMediaUrl, chatId)) {
      throw new HttpsError("invalid-argument", "mediaUrl invalide.");
    }
    mediaUrl = rawMediaUrl;
    mediaType = rawMediaType;
  }

  if (content.length > 4000) {
    throw new HttpsError("invalid-argument", "content trop long (max 4000 caractères).");
  }
  if (!mediaUrl && !content) {
    throw new HttpsError("invalid-argument", "content requis (max 4000 caractères).");
  }

  const rawWidth = request.data?.mediaWidth;
  const rawHeight = request.data?.mediaHeight;
  const mediaWidth =
    typeof rawWidth === "number" && rawWidth > 0 ? Math.floor(rawWidth) : undefined;
  const mediaHeight =
    typeof rawHeight === "number" && rawHeight > 0 ? Math.floor(rawHeight) : undefined;

  return writeChatMessage({
    uid,
    chatId,
    clientMessageId,
    content,
    mediaUrl,
    mediaType,
    mediaWidth,
    mediaHeight,
  });
});

/**
 * Transfère un message existant (texte et/ou média) vers une AUTRE
 * conversation dont l'appelant est participant. Si le message source a un
 * média, le fichier Storage est copié vers le dossier du chat CIBLE (voir
 * `copyChatMediaToTargetChat`) avant l'écriture, pour que les participants
 * du chat cible (qui n'ont pas forcément participé au chat source) restent
 * couverts par `storage.rules`. `forwardedFromChatId`/`forwardedFromMessageId`
 * alimentent l'étiquette "Transféré" côté client. L'appelant doit être
 * participant des DEUX conversations (celle d'origine, pour avoir
 * légitimement pu lire ce message ; celle de destination, pour pouvoir y
 * écrire) — jamais uniquement l'une des deux. Réutilise l'idempotence de
 * `writeChatMessage` sur `clientMessageId` : un retry ne crée jamais de
 * doublon.
 */
exports.forwardChatMessage = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
  const sourceChatId = request.data?.sourceChatId;
  if (!isValidDocId(sourceChatId, 200)) {
    throw new HttpsError("invalid-argument", "sourceChatId invalide.");
  }
  const sourceMessageId = request.data?.sourceMessageId;
  if (!isValidDocId(sourceMessageId, 128)) {
    throw new HttpsError("invalid-argument", "sourceMessageId invalide.");
  }
  const targetChatId = request.data?.targetChatId;
  if (!isValidDocId(targetChatId, 200)) {
    throw new HttpsError("invalid-argument", "targetChatId invalide.");
  }
  const clientMessageId = request.data?.clientMessageId;
  if (!isValidDocId(clientMessageId, 128)) {
    throw new HttpsError("invalid-argument", "clientMessageId invalide.");
  }

  const sourceChatSnap = await db.collection("chats").doc(sourceChatId).get();
  if (!sourceChatSnap.exists) {
    throw new HttpsError("not-found", "Conversation d'origine introuvable.");
  }
  const sourceChatData = sourceChatSnap.data();
  if (uid !== sourceChatData.buyerId && uid !== sourceChatData.sellerId) {
    throw new HttpsError(
      "permission-denied",
      "Vous ne participez pas à la conversation d'origine."
    );
  }

  const sourceMsgSnap = await db
    .collection("chats")
    .doc(sourceChatId)
    .collection("messages")
    .doc(sourceMessageId)
    .get();
  if (!sourceMsgSnap.exists) {
    throw new HttpsError("not-found", "Message introuvable.");
  }
  const sourceMsg = sourceMsgSnap.data();

  // Vérifié ICI, avant toute copie Storage (pas seulement plus tard dans
  // la transaction de `writeChatMessage`) : sans ça, une copie vers le
  // dossier Storage d'un chat auquel l'appelant ne participe même pas
  // aurait déjà eu lieu avant le rejet de l'écriture Firestore.
  const targetChatSnap = await db.collection("chats").doc(targetChatId).get();
  if (!targetChatSnap.exists) {
    throw new HttpsError("not-found", "Conversation cible introuvable.");
  }
  const targetChatData = targetChatSnap.data();
  if (uid !== targetChatData.buyerId && uid !== targetChatData.sellerId) {
    throw new HttpsError(
      "permission-denied",
      "Vous ne participez pas à la conversation cible."
    );
  }
  // Même dérivation que `writeChatMessage` : le destinataire vient
  // toujours des participants réels du chat cible, jamais d'une valeur
  // client — nécessaire ici pour construire le chemin Storage attendu par
  // `storage.rules` (`chatMedia/{chatId}/{senderId}/{receiverId}/...`).
  const targetReceiverId =
    uid === targetChatData.buyerId ? targetChatData.sellerId : targetChatData.buyerId;

  const mediaUrl = sourceMsg.mediaUrl
    ? await copyChatMediaToTargetChat(
        sourceMsg.mediaUrl,
        targetChatId,
        uid,
        targetReceiverId,
        clientMessageId
      )
    : sourceMsg.mediaUrl;

  return writeChatMessage({
    uid,
    chatId: targetChatId,
    clientMessageId,
    content: sourceMsg.content ?? "",
    mediaUrl,
    mediaType: sourceMsg.mediaType,
    mediaWidth: sourceMsg.mediaWidth,
    mediaHeight: sourceMsg.mediaHeight,
    forwardedFromChatId: sourceChatId,
    forwardedFromMessageId: sourceMessageId,
  });
});

/** Taille de page pour `markChatAsRead` (marge sous la limite Firestore de
 * 500 écritures/lectures par transaction : 200 messages + 1 chat). */
const MARK_CHAT_AS_READ_PAGE_SIZE = 200;

/**
 * Cloud Function callable qui remplace l'ancienne écriture directe côté
 * client (`ChatService.markAsRead`) : le client ne modifie plus jamais
 * `buyerUnreadCount`/`sellerUnreadCount` ni le `status` des messages (voir
 * `firestore.rules`), tout passe par ici avec l'Admin SDK.
 *
 * Traite les messages non lus adressés à `request.auth.uid` par pages de
 * `MARK_CHAT_AS_READ_PAGE_SIZE`, chaque page dans sa propre transaction qui
 * relit le chat ET chaque message sélectionné (protection contre une course
 * avec `onNewMessage` : si le compteur a été incrémenté entre-temps,
 * Firestore relance automatiquement la transaction, qui relira alors la
 * valeur fraîche). Ne décompte que les messages pour lesquels
 * `unreadIncrementApplied === true` (un message déjà marqué lu avant le
 * passage d'`onNewMessage` n'a jamais incrémenté le compteur, il ne doit
 * donc jamais le décrémenter non plus). Le nouveau compteur est toujours
 * écrit comme `max(0, actuel - nombreDécompté)` — jamais un
 * `FieldValue.increment` négatif non borné — pour ne jamais pouvoir devenir
 * négatif, y compris sur un historique déjà incohérent.
 *
 * Idempotent : un second appel immédiat ne trouve plus de message non lu et
 * ne modifie rien.
 */
exports.markChatAsRead = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
  const chatId = request.data?.chatId;
  if (!chatId || typeof chatId !== "string") {
    throw new HttpsError("invalid-argument", "chatId requis.");
  }

  const chatRef = db.collection("chats").doc(chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    throw new HttpsError("not-found", "Conversation introuvable.");
  }
  const chatData = chatSnap.data();
  if (chatData.buyerId !== uid && chatData.sellerId !== uid) {
    throw new HttpsError("permission-denied", "Vous ne participez pas à cette conversation.");
  }
  const unreadField = uid === chatData.buyerId ? "buyerUnreadCount" : "sellerUnreadCount";
  const counterBefore = chatData[unreadField] ?? 0;

  let messagesMarkedRead = 0;
  const messagesRef = chatRef.collection("messages");
  const readerUserRef = db.collection("users").doc(uid);

  for (;;) {
    const pageSnap = await messagesRef
      .where("receiverId", "==", uid)
      .where("status", "!=", "read")
      .limit(MARK_CHAT_AS_READ_PAGE_SIZE)
      .get();
    if (pageSnap.empty) break;

    const markedInPage = await db.runTransaction(async (tx) => {
      const msgSnaps = await Promise.all(pageSnap.docs.map((doc) => tx.get(doc.ref)));
      const freshChatSnap = await tx.get(chatRef);
      const freshCurrent = freshChatSnap.data()?.[unreadField] ?? 0;
      const freshUserSnap = await tx.get(readerUserRef);
      const freshUserCount = freshUserSnap.data()?.unreadMessageCount ?? 0;

      let marked = 0;
      let incrementAppliedCount = 0;
      for (const snap of msgSnaps) {
        if (!snap.exists) continue;
        const data = snap.data();
        if (data.status === "read") continue;
        tx.update(snap.ref, { status: "read", readAt: FieldValue.serverTimestamp() });
        marked++;
        if (data.unreadIncrementApplied === true) incrementAppliedCount++;
      }

      if (incrementAppliedCount > 0 || marked > 0) {
        tx.update(chatRef, { [unreadField]: Math.max(0, freshCurrent - incrementAppliedCount) });
      }
      if (incrementAppliedCount > 0) {
        // Même principe que le compteur par conversation ci-dessus : jamais
        // un increment négatif non borné, toujours max(0, ...) — le badge
        // global (`users/{uid}.unreadMessageCount`) ne peut jamais devenir
        // négatif même si l'historique était incohérent.
        tx.set(
          readerUserRef,
          { unreadMessageCount: Math.max(0, freshUserCount - incrementAppliedCount) },
          { merge: true }
        );
      }
      return marked;
    });

    messagesMarkedRead += markedInPage;
    if (pageSnap.docs.length < MARK_CHAT_AS_READ_PAGE_SIZE) break;
  }

  const finalChatSnap = await chatRef.get();
  const counterAfter = finalChatSnap.data()?.[unreadField] ?? 0;

  return { messagesMarkedRead, counterBefore, counterAfter };
});

/**
 * Supprime une conversation. Remplace l'ancienne suppression client directe
 * (`ChatService.deleteChat` écrivait `chats/{chatId}.delete()` elle-même) :
 * une fois le chat supprimé, plus aucun mécanisme (`markChatAsRead`) ne peut
 * jamais décompter les messages non lus qu'il contenait du badge global
 * `users/{uid}.unreadMessageCount` — celui-ci resterait gonflé pour
 * toujours. Cette fonction décrémente donc d'abord les deux participants
 * (même principe `max(0, ...)` que `markChatAsRead`/`incrementChatUnread`,
 * jamais négatif) dans la même transaction que la suppression du document
 * `chats/{chatId}`, puis nettoie la sous-collection `messages` — jamais
 * supprimée en cascade par Firestore — via `recursiveDelete`, hors
 * transaction (incompatible avec le BulkWriter qu'il utilise en interne).
 *
 * Idempotent : un rejeu sur un chat déjà supprimé renvoie simplement
 * `{ deleted: true }` sans rien modifier de plus.
 */
exports.deleteChat = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
  const chatId = request.data?.chatId;
  if (!chatId || typeof chatId !== "string") {
    throw new HttpsError("invalid-argument", "chatId requis.");
  }

  const chatRef = db.collection("chats").doc(chatId);

  await db.runTransaction(async (tx) => {
    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) return;

    const chatData = chatSnap.data();
    if (chatData.buyerId !== uid && chatData.sellerId !== uid) {
      throw new HttpsError("permission-denied", "Vous ne participez pas à cette conversation.");
    }

    const buyerRef = db.collection("users").doc(chatData.buyerId);
    const sellerRef = db.collection("users").doc(chatData.sellerId);
    const [buyerSnap, sellerSnap] = await Promise.all([tx.get(buyerRef), tx.get(sellerRef)]);

    const buyerUnread = chatData.buyerUnreadCount ?? 0;
    const sellerUnread = chatData.sellerUnreadCount ?? 0;

    if (buyerUnread > 0) {
      const freshBuyerCount = buyerSnap.data()?.unreadMessageCount ?? 0;
      tx.set(
        buyerRef,
        { unreadMessageCount: Math.max(0, freshBuyerCount - buyerUnread) },
        { merge: true }
      );
    }
    if (sellerUnread > 0) {
      const freshSellerCount = sellerSnap.data()?.unreadMessageCount ?? 0;
      tx.set(
        sellerRef,
        { unreadMessageCount: Math.max(0, freshSellerCount - sellerUnread) },
        { merge: true }
      );
    }

    tx.delete(chatRef);
  });

  await db.recursiveDelete(chatRef.collection("messages"));

  return { deleted: true };
});

/**
 * Annonce un nouveau statut à tous les acheteurs abonnés au topic FCM
 * `new_status` (topic global, décision produit : pas de préférence par
 * catégorie/vendeur dans cette passe). Un seul appel `fcm.send({topic})` —
 * contrairement à l'ancienne implémentation, ne lit ni tous les
 * utilisateurs ni leurs sous-collections `devices` (coût Firestore
 * proportionnel au nombre d'acheteurs à chaque publication, désormais
 * géré par FCM lui-même côté abonnement au topic).
 */
exports.onNewStatus = onDocumentCreated("statuses/{statusId}", async (event) => {
  const status = event.data.data();
  const sellerName = status.sellerName ?? "Un vendeur";
  const caption = status.caption;
  const body = caption
    ? caption.length > 80
      ? `${caption.substring(0, 80)}...`
      : caption
    : "Découvrez ce nouvel article !";

  try {
    await fcm.send({
      topic: NEW_STATUS_TOPIC,
      notification: {
        title: `🛍️ ${sellerName} a publié un article`,
        body,
      },
      data: {
        type: "status",
        statusId: event.params.statusId,
      },
      android: {
        priority: "high",
        notification: { channelId: androidChannelIdForType("status") },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    });
  } catch (err) {
    console.error("Erreur envoi notif statut (topic) :", err);
  }

  return null;
});

/**
 * Bascule le like d'un statut pour l'utilisateur connecté : transaction sur
 * un document par (statut, utilisateur) `statusLikes/{statusId}_{uid}`,
 * jamais un simple `increment` client. Empêche structurellement le double
 * like (un seul document possible par utilisateur), la persistance après
 * reconnexion (état lisible depuis Firestore) et un compteur négatif (le
 * décrément n'a lieu que si le document de like existait).
 */
exports.toggleStatusLike = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  const statusId = request.data?.statusId;
  if (!statusId || typeof statusId !== "string") {
    throw new HttpsError("invalid-argument", "statusId manquant");
  }

  const statusRef = db.collection("statuses").doc(statusId);
  const likeRef = db.collection("statusLikes").doc(`${statusId}_${uid}`);

  const liked = await db.runTransaction(async (tx) => {
    const [statusSnap, likeSnap] = await Promise.all([
      tx.get(statusRef),
      tx.get(likeRef),
    ]);
    if (!statusSnap.exists) {
      throw new HttpsError("not-found", "Statut introuvable.");
    }

    if (likeSnap.exists) {
      tx.delete(likeRef);
      tx.update(statusRef, { likesCount: FieldValue.increment(-1) });
      return false;
    }

    tx.set(likeRef, {
      statusId,
      userId: uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(statusRef, { likesCount: FieldValue.increment(1) });
    return true;
  });

  return { liked };
});

/**
 * Supprime un statut : réservé au vendeur propriétaire ou à un admin.
 * Nettoie dans la foulée le fichier Storage associé et tous les
 * `statusLikes` du statut (jamais laissés orphelins), contrairement à
 * l'ancienne suppression Firestore directe côté client.
 */
exports.deleteStatus = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  const statusId = request.data?.statusId;
  if (!statusId || typeof statusId !== "string") {
    throw new HttpsError("invalid-argument", "statusId manquant");
  }

  const statusRef = db.collection("statuses").doc(statusId);
  const statusSnap = await statusRef.get();
  if (!statusSnap.exists) {
    return { status: "already_deleted" };
  }

  const status = statusSnap.data();
  if (status.sellerId !== uid) {
    await assertIsAdmin(uid);
  }

  const likesSnap = await db
    .collection("statusLikes")
    .where("statusId", "==", statusId)
    .get();

  // Découpé en lots de 400 (marge sous la limite Firestore de 500
  // écritures/batch) : un statut avec beaucoup de likes ne doit jamais
  // faire échouer sa propre suppression.
  const likeRefs = likesSnap.docs.map((doc) => doc.ref);
  const chunkSize = 400;
  let statusDeleted = false;
  for (let i = 0; i < likeRefs.length; i += chunkSize) {
    const batch = db.batch();
    if (!statusDeleted) {
      batch.delete(statusRef);
      statusDeleted = true;
    }
    for (const ref of likeRefs.slice(i, i + chunkSize)) {
      batch.delete(ref);
    }
    await batch.commit();
  }
  if (!statusDeleted) {
    await statusRef.delete();
  }

  const mediaPath = storagePathFromDownloadUrl(status.mediaUrl);
  if (mediaPath) {
    await storageBucket
      .file(mediaPath)
      .delete()
      .catch((err) => {
        if (err.code !== 404) {
          console.error(`Erreur suppression Storage statut ${statusId} :`, err);
        }
      });
  }

  return { status: "deleted" };
});

/**
 * Table canonique des formules vendeur — seule source de vérité pour le
 * montant/la durée réellement activés à la confirmation d'un paiement.
 * `paymentIntents.amount`/`durationDays`/`planName` sont écrits par le
 * client (voir `SubscriptionNotifier.submitManualSubscriptionPayment`) et
 * ne sont donc JAMAIS fiables tels quels : sans cette table, un client
 * pouvait soumettre une intention avec un `amount` dérisoire mais un
 * `durationDays` énorme, qu'un admin approuvant seulement la référence de
 * paiement (sans recalculer la durée à la main) activerait tel quel.
 * Doit rester synchronisé avec `plans` dans `lib/screens/subscription_screen.dart`.
 */
const SUBSCRIPTION_PLANS = {
  seller_monthly: { name: "Vendeur Mensuel", amount: 20000, durationDays: 30 },
};

/**
 * Recalcule le montant réel d'une commande à partir du prix ACTUEL de
 * chaque annonce (`annonces/{productId}.price`), jamais du `unitPrice`/
 * `totalPrice` fournis par le client dans `order.items` (`payment_screen.dart`
 * les écrit directement depuis le panier local, sans lien imposé entre eux
 * — un client pouvait donc soumettre n'importe quel total, découplé du
 * prix réel des articles). Retourne `null` si un article référence une
 * annonce introuvable (supprimée entre-temps) : dans ce cas, impossible de
 * vérifier, la confirmation doit être refusée plutôt que de faire
 * confiance au total déclaré.
 */
/**
 * Prix ACTUEL de l'annonce × quantité pour chaque article — jamais
 * `item.totalPrice`, fourni par le client (`order.items`, écrit
 * directement depuis le panier local par `payment_screen.dart`, sans lien
 * imposé avec le prix réel). Source unique partagée par la validation du
 * montant total (`recomputeOrderTotal`, qui refuse la confirmation si un
 * article est introuvable/invalide) ET l'attribution du revenu/des points
 * de fidélité PAR VENDEUR après confirmation (`notifySettlement`,
 * `creditOrderLoyaltyPoints`) : sans ce partage, un total globalement
 * cohérent pouvait quand même créditer chaque vendeur du `totalPrice` non
 * vérifié de ses propres articles (ex. le transférer artificiellement à
 * un autre vendeur de la même commande sans changer le total validé).
 * `verifiedTotal` vaut `null` pour un article dont l'annonce est
 * introuvable/invalide.
 *
 * `verifiedSellerId` : propriétaire RÉEL de l'annonce (`sellerId`/
 * `vendeurId`/`userId` du document `annonces`), jamais `item.sellerId`
 * déclaré par le client (même origine non fiable que `item.totalPrice` —
 * écrit directement depuis le panier local). Sans ça, un acheteur pouvait
 * mettre n'importe quel uid dans `item.sellerId`/`order.sellerIds` pour
 * faire créditer les ventes/avis d'un article à un tiers totalement
 * étranger à l'annonce. Vaut `null` si l'annonce est introuvable/invalide
 * ou n'expose aucun des trois champs propriétaire.
 */
async function verifiedItemTotals(items, getDoc) {
  if (!Array.isArray(items) || items.length === 0) return [];
  const annonceRefs = items.map((item) =>
    db.collection("annonces").doc(String(item.productId))
  );
  const annonceSnaps = await Promise.all(annonceRefs.map((ref) => getDoc(ref)));

  return items.map((item, i) => {
    const snap = annonceSnaps[i];
    if (!snap.exists) {
      return { ...item, verifiedTotal: null, verifiedSellerId: null };
    }
    const data = snap.data();
    const price = data.price;
    const quantity = Number(item.quantity) || 0;
    // Vrai vendeur = celui qui possède réellement l'annonce, JAMAIS
    // item.sellerId (100% contrôlé par le client, voir
    // lib/screens/payment_screen.dart) — sans ça un acheteur peut
    // rediriger paiement/stats/avis/points de fidélité vers un compte
    // complice sans jamais avertir le vrai vendeur. Les trois alias
    // possibles du propriétaire (voir validAnnonce côté règles Firestore).
    const verifiedSellerId = data.sellerId ?? data.vendeurId ?? data.userId ?? null;
    if (typeof price !== "number" || quantity <= 0) {
      return { ...item, verifiedTotal: null, verifiedSellerId };
    }
    return { ...item, verifiedTotal: price * quantity, verifiedSellerId };
  });
}

async function recomputeOrderTotal(tx, items) {
  const withTotals = await verifiedItemTotals(items, (ref) => tx.get(ref));
  if (withTotals.length === 0) return null;
  let total = 0;
  for (const item of withTotals) {
    if (item.verifiedTotal === null) return null;
    total += item.verifiedTotal;
  }
  return total;
}

/**
 * Applique le résultat d'un paiement (payé ou non) à Firestore : crée la
 * transaction, met à jour la commande ou active l'abonnement, et met à
 * jour l'intention de paiement elle-même.
 */
/**
 * Règle un paiement (commande ou abonnement) de façon entièrement atomique :
 * lecture de `paymentIntents/{transactionId}`, vérification qu'il est
 * encore en attente, et toutes les écritures (transactions, orders ou
 * subscriptions, users, paymentIntents) dans une seule transaction
 * Firestore — plus de fenêtre de course entre la lecture et l'écriture.
 * Si deux admins confirment en même temps (ou double-tap/retry réseau), la
 * transaction perdante relit `status` déjà `paid`/`failed` et n'applique
 * rien une seconde fois (compteurs `sellerStatistics` et date de départ
 * d'abonnement jamais doublés).
 */
async function applySettlement({
  transactionId,
  isPaid,
  paymentMethod,
  extra = {},
}) {
  const now = FieldValue.serverTimestamp();
  const intentRef = db.collection("paymentIntents").doc(transactionId);

  let outcome;
  try {
    outcome = await db.runTransaction(async (tx) => {
      const intentSnap = await tx.get(intentRef);
      if (!intentSnap.exists) {
        return { applied: false, notFound: true };
      }

      const intent = intentSnap.data();
      if (intent.status === "paid" || intent.status === "failed") {
        // Déjà réglé (double-tap admin, retry réseau, deux admins sur la
        // même ligne en même temps) : ré-appliquer doublerait les
        // compteurs sellerStatistics et réinitialiserait la date de
        // départ d'un abonnement. No-op silencieux plutôt qu'une erreur
        // bloquante.
        return { applied: false, alreadySettled: true, status: intent.status };
      }

      // Valide/recalcule AVANT toute écriture (les transactions Firestore
      // exigent toutes les lectures en premier) — `intent.amount`/
      // `durationDays`/`planName` viennent du client et ne sont jamais
      // fiables tels quels. Uniquement à l'activation réelle (`isPaid`) :
      // un rejet doit toujours pouvoir s'appliquer même si l'intention
      // était malformée.
      let subscriptionPlan = null;
      let recomputedOrderTotal = null;
      if (isPaid && intent.type === "subscription") {
        subscriptionPlan = SUBSCRIPTION_PLANS[intent.planId];
        if (!subscriptionPlan) {
          throw new HttpsError(
            "failed-precondition",
            `Formule d'abonnement inconnue (${intent.planId}) : confirmation refusée.`
          );
        }
      }
      if (isPaid && intent.type === "order" && intent.orderId) {
        const orderSnap = await tx.get(db.collection("orders").doc(intent.orderId));
        if (!orderSnap.exists) {
          throw new HttpsError("not-found", "Commande introuvable.");
        }
        recomputedOrderTotal = await recomputeOrderTotal(tx, orderSnap.data().items);
        if (recomputedOrderTotal === null) {
          throw new HttpsError(
            "failed-precondition",
            "Impossible de vérifier le montant de la commande (article introuvable) : confirmation refusée."
          );
        }
        // Tolérance d'arrondi minime (devise sans centimes en pratique) :
        // au-delà, le montant réclamé ne correspond pas au prix réel des
        // articles — refuse plutôt que d'activer un montant potentiellement
        // manipulé côté client.
        if (Math.abs(recomputedOrderTotal - intent.amount) > 1) {
          throw new HttpsError(
            "failed-precondition",
            `Montant incohérent : commande à ${intent.amount}, prix réel des articles ${recomputedOrderTotal}. Confirmation refusée.`
          );
        }
      }

      tx.set(
        db.collection("transactions").doc(transactionId),
        {
          id: transactionId,
          type: intent.type,
          userId: intent.userId,
          orderId: intent.orderId ?? null,
          planId: intent.planId ?? null,
          // Le montant enregistré (piste d'audit) doit refléter la valeur
          // VÉRIFIÉE côté serveur, jamais celle déclarée par le client —
          // sinon la tolérance d'arrondi acceptée ci-dessus laisserait un
          // écart mineur mais réel se figer dans `transactions.amount`.
          amount: subscriptionPlan
            ? subscriptionPlan.amount
            : (recomputedOrderTotal ?? intent.amount),
          currency: intent.currency ?? "FC",
          paymentMethod,
          paymentReference: intent.manualPaymentReference ?? null,
          status: isPaid ? "paid" : "failed",
          createdAt: now,
          ...extra,
        },
        { merge: true }
      );

      if (intent.type === "order" && intent.orderId) {
        const orderUpdate = {
          status: isPaid ? "paid" : "payment_failed",
          transactionId,
          updatedAt: now,
        };
        if (isPaid) {
          const paidAtDate = new Date();
          orderUpdate.paidAt = paidAtDate;
          orderUpdate.autoReleaseAt = new Date(
            paidAtDate.getTime() + ESCROW_AUTO_RELEASE_DAYS * 24 * 60 * 60 * 1000
          );
        }
        tx.set(db.collection("orders").doc(intent.orderId), orderUpdate, {
          merge: true,
        });
      }

      if (intent.type === "subscription" && isPaid && intent.userId) {
        const durationDays = subscriptionPlan.durationDays;
        const startDate = new Date();
        const expiryDate = new Date(
          startDate.getTime() + durationDays * 24 * 60 * 60 * 1000
        );

        tx.set(
          db.collection("subscriptions").doc(intent.userId),
          {
            id: intent.userId,
            userId: intent.userId,
            planId: intent.planId,
            planName: subscriptionPlan.name,
            price: subscriptionPlan.amount,
            startDate,
            expiryDate,
            isActive: true,
            paymentMethod,
            transactionId,
            updatedAt: now,
          },
          { merge: true }
        );

        tx.set(
          db.collection("users").doc(intent.userId),
          {
            sellerSubscriptionActive: true,
            sellerSubscriptionExpiresAt: expiryDate,
            updatedAt: now,
          },
          { merge: true }
        );
      }

      tx.set(
        intentRef,
        { status: isPaid ? "paid" : "failed", confirmedAt: now, ...extra },
        { merge: true }
      );

      return { applied: true, intent };
    });
  } catch (err) {
    // Un paiement déjà vérifié qui échoue à s'écrire en base est le pire des
    // cas silencieux (argent reçu, jamais reflété côté app) : log distinct et
    // explicite pour pouvoir être alerté dessus (Cloud Logging / Error
    // Reporting), plutôt que de se perdre parmi les logs normaux.
    console.error(
      `PAYMENT_ALERT applySettlement: échec d'écriture Firestore pour la transaction ${transactionId}`,
      err
    );
    throw err;
  }

  if (outcome.notFound) {
    console.error(
      `PAYMENT_ALERT applySettlement: intention de paiement introuvable pour ${transactionId}`
    );
    throw new HttpsError("not-found", "Intention de paiement introuvable");
  }
  if (outcome.alreadySettled) {
    return { status: outcome.status, alreadySettled: true };
  }

  await notifySettlement({ transactionId, intent: outcome.intent, isPaid });
  return { status: isPaid ? "paid" : "failed" };
}

/**
 * Notifie les parties concernées du résultat d'un paiement (commande
 * payée/rejetée -> acheteur puis vendeurs ; abonnement activé/rejeté ->
 * vendeur). Ne doit jamais faire échouer le règlement lui-même : erreurs
 * seulement loguées.
 */
async function notifySettlement({ transactionId, intent, isPaid }) {
  try {
    if (intent.type === "order" && intent.orderId) {
      await sendToUser({
        recipientId: intent.userId,
        notificationId: `order_${transactionId}_buyer`,
        type: "order",
        title: isPaid ? "✅ Paiement confirmé" : "❌ Paiement rejeté",
        body: isPaid
          ? "Votre commande a été validée, le vendeur va la préparer."
          : "Votre paiement n'a pas pu être vérifié. Contactez le support si besoin.",
        route: "/orders",
        data: { orderId: intent.orderId },
      });

      if (isPaid) {
        const orderSnap = await db.collection("orders").doc(intent.orderId).get();
        const order = orderSnap.data() ?? {};
        const items = order.items ?? [];
        const currency = order.currency ?? "FC";
        // Prix réels (annonces), jamais `item.totalPrice` déclaré par le
        // client — voir `verifiedItemTotals`. La commande a déjà été
        // validée en agrégat par `recomputeOrderTotal` à la confirmation ;
        // ce recalcul par article empêche un acheteur de transférer un
        // montant entre vendeurs d'une même commande multi-vendeur sans
        // changer le total.
        const verifiedItems = await verifiedItemTotals(items, (ref) => ref.get());
        // Jamais `order.sellerIds` (rempli par l'acheteur à la création de
        // la commande, voir lib/screens/payment_screen.dart) : les vrais
        // vendeurs sont dérivés des annonces réelles (`verifiedSellerId`).
        const sellerIds = [
          ...new Set(verifiedItems.map((item) => item.verifiedSellerId).filter(Boolean)),
        ];

        await Promise.all(
          sellerIds.map(async (sellerId) => {
            // Un même montant `order.total` peut couvrir plusieurs vendeurs
            // (panier multi-vendeur) : on ne crédite chacun que de son
            // propre sous-total, pas du total de la commande.
            const sellerSubtotal = verifiedItems
              .filter((item) => item.verifiedSellerId === sellerId)
              .reduce((sum, item) => sum + (item.verifiedTotal ?? 0), 0);

            await Promise.all([
              sendToUser({
                recipientId: sellerId,
                notificationId: `order_${transactionId}_seller_${sellerId}`,
                type: "order",
                title: "🛍️ Nouvelle commande payée",
                body: "Un acheteur a payé une commande. Préparez l'envoi.",
                route: "/seller-orders",
                data: { orderId: intent.orderId },
              }),
              bumpSellerStats(sellerId, {
                totalSales: 1,
                [`revenue.${currency}`]: sellerSubtotal,
              }).catch((err) =>
                console.error(`Erreur bumpSellerStats totalSales ${sellerId} :`, err)
              ),
              // Miroir public (nombre de ventes affiché sur le profil
              // vendeur, `publicProfiles/{userId}` — allow read: if
              // signedIn()) : `sellerStatistics` reste strictement
              // owner-read-only, jamais exposable directement aux
              // acheteurs.
              db
                .collection("publicProfiles")
                .doc(sellerId)
                .set(
                  { totalSales: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
                  { merge: true }
                )
                .catch((err) =>
                  console.error(`Erreur miroir publicProfiles totalSales ${sellerId} :`, err)
                ),
            ]);
          })
        );
      }
    } else if (intent.type === "subscription") {
      await sendToUser({
        recipientId: intent.userId,
        notificationId: `subscription_${transactionId}`,
        type: "subscription",
        title: isPaid ? "✅ Abonnement activé" : "❌ Abonnement rejeté",
        body: isPaid
          ? "Votre abonnement vendeur est actif."
          : "Votre paiement d'abonnement n'a pas pu être vérifié.",
        route: "/subscription",
      });
    }
  } catch (err) {
    console.error(`Erreur notification settlement ${transactionId} :`, err);
  }
}

/**
 * Vérifie que l'appelant est un administrateur (présent dans la
 * collection `admins`). Lève une erreur sinon.
 */
async function assertIsAdmin(uid) {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  const adminSnap = await db.collection("admins").doc(uid).get();
  if (!adminSnap.exists) {
    throw new HttpsError(
      "permission-denied",
      "Réservé aux administrateurs."
    );
  }
}

/**
 * Notifie tous les administrateurs dès qu'une demande d'abonnement passe à
 * `awaiting_manual_verification` (paiement Orange Money manuel envoyé par
 * le vendeur, en attente de vérification humaine). Écrit directement par
 * le client (`submitManualSubscriptionPayment`) : ce trigger est le seul
 * point d'accroche serveur, quel que soit le chemin client emprunté.
 * `sendToUser` persiste le document `notifications/{id}` même si un admin
 * n'a aucun appareil enregistré — il verra la demande à sa prochaine
 * ouverture de l'app, même sans notification push.
 */
exports.onSubscriptionAwaitingVerification = onDocumentUpdated(
  "paymentIntents/{intentId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const intentId = event.params.intentId;

    if (
      after.type !== "subscription" ||
      after.status !== "awaiting_manual_verification" ||
      before.status === "awaiting_manual_verification"
    ) {
      return null;
    }

    const adminsSnap = await db.collection("admins").get();
    await Promise.all(
      adminsSnap.docs.map((doc) =>
        sendToUser({
          recipientId: doc.id,
          notificationId: `subscription_request_${intentId}`,
          type: "subscription_request",
          title: "Nouvelle demande d'abonnement",
          body: "Un vendeur a envoyé une demande de vérification Orange Money.",
          route: "/admin/orders",
          data: {
            paymentIntentId: intentId,
            sellerId: after.userId ?? "",
            planName: after.planName ?? "",
            amount: after.amount ?? 0,
          },
        }).catch((err) =>
          console.error(
            `Erreur notification admin (abonnement) ${doc.id}/${intentId} :`,
            err
          )
        )
      )
    );

    return null;
  }
);

/**
 * Enregistre une vue unique par (annonce, visiteur connecté) : idempotent,
 * incrémente `annonces/{id}.vues` et `sellerStatistics/{sellerId}.totalViews`
 * seulement la première fois qu'un utilisateur donné consulte une annonce
 * donnée (protection anti-fraude — un même visiteur qui rouvre l'annonce
 * plusieurs fois ne la fait plus progresser). Les visiteurs non connectés ne
 * sont pas comptabilisés, faute d'identité fiable à dédupliquer.
 */
exports.recordAnnonceView = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  const annonceId = request.data?.annonceId;
  if (!annonceId || typeof annonceId !== "string") {
    throw new HttpsError("invalid-argument", "annonceId manquant");
  }

  const annonceRef = db.collection("annonces").doc(annonceId);
  const viewerRef = annonceRef.collection("viewers").doc(uid);

  await db.runTransaction(async (tx) => {
    const viewerSnap = await tx.get(viewerRef);
    if (viewerSnap.exists) return;

    const annonceSnap = await tx.get(annonceRef);
    if (!annonceSnap.exists) return;

    const annonce = annonceSnap.data();
    // Une annonce dépubliée/inactive ne doit plus progresser en vues.
    if (annonce?.isPublished !== true) return;

    const sellerId = annonce?.sellerId ?? annonce?.vendeurId;
    // Le propriétaire qui consulte sa propre annonce ne compte pas comme
    // une vue (auto-vue) — évite qu'un vendeur gonfle ses propres
    // statistiques en rouvrant ses annonces.
    if (sellerId === uid) return;

    tx.set(viewerRef, { viewedAt: FieldValue.serverTimestamp() });
    tx.update(annonceRef, { vues: FieldValue.increment(1) });

    if (sellerId) {
      tx.set(
        db.collection(SELLER_STATISTICS_COLLECTION).doc(sellerId),
        {
          totalViews: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
  });

  return { status: "ok" };
});

const REVIEW_RATING_MIN = 1;
const REVIEW_RATING_MAX = 5;
const REVIEW_COMMENT_MAX_LENGTH = 1000;
// Statuts d'une commande à partir desquels un avis peut être déposé : la
// libération du reversement au vendeur (`payout_sent`) survient APRÈS
// `completed` (voir la règle `orders` update) sans jamais y revenir — exiger
// seulement `completed` fermerait la fenêtre de dépôt d'avis dès que
// `applySettlement`/`confirmManualPayment` traite le reversement, parfois
// quelques minutes après la réception.
const REVIEWABLE_ORDER_STATUSES = new Set(["completed", "payout_sent"]);

/**
 * Dépose un avis après une commande complétée : l'acheteur note un vendeur
 * de la commande, ou un vendeur de la commande note l'acheteur.
 * `direction`/`revieweeId` sont dérivés uniquement côté serveur (jamais
 * transmis par le client) pour empêcher toute usurpation — le client ne
 * choisit que `sellerId` (lequel des vendeurs de la commande, utile pour un
 * panier multi-vendeurs, voir `sellerIds` sur `orders`), `rating` et
 * `comment`.
 *
 * Id de document déterministe `reviews/{orderId}_{sellerId}_{direction}` :
 * un avis est définitif une fois posté (pas de mise à jour ni de
 * suppression, cohérent avec l'immutabilité déjà pratiquée pour les
 * messages) — un second appel sur le même triplet retourne
 * `alreadyExisted: true` sans rien réécrire, jamais un écrasement. Une
 * commande multi-vendeurs donne donc lieu à un avis distinct par vendeur,
 * chaque vendeur déposant aussi son propre avis sur l'acheteur.
 */
exports.submitReview = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  const orderId = request.data?.orderId;
  const sellerId = request.data?.sellerId;
  const rating = request.data?.rating;
  const comment =
    typeof request.data?.comment === "string" ? request.data.comment.trim() : "";

  if (!isValidDocId(orderId, 128) || !isValidDocId(sellerId, 128)) {
    throw new HttpsError("invalid-argument", "orderId/sellerId invalide.");
  }
  if (!Number.isInteger(rating) || rating < REVIEW_RATING_MIN || rating > REVIEW_RATING_MAX) {
    throw new HttpsError("invalid-argument", "La note doit être un entier entre 1 et 5.");
  }
  if (comment.length > REVIEW_COMMENT_MAX_LENGTH) {
    throw new HttpsError("invalid-argument", "Commentaire trop long.");
  }

  const orderRef = db.collection("orders").doc(orderId);

  return db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Commande introuvable.");
    }
    const order = orderSnap.data();
    if (!REVIEWABLE_ORDER_STATUSES.has(order.status)) {
      throw new HttpsError("failed-precondition", "La commande n'est pas encore complétée.");
    }
    // Jamais `order.sellerIds` (rempli par l'acheteur à la création de la
    // commande, jamais recoupé avec les articles) : sans ça, un acheteur
    // pouvait mettre l'uid d'un tiers totalement étranger à la commande
    // dans `sellerIds` pour lui poster un faux avis (diffamatoire ou
    // complaisant), ou désigner un complice comme "vendeur" pour en
    // recevoir un. Voir `verifiedSellerId`.
    const verifiedItems = await verifiedItemTotals(order.items ?? [], (ref) => tx.get(ref));
    const realSellerIds = new Set(
      verifiedItems.map((item) => item.verifiedSellerId).filter(Boolean)
    );
    if (!realSellerIds.has(sellerId)) {
      throw new HttpsError("failed-precondition", "Ce vendeur ne fait pas partie de cette commande.");
    }

    let direction;
    let revieweeId;
    if (uid === order.buyerId) {
      direction = "buyer_to_seller";
      revieweeId = sellerId;
    } else if (uid === sellerId) {
      direction = "seller_to_buyer";
      revieweeId = order.buyerId;
    } else {
      throw new HttpsError("permission-denied", "Vous ne faites pas partie de cette commande.");
    }
    if (!revieweeId) {
      throw new HttpsError("failed-precondition", "Commande invalide.");
    }

    const reviewId = `${orderId}_${sellerId}_${direction}`;
    const reviewRef = db.collection("reviews").doc(reviewId);
    const reviewSnap = await tx.get(reviewRef);
    if (reviewSnap.exists) {
      return { alreadyExisted: true, reviewId };
    }

    const profileRef = db.collection("publicProfiles").doc(revieweeId);
    const profileSnap = await tx.get(profileRef);
    const currentSum = profileSnap.data()?.ratingSum ?? 0;
    const currentCount = profileSnap.data()?.ratingCount ?? 0;
    const newSum = currentSum + rating;
    const newCount = currentCount + 1;

    tx.set(reviewRef, {
      orderId,
      sellerId,
      reviewerId: uid,
      revieweeId,
      direction,
      rating,
      comment,
      createdAt: FieldValue.serverTimestamp(),
    });

    tx.set(
      profileRef,
      {
        ratingSum: newSum,
        ratingCount: newCount,
        averageRating: newSum / newCount,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const orderFlagField =
      direction === "buyer_to_seller" ? "buyerReviewedSellerIds" : "sellerReviewedBuyerIds";
    tx.update(orderRef, {
      [orderFlagField]: FieldValue.arrayUnion(sellerId),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { alreadyExisted: false, reviewId };
  });
});

/**
 * Confirme manuellement un paiement Orange Money envoyé directement par
 * l'acheteur ou le vendeur, après vérification humaine
 * par un admin (ex: l'admin retrouve la référence dans son appli Orange
 * Money). Fonctionne aussi bien pour une commande que pour un abonnement
 * vendeur, via la collection unifiée `paymentIntents`.
 */
exports.confirmManualPayment = onCall(async (request) => {
  await assertIsAdmin(request.auth?.uid);

  const transactionId = request.data?.transactionId;
  if (!transactionId || typeof transactionId !== "string") {
    throw new HttpsError("invalid-argument", "transactionId manquant");
  }

  // Lit le mode de paiement manuel dans la même intention que celle réglée
  // atomiquement par applySettlement (pas de lecture séparée qui rouvrirait
  // une fenêtre de course).
  const intentSnap = await db.collection("paymentIntents").doc(transactionId).get();
  const manualPaymentMethod =
    intentSnap.data()?.manualPaymentMethod ?? "Orange Money (manuel)";

  return applySettlement({
    transactionId,
    isPaid: true,
    paymentMethod: manualPaymentMethod,
    extra: { verifiedBy: request.auth.uid },
  });
});

/**
 * Rejette un paiement manuel (référence introuvable / montant incorrect).
 */
exports.rejectManualPayment = onCall(async (request) => {
  await assertIsAdmin(request.auth?.uid);

  const transactionId = request.data?.transactionId;
  if (!transactionId || typeof transactionId !== "string") {
    throw new HttpsError("invalid-argument", "transactionId manquant");
  }

  const intentSnap = await db.collection("paymentIntents").doc(transactionId).get();
  const manualPaymentMethod =
    intentSnap.data()?.manualPaymentMethod ?? "Orange Money (manuel)";

  return applySettlement({
    transactionId,
    isPaid: false,
    paymentMethod: manualPaymentMethod,
    extra: { verifiedBy: request.auth.uid },
  });
});

/**
 * Libération automatique du séquestre : si un acheteur n'a ni confirmé
 * la réception ni signalé de problème dans les délais, on considère la
 * transaction acceptée par défaut (évite qu'un acheteur de mauvaise foi
 * bloque indéfiniment les fonds d'un vendeur). Tourne une fois par jour.
 */
exports.autoReleaseEscrow = onSchedule("every 24 hours", async () => {
  const now = new Date();
  const snapshot = await db
    .collection("orders")
    .where("status", "==", "paid")
    .where("autoReleaseAt", "<=", now)
    .get();

  if (snapshot.empty) {
    console.log("autoReleaseEscrow: aucune commande à libérer.");
    return;
  }

  const batch = db.batch();
  snapshot.docs.forEach((doc) => {
    batch.set(
      doc.ref,
      {
        status: "completed",
        completedAt: FieldValue.serverTimestamp(),
        completedBy: "auto_release",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
  await batch.commit();
  console.log(`autoReleaseEscrow: ${snapshot.size} commande(s) libérée(s).`);

  await Promise.all(
    snapshot.docs.map(async (doc) => {
      const items = doc.data().items ?? [];
      // Jamais `doc.data().sellerIds` (rempli par l'acheteur) : dérivé des
      // annonces réelles, même principe que notifySettlement/onOrderCompleted.
      const verifiedItems = await verifiedItemTotals(items, (ref) => ref.get());
      const sellerIds = [
        ...new Set(verifiedItems.map((item) => item.verifiedSellerId).filter(Boolean)),
      ];
      await Promise.all(
        sellerIds.map((sellerId) =>
          sendToUser({
            recipientId: sellerId,
            notificationId: `escrow_${doc.id}_${sellerId}`,
            type: "order",
            title: "💰 Fonds libérés",
            body: "Le séquestre de votre commande a été libéré automatiquement.",
            route: "/seller-orders",
            data: { orderId: doc.id },
          }).catch((err) =>
            console.error(`Erreur notif escrow ${doc.id} -> ${sellerId} :`, err)
          )
        )
      );
    })
  );
});

/**
 * Crédite les points de fidélité (acheteur ET vendeur) à la réception
 * confirmée d'une commande — jamais au simple paiement (une commande encore
 * contestable ne doit pas générer de points). La transition vers
 * `'completed'` peut venir de trois chemins différents (confirmation
 * acheteur, libération auto du séquestre, résolution d'un litige admin) :
 * ce trigger générique sur toute mise à jour de `orders/{orderId}` est le
 * seul point d'accroche qui couvre les trois sans dupliquer la logique.
 */
exports.onOrderCompleted = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === "completed" || after.status !== "completed") {
      return null;
    }

    const orderId = event.params.orderId;
    const buyerId = after.buyerId;
    const items = after.items ?? [];
    const currency = after.currency ?? "FC";
    // Prix réels (annonces), jamais `item.totalPrice` déclaré par le
    // client — voir `verifiedItemTotals`. Sans ça, un acheteur pouvait
    // gonfler les points de fidélité d'un vendeur (ou les réduire) sans
    // changer le total de commande déjà validé à la confirmation.
    const verifiedItems = await verifiedItemTotals(items, (ref) => ref.get());
    // Jamais `after.sellerIds`/`item.sellerId` (rempli par l'acheteur à la
    // création) : dérivé des annonces réelles, seule source de vérité pour
    // savoir qui doit recevoir les points de fidélité.
    const sellerIds = [
      ...new Set(verifiedItems.map((item) => item.verifiedSellerId).filter(Boolean)),
    ];

    await Promise.all(
      sellerIds.map(async (sellerId) => {
        const sellerSubtotal = verifiedItems
          .filter((item) => item.verifiedSellerId === sellerId)
          .reduce((sum, item) => sum + (item.verifiedTotal ?? 0), 0);
        const points = pointsForAmount(currency, sellerSubtotal);
        if (points <= 0 || !buyerId) return;

        try {
          // Les triggers Cloud Functions livrent "au moins une fois" : sans
          // ce marqueur, une redélivrance du même évènement créditerait les
          // points une seconde fois (FieldValue.increment ne s'en protège
          // pas tout seul, contrairement à sendToUser qui est déjà idempotent
          // via son notificationId déterministe).
          const credited = await creditOrderLoyaltyPoints({
            orderId,
            sellerId,
            buyerId,
            points,
          });
          if (!credited) return;

          await sendToUser({
            recipientId: buyerId,
            notificationId: `loyalty_earned_${orderId}_${sellerId}`,
            type: "order",
            title: "🎁 Points de fidélité gagnés",
            body: `Vous avez gagné ${points} point(s) chez ce vendeur.`,
            route: "/loyalty-points",
            data: { orderId, sellerId },
          });

          await bumpSellerStats(sellerId, { loyaltyPoints: points });
        } catch (err) {
          console.error(
            `Erreur crédit points fidélité ${orderId} -> ${sellerId} :`,
            err
          );
        }
      })
    );

    return null;
  }
);

/**
 * Demande d'échange de points contre un article du catalogue d'un vendeur.
 * Transaction : vérifie l'article et le solde, débite les points et crée la
 * demande de façon atomique (évite tout double-usage/course entre deux
 * requêtes concurrentes sur le même solde).
 */
exports.requestGiftRedemption = onCall(async (request) => {
  const buyerId = request.auth?.uid;
  if (!buyerId) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  const itemId = request.data?.itemId;
  if (!itemId || typeof itemId !== "string") {
    throw new HttpsError("invalid-argument", "itemId manquant");
  }
  const clientRequestId = request.data?.clientRequestId;
  if (!isValidDocId(clientRequestId, 128)) {
    throw new HttpsError(
      "invalid-argument",
      "clientRequestId manquant/invalide"
    );
  }

  const itemRef = db.collection("giftCatalogItems").doc(itemId);
  // Id déterministe fourni par le client (même principe que
  // clientMessageId pour les messages de chat) : une relance après
  // timeout/coupure réseau retombe sur le MÊME document plutôt que d'en
  // créer un second, ce qui débiterait les points deux fois pour une
  // seule demande logique.
  const redemptionRef = db.collection("giftRedemptions").doc(clientRequestId);

  const { sellerId, itemTitle, pointsCost, status, alreadyExisted } =
    await db.runTransaction(async (tx) => {
      const existingSnap = await tx.get(redemptionRef);
      if (existingSnap.exists) {
        const existing = existingSnap.data();
        return {
          sellerId: existing.sellerId,
          itemTitle: existing.itemTitle,
          pointsCost: existing.pointsCost,
          status: existing.status,
          alreadyExisted: true,
        };
      }

      const itemSnap = await tx.get(itemRef);
      if (!itemSnap.exists || itemSnap.data().isActive !== true) {
        throw new HttpsError(
          "not-found",
          "Cet article n'est plus disponible."
        );
      }
      const item = itemSnap.data();
      const sellerId = item.sellerId;
      const pointsCost = item.pointsCost ?? 0;

      const pointsRef = db
        .collection(LOYALTY_POINTS_COLLECTION)
        .doc(loyaltyPointsDocId(buyerId, sellerId));
      const pointsSnap = await tx.get(pointsRef);
      const balance = pointsSnap.exists ? (pointsSnap.data().balance ?? 0) : 0;
      if (balance < pointsCost) {
        throw new HttpsError(
          "failed-precondition",
          "Solde de points insuffisant."
        );
      }

      tx.set(
        pointsRef,
        {
          buyerId,
          sellerId,
          balance: FieldValue.increment(-pointsCost),
          lifetimeRedeemed: FieldValue.increment(pointsCost),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      tx.set(redemptionRef, {
        buyerId,
        sellerId,
        itemId,
        itemTitle: item.title ?? "",
        pointsCost,
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        sellerId,
        itemTitle: item.title ?? "",
        pointsCost,
        status: "pending",
        alreadyExisted: false,
      };
    });

  if (!alreadyExisted) {
    await sendToUser({
      recipientId: sellerId,
      notificationId: `gift_redemption_${redemptionRef.id}_request`,
      type: "order",
      title: "🎁 Demande d'échange de cadeau",
      body: `Un acheteur demande "${itemTitle}" contre ${pointsCost} points.`,
      route: "/gift-redemptions",
      data: { redemptionId: redemptionRef.id },
    }).catch((err) =>
      console.error("Erreur notif requestGiftRedemption :", err)
    );
  }

  return { status, redemptionId: redemptionRef.id };
});

/**
 * Le vendeur propriétaire du catalogue (ou un admin) valide ou rejette une
 * demande d'échange. Un rejet rembourse atomiquement les points débités à
 * la demande.
 */
exports.respondToGiftRedemption = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  const redemptionId = request.data?.redemptionId;
  const decision = request.data?.decision;
  if (!redemptionId || typeof redemptionId !== "string") {
    throw new HttpsError("invalid-argument", "redemptionId manquant");
  }
  if (decision !== "fulfilled" && decision !== "rejected") {
    throw new HttpsError("invalid-argument", "decision invalide");
  }

  const redemptionRef = db.collection("giftRedemptions").doc(redemptionId);

  const { buyerId, sellerId, itemTitle } = await db.runTransaction(
    async (tx) => {
      const snap = await tx.get(redemptionRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Demande introuvable.");
      }
      const redemption = snap.data();
      if (redemption.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "Cette demande a déjà été traitée."
        );
      }

      const isOwnerSeller = redemption.sellerId === uid;
      let isCallerAdmin = false;
      if (!isOwnerSeller) {
        const adminSnap = await tx.get(db.collection("admins").doc(uid));
        isCallerAdmin = adminSnap.exists;
      }
      if (!isOwnerSeller && !isCallerAdmin) {
        throw new HttpsError(
          "permission-denied",
          "Réservé au vendeur concerné ou à un administrateur."
        );
      }

      tx.update(redemptionRef, {
        status: decision,
        reviewedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      });

      if (decision === "rejected") {
        const pointsRef = db
          .collection(LOYALTY_POINTS_COLLECTION)
          .doc(loyaltyPointsDocId(redemption.buyerId, redemption.sellerId));
        tx.set(
          pointsRef,
          {
            buyerId: redemption.buyerId,
            sellerId: redemption.sellerId,
            balance: FieldValue.increment(redemption.pointsCost),
            lifetimeRedeemed: FieldValue.increment(-redemption.pointsCost),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      return {
        buyerId: redemption.buyerId,
        sellerId: redemption.sellerId,
        itemTitle: redemption.itemTitle,
      };
    }
  );

  await sendToUser({
    recipientId: buyerId,
    notificationId: `gift_redemption_${redemptionId}_${decision}`,
    type: "order",
    title: decision === "fulfilled" ? "✅ Cadeau envoyé" : "❌ Échange refusé",
    body:
      decision === "fulfilled"
        ? `Votre échange pour "${itemTitle}" a été validé.`
        : `Votre échange pour "${itemTitle}" a été refusé, vos points ont été remboursés.`,
    route: "/loyalty-points",
    data: { redemptionId, sellerId },
  }).catch((err) =>
    console.error("Erreur notif respondToGiftRedemption :", err)
  );

  return { status: decision };
});

/**
 * Remise à zéro exceptionnelle du solde de points d'un acheteur chez un
 * vendeur donné, réservée aux admins, avec trace d'audit obligatoire
 * (motif requis).
 */
exports.adminResetLoyaltyPoints = onCall(async (request) => {
  await assertIsAdmin(request.auth?.uid);

  const buyerId = request.data?.buyerId;
  const sellerId = request.data?.sellerId;
  const reason = request.data?.reason;
  if (
    !buyerId ||
    typeof buyerId !== "string" ||
    !sellerId ||
    typeof sellerId !== "string"
  ) {
    throw new HttpsError("invalid-argument", "buyerId et sellerId requis.");
  }
  if (!reason || typeof reason !== "string" || !reason.trim()) {
    throw new HttpsError("invalid-argument", "Un motif est requis.");
  }

  const pointsRef = db
    .collection(LOYALTY_POINTS_COLLECTION)
    .doc(loyaltyPointsDocId(buyerId, sellerId));

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(pointsRef);
    const previousBalance = snap.exists ? (snap.data().balance ?? 0) : 0;

    tx.set(
      pointsRef,
      {
        buyerId,
        sellerId,
        balance: 0,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(db.collection("loyaltyPointsAuditLog").doc(), {
      targetBuyerId: buyerId,
      sellerId,
      previousBalance,
      resetBy: request.auth.uid,
      resetAt: FieldValue.serverTimestamp(),
      reason: reason.trim(),
    });
  });

  return { status: "ok" };
});

// ---------------------------------------------------------------------
// Parrainage
//
// Programme indépendant du système de fidélité par vendeur ci-dessus
// (`LOYALTY_POINTS_RATE`, `loyaltyPoints/{buyerId_sellerId}`) : le
// parrainage est une récompense plateforme, pas liée à un vendeur
// particulier, donc une nouvelle devise dédiée (`referralRewardPoints`)
// plutôt que de mélanger les deux mécanismes.
//
// Champs sur users/{uid} (voir firestore.rules — écriture exclusivement
// serveur, sauf `referredByCode` que le client peut renseigner à
// l'inscription) :
//   - referralCode           : code unique généré ici, à partager.
//   - referredByCode         : code saisi par le client à l'inscription
//                              (chaîne brute, non résolue).
//   - referredBy             : uid du parrain, résolu par onUserCreated.
//   - referralCount          : nombre de filleuls inscrits avec ce code.
//   - referralRewardGranted  : empêche tout double crédit (idempotence).
//   - referralRewardPoints   : solde de récompense, parrain et filleul.
// ---------------------------------------------------------------------

const REFERRAL_CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const REFERRAL_CODE_LENGTH = 6;
const REFERRAL_REWARD_POINTS = 5;

function randomReferralCode() {
  let code = "";
  for (let i = 0; i < REFERRAL_CODE_LENGTH; i++) {
    const index = Math.floor(Math.random() * REFERRAL_CODE_ALPHABET.length);
    code += REFERRAL_CODE_ALPHABET[index];
  }
  return code;
}

/**
 * Génère un code de parrainage garanti unique (quelques tentatives avec
 * vérification en base — l'espace de codes (32^6 ≈ 1 milliard) rend une
 * collision quasi impossible, la boucle est une garantie, pas l'attendu).
 */
async function generateUniqueReferralCode() {
  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = randomReferralCode();
    const existing = await db
      .collection("users")
      .where("referralCode", "==", candidate)
      .limit(1)
      .get();
    if (existing.empty) return candidate;
  }
  // Extrêmement improbable : on retombe sur un code plus long plutôt que
  // d'échouer l'inscription pour ça.
  return `${randomReferralCode()}${randomReferralCode()}`;
}

/**
 * Génère et enregistre le code de parrainage d'un compte qui n'en a pas
 * encore. `onUserCreated` ci-dessous ne se déclenche qu'à la CRÉATION du
 * document `users/{uid}` (onCreate) : tout compte existant avant l'ajout
 * du parrainage ne recevra jamais de `referralCode` par ce chemin, et
 * restait bloqué indéfiniment sur l'écran "Parrainage" ("code en cours de
 * génération, revenez dans un instant" — qui ne redevient jamais vrai).
 * Callable idempotente que l'écran déclenche lui-même quand il voit un
 * code manquant : ne régénère jamais un code déjà présent, pour ne
 * jamais invalider un code déjà partagé et potentiellement déjà utilisé
 * par un filleul.
 */
exports.ensureReferralCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Compte introuvable.");
  }

  const existing = snap.data()?.referralCode;
  if (existing) {
    return { referralCode: existing };
  }

  const referralCode = await generateUniqueReferralCode();
  await userRef.update({ referralCode });
  return { referralCode };
});

/**
 * À la création de tout compte : attribue son propre code de parrainage,
 * et si un code de parrain a été saisi (`referredByCode`), le résout en
 * uid et incrémente le compteur du parrain. Ne bloque jamais la création
 * du compte elle-même (déjà faite avant que ce trigger s'exécute) : un
 * code invalide ou introuvable est simplement ignoré.
 *
 * Les triggers Cloud Functions livrent "au moins une fois" : `event.data`
 * reflète toujours le document tel qu'il était À LA CRÉATION, identique à
 * chaque redélivrance — il faut donc relire l'état COURANT du document
 * pour savoir si ce trigger a déjà fait son travail, sans quoi une
 * redélivrance régénérerait `referralCode` (invalidant un code déjà
 * partagé/utilisé) et réincrémenterait `referralCount` du parrain une
 * seconde fois. Même précaution que `ensureReferralCode` ci-dessus.
 */
exports.onUserCreated = onDocumentCreated(
  "users/{userId}",
  async (event) => {
    const userId = event.params.userId;
    const data = event.data.data() ?? {};
    const userRef = db.collection("users").doc(userId);

    const currentSnap = await userRef.get();
    const current = currentSnap.data() ?? {};

    const updates = {};
    if (!current.referralCode) {
      updates.referralCode = await generateUniqueReferralCode();
    }

    const enteredCode = (data.referredByCode ?? "").trim().toUpperCase();
    if (enteredCode && !current.referredBy) {
      try {
        const match = await db
          .collection("users")
          .where("referralCode", "==", enteredCode)
          .limit(1)
          .get();
        const referrerDoc = match.docs[0];
        if (referrerDoc && referrerDoc.id !== userId) {
          updates.referredBy = referrerDoc.id;
          await referrerDoc.ref.update({
            referralCount: FieldValue.increment(1),
          });
        }
      } catch (err) {
        console.error(`Erreur résolution code parrainage ${userId} :`, err);
      }
    }

    if (Object.keys(updates).length > 0) {
      await userRef.update(updates);
    }
  }
);

/**
 * Crédite parrain et filleul une seule fois, au premier achat complété du
 * filleul. Transaction Firestore sur le document du filleul : lit
 * `referredBy`/`referralRewardGranted` et écrit atomiquement pour exclure
 * tout double crédit en cas de rejeu de l'évènement (garantie "au moins
 * une fois" des triggers Cloud Functions — même précaution que
 * `creditOrderLoyaltyPoints` plus haut).
 */
async function grantReferralRewardOnce(referredId) {
  const referredRef = db.collection("users").doc(referredId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(referredRef);
    if (!snap.exists) return null;

    const referredData = snap.data();
    const referrerId = referredData.referredBy;
    if (!referrerId || referredData.referralRewardGranted) return null;

    const referrerRef = db.collection("users").doc(referrerId);
    const referrerSnap = await tx.get(referrerRef);
    if (!referrerSnap.exists) return null;

    tx.update(referredRef, {
      referralRewardGranted: true,
      referralRewardPoints: FieldValue.increment(REFERRAL_REWARD_POINTS),
    });
    tx.update(referrerRef, {
      referralRewardPoints: FieldValue.increment(REFERRAL_REWARD_POINTS),
    });
    return { referrerId };
  });
}

/**
 * Fonction indépendante de `onOrderCompleted` ci-dessus, sur le même
 * déclencheur (Firestore autorise plusieurs fonctions sur le même
 * chemin) — ne modifie donc rien à la logique de fidélité par vendeur
 * déjà en place.
 */
exports.onReferredUserFirstOrder = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === "completed" || after.status !== "completed") {
      return null;
    }

    const buyerId = after.buyerId;
    if (!buyerId) return null;

    try {
      const granted = await grantReferralRewardOnce(buyerId);
      if (!granted) return null;

      await sendToUser({
        recipientId: granted.referrerId,
        notificationId: `referral_reward_${buyerId}`,
        type: "referral",
        title: "🎉 Récompense de parrainage",
        body: "La personne que vous avez invitée a fait son 1er achat !",
        route: "/referral",
        data: { referredUserId: buyerId },
      });
      await sendToUser({
        recipientId: buyerId,
        notificationId: `referral_bonus_${buyerId}`,
        type: "referral",
        title: "🎉 Bonus de bienvenue débloqué",
        body: "Merci pour votre premier achat, votre bonus est crédité.",
        route: "/referral",
        data: {},
      });
    } catch (err) {
      console.error(`Erreur récompense parrainage ${buyerId} :`, err);
    }
    return null;
  }
);

// Exports internes réservés aux tests (functions/test/), jamais utilisés en
// production ni déployés comme fonctions (objet brut, pas un CloudFunction
// reconnu par le CLI Firebase).
// ─────────────────────────────────────────────────────────────────────────
// pawaPay : paiement Mobile Money automatique (RDC : M-Pesa, Airtel, Orange)
// ─────────────────────────────────────────────────────────────────────────
//
// Flux : l'acheteur crée sa commande + `paymentIntents/{transactionId}`
// (comme pour Orange Money manuel), puis `startPawapayPayment` demande à
// pawaPay de prélever son portefeuille (le client valide avec son code PIN
// sur son téléphone). La confirmation arrive par `checkPawapayPayment` (interrogation par
// l'app) ou par `reconcilePawapayDeposits` (rapprochement planifié) : dans
// les deux cas le statut est RELU auprès de l'API pawaPay avec notre jeton
// (un callback n'est jamais cru sur parole), puis réglé par
// `applySettlement` — le même chemin atomique que la confirmation admin.
//
// Jeton : secret Secret Manager `PAWAPAY`, jamais dans le code.
// Environnement : `PAWAPAY_BASE_URL` (functions/.env) — sandbox par défaut.
// En sandbox, seuls les administrateurs peuvent lancer un paiement (tests).

const PAWAPAY_API_TOKEN = defineSecret("PAWAPAY");
const PAWAPAY_SANDBOX_URL = "https://api.sandbox.pawapay.io";

function pawapayBaseUrl() {
  return (process.env.PAWAPAY_BASE_URL || PAWAPAY_SANDBOX_URL).replace(/\/+$/, "");
}

function pawapayIsSandbox() {
  return pawapayBaseUrl() === PAWAPAY_SANDBOX_URL;
}

/** Opérateurs RDC pris en charge (codes « provider » de l'API v2). */
const PAWAPAY_PROVIDERS_COD = new Set([
  "VODACOM_MPESA_COD",
  "AIRTEL_COD",
  "ORANGE_COD",
]);

/** Devise Occasion → devise pawaPay (seule la RDC est ouverte pour l'instant). */
function pawapayCurrency(currency) {
  const code = String(currency || "").trim().toUpperCase();
  if (code === "FC" || code === "CDF") return "CDF";
  if (code === "USD") return "USD";
  return null;
}

/** Montant au format attendu : entier en CDF, 2 décimales max en USD. */
function pawapayAmount(amount, currency) {
  const value = Number(amount);
  if (!Number.isFinite(value) || value <= 0) return null;
  if (currency === "CDF") return String(Math.round(value));
  return String(Math.round(value * 100) / 100);
}

/** Numéro RDC au format pawaPay : 243 + 9 chiffres, sans « + ». */
function pawapayPhone(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  const normalized = digits.startsWith("243")
    ? digits
    : digits.startsWith("0")
      ? `243${digits.slice(1)}`
      : digits;
  return /^243\d{9}$/.test(normalized) ? normalized : null;
}

async function pawapayRequest(method, path, body) {
  const response = await fetch(`${pawapayBaseUrl()}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${PAWAPAY_API_TOKEN.value()}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try {
    data = await response.json();
  } catch (_) {
    data = null;
  }
  return { httpStatus: response.status, data };
}

/**
 * Statut final d'un dépôt relu auprès de pawaPay. Tolère les deux formes
 * de réponse ({status:"FOUND", data:{...}} en v2, ou l'objet direct).
 */
async function fetchPawapayDeposit(depositId) {
  const { httpStatus, data } = await pawapayRequest(
    "GET",
    `/v2/deposits/${encodeURIComponent(depositId)}`
  );
  if (httpStatus >= 400 || !data) return null;
  const deposit = data.data && typeof data.data === "object" ? data.data : data;
  if (Array.isArray(deposit)) return deposit[0] || null;
  return deposit;
}

/**
 * Applique le statut pawaPay d'un dépôt à l'intention de paiement.
 * COMPLETED → réglée « payée » (montant et devise revérifiés) ; FAILED →
 * l'intention reste en attente pour permettre un nouvel essai.
 */
async function reconcilePawapayDeposit(depositId) {
  const linkRef = db.collection("pawapayDeposits").doc(depositId);
  const linkSnap = await linkRef.get();
  if (!linkSnap.exists) return { status: "unknown" };
  const link = linkSnap.data();

  const deposit = await fetchPawapayDeposit(depositId);
  if (!deposit || !deposit.status) return { status: "pending" };
  const status = String(deposit.status).toUpperCase();

  if (status === "COMPLETED") {
    const sameAmount =
      deposit.amount == null ||
      Math.abs(Number(deposit.amount) - Number(link.amount)) < 0.01;
    const sameCurrency =
      deposit.currency == null || deposit.currency === link.currency;
    if (!sameAmount || !sameCurrency) {
      await linkRef.set(
        { status: "MISMATCH", checkedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
      console.error("pawaPay : montant/devise incohérents", depositId);
      return { status: "failed", message: "Paiement incohérent : contactez le support." };
    }
    await linkRef.set(
      { status: "COMPLETED", checkedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    const result = await applySettlement({
      transactionId: link.transactionId,
      isPaid: true,
      paymentMethod: `Mobile Money pawaPay (${link.provider})`,
      extra: { pawapayDepositId: depositId },
    });
    return { status: result.status === "failed" ? "failed" : "paid" };
  }

  if (status === "FAILED" || status === "REJECTED") {
    const reason =
      deposit.failureReason?.failureMessage ||
      deposit.failureReason?.failureCode ||
      "Paiement refusé ou annulé.";
    await linkRef.set(
      { status: "FAILED", failureReason: reason, checkedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    await db.collection("paymentIntents").doc(link.transactionId).set(
      { pawapayStatus: "FAILED", pawapayFailureReason: reason },
      { merge: true }
    );
    return { status: "failed", message: reason };
  }

  return { status: "pending" };
}

/**
 * Lance le prélèvement Mobile Money d'une commande déjà créée.
 * data : { transactionId, phoneNumber, provider }
 */
exports.startPawapayPayment = onCall(
  { secrets: [PAWAPAY_API_TOKEN] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");
    if (pawapayIsSandbox()) {
      // Mode test : aucun argent réel, réservé aux administrateurs et aux
      // comptes testeurs listés dans appConfig/payments.pawapayTesterUids
      // (ex. un compte acheteur de test).
      const config = await db.collection("appConfig").doc("payments").get();
      const testers = config.data()?.pawapayTesterUids;
      const isTester = Array.isArray(testers) && testers.includes(uid);
      if (!isTester) await assertIsAdmin(uid);
    }

    const transactionId = request.data?.transactionId;
    const provider = String(request.data?.provider || "");
    const phoneNumber = pawapayPhone(request.data?.phoneNumber);
    if (!isValidDocId(transactionId, 128)) {
      throw new HttpsError("invalid-argument", "Paiement introuvable.");
    }
    if (!PAWAPAY_PROVIDERS_COD.has(provider)) {
      throw new HttpsError("invalid-argument", "Opérateur Mobile Money non pris en charge.");
    }
    if (!phoneNumber) {
      throw new HttpsError(
        "invalid-argument",
        "Numéro Mobile Money invalide (format RDC : 243 suivi de 9 chiffres)."
      );
    }

    const intentRef = db.collection("paymentIntents").doc(transactionId);
    const intentSnap = await intentRef.get();
    if (!intentSnap.exists) throw new HttpsError("not-found", "Paiement introuvable.");
    const intent = intentSnap.data();
    if (intent.userId !== uid) {
      throw new HttpsError("permission-denied", "Ce paiement ne vous appartient pas.");
    }
    if (intent.type !== "order" || !intent.orderId) {
      throw new HttpsError("failed-precondition", "Seules les commandes se paient ainsi.");
    }
    if (intent.status === "paid" || intent.status === "failed") {
      throw new HttpsError("failed-precondition", "Ce paiement est déjà réglé.");
    }

    const currency = pawapayCurrency(intent.currency);
    if (!currency) {
      throw new HttpsError(
        "failed-precondition",
        "Le paiement Mobile Money n'est disponible qu'en FC ou en USD."
      );
    }

    // Montant revérifié côté serveur à partir des prix RÉELS des annonces.
    const orderSnap = await db.collection("orders").doc(intent.orderId).get();
    if (!orderSnap.exists || orderSnap.data().buyerId !== uid) {
      throw new HttpsError("not-found", "Commande introuvable.");
    }
    const items = await verifiedItemTotals(orderSnap.data().items, (ref) => ref.get());
    if (items.length === 0 || items.some((item) => item.verifiedTotal === null)) {
      throw new HttpsError("failed-precondition", "Un article n'est plus disponible.");
    }
    const verifiedTotal = items.reduce((sum, item) => sum + item.verifiedTotal, 0);
    if (Math.abs(verifiedTotal - Number(intent.amount)) > 1) {
      throw new HttpsError(
        "failed-precondition",
        "Le prix d'un article a changé : recommencez votre commande."
      );
    }
    const amount = pawapayAmount(verifiedTotal, currency);
    if (!amount) throw new HttpsError("failed-precondition", "Montant invalide.");

    const depositId = randomUUID();
    // Lien enregistré AVANT l'appel : même sans réponse (coupure réseau),
    // le dépôt reste rapprochable par son identifiant.
    await db.collection("pawapayDeposits").doc(depositId).set({
      depositId,
      transactionId,
      orderId: intent.orderId,
      userId: uid,
      provider,
      amount: Number(amount),
      currency,
      status: "INITIATED",
      sandbox: pawapayIsSandbox(),
      createdAt: FieldValue.serverTimestamp(),
    });
    await intentRef.set(
      {
        pawapayDepositId: depositId,
        pawapayStatus: "INITIATED",
        pawapayProvider: provider,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const { httpStatus, data } = await pawapayRequest("POST", "/v2/deposits", {
      depositId,
      amount,
      currency,
      payer: {
        type: "MMO",
        accountDetails: { phoneNumber, provider },
      },
      customerMessage: "Achat Occasion",
      clientReferenceId: intent.orderId,
      metadata: [{ orderId: intent.orderId }],
    });

    const accepted = httpStatus < 400 && data && String(data.status).toUpperCase() === "ACCEPTED";
    if (!accepted) {
      const reason =
        data?.failureReason?.failureMessage ||
        data?.failureReason?.failureCode ||
        "Paiement refusé par l'opérateur.";
      await db.collection("pawapayDeposits").doc(depositId).set(
        { status: "REJECTED", failureReason: reason },
        { merge: true }
      );
      await intentRef.set({ pawapayStatus: "REJECTED" }, { merge: true });
      console.error("pawaPay : dépôt refusé", httpStatus, JSON.stringify(data));
      throw new HttpsError("failed-precondition", reason);
    }

    await db.collection("pawapayDeposits").doc(depositId).set(
      { status: "ACCEPTED" },
      { merge: true }
    );
    await intentRef.set({ pawapayStatus: "ACCEPTED" }, { merge: true });
    return { depositId, status: "pending" };
  }
);

/** Interrogation par l'app (repli si le callback tarde). data : { transactionId } */
exports.checkPawapayPayment = onCall(
  { secrets: [PAWAPAY_API_TOKEN] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");
    const transactionId = request.data?.transactionId;
    if (!isValidDocId(transactionId, 128)) {
      throw new HttpsError("invalid-argument", "Paiement introuvable.");
    }
    const intentSnap = await db.collection("paymentIntents").doc(transactionId).get();
    if (!intentSnap.exists || intentSnap.data().userId !== uid) {
      throw new HttpsError("not-found", "Paiement introuvable.");
    }
    const intent = intentSnap.data();
    if (intent.status === "paid") return { status: "paid" };
    if (!intent.pawapayDepositId) return { status: "pending" };
    return reconcilePawapayDeposit(intent.pawapayDepositId);
  }
);

/**
 * Rapprochement périodique des dépôts pawaPay encore en attente (repli
 * sans URL publique : aucun droit IAM supplémentaire requis). Complète
 * l'interrogation par l'app si l'acheteur a fermé l'écran avant la
 * confirmation. Le callback HTTP public viendra dans une étape suivante.
 */
exports.reconcilePawapayDeposits = onSchedule(
  { schedule: "every 10 minutes", secrets: [PAWAPAY_API_TOKEN] },
  async () => {
    const since = Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
    const snapshot = await db
      .collection("pawapayDeposits")
      .where("status", "==", "ACCEPTED")
      .where("createdAt", ">=", since)
      .limit(100)
      .get();
    for (const doc of snapshot.docs) {
      try {
        await reconcilePawapayDeposit(doc.id);
      } catch (error) {
        console.error("reconcilePawapayDeposits", doc.id, error);
      }
    }
  }
);

exports._testables = {
  pawapayPhone,
  pawapayAmount,
  pawapayCurrency,
  claimPushSlot,
  applyPushResult,
  upsertNotificationContent,
  PUSH_LEASE_MS,
  badgeCountForUser,
};
