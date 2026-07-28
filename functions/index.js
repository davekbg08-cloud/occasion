const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");

initializeApp();

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
    default:
      return "occasion_general";
  }
}

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
 */
async function applyPushResult({ notifRef, recipientId, devices, result }) {
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
    await applyPushResult({ notifRef, recipientId, devices, result });
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
      data: { chatId },
    });

    if (receiverDoc.data()?.role === "seller") {
      await bumpSellerStats(receiverId, { totalMessages: 1 }).catch((err) =>
        console.error(`Erreur bumpSellerStats totalMessages ${receiverId} :`, err)
      );
    }

    return null;
  }
);

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
        priority: "normal",
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

      tx.set(
        db.collection("transactions").doc(transactionId),
        {
          id: transactionId,
          type: intent.type,
          userId: intent.userId,
          orderId: intent.orderId ?? null,
          planId: intent.planId ?? null,
          amount: intent.amount,
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
        const durationDays = intent.durationDays ?? 30;
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
            planName: intent.planName,
            price: intent.amount,
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
        const sellerIds = order.sellerIds ?? [];
        const items = order.items ?? [];
        const currency = order.currency ?? "FC";

        await Promise.all(
          sellerIds.map(async (sellerId) => {
            // Un même montant `order.total` peut couvrir plusieurs vendeurs
            // (panier multi-vendeur) : on ne crédite chacun que de son
            // propre sous-total, pas du total de la commande.
            const sellerSubtotal = items
              .filter((item) => item.sellerId === sellerId)
              .reduce((sum, item) => sum + (item.totalPrice ?? 0), 0);

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
    snapshot.docs.flatMap((doc) => {
      const sellerIds = doc.data().sellerIds ?? [];
      return sellerIds.map((sellerId) =>
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
    const sellerIds = after.sellerIds ?? [];

    await Promise.all(
      sellerIds.map(async (sellerId) => {
        const sellerSubtotal = items
          .filter((item) => item.sellerId === sellerId)
          .reduce((sum, item) => sum + (item.totalPrice ?? 0), 0);
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

  const itemRef = db.collection("giftCatalogItems").doc(itemId);
  const redemptionRef = db.collection("giftRedemptions").doc();

  const { sellerId, itemTitle, pointsCost } = await db.runTransaction(
    async (tx) => {
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

      return { sellerId, itemTitle: item.title ?? "", pointsCost };
    }
  );

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

  return { status: "pending", redemptionId: redemptionRef.id };
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

// Exports internes réservés aux tests (functions/test/), jamais utilisés en
// production ni déployés comme fonctions (objet brut, pas un CloudFunction
// reconnu par le CLI Firebase).
exports._testables = {
  claimPushSlot,
  applyPushResult,
  upsertNotificationContent,
  PUSH_LEASE_MS,
  badgeCountForUser,
};
