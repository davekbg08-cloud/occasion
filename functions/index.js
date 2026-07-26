const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const fcm = getMessaging();

const ESCROW_AUTO_RELEASE_DAYS = 3;
const NOTIFICATIONS_COLLECTION = "notifications";
const NOTIFICATION_ENTITY_FIELDS = [
  "chatId",
  "listingId",
  "statusId",
  "orderId",
  "paymentIntentId",
  "entityId",
];

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

/**
 * Persiste une notification (historique in-app, lue par le client via
 * `notifications/{id}`) et l'envoie en push à tous les appareils du
 * destinataire. `notificationId` déterministe = idempotent (les retries
 * Cloud Functions ne créent jamais de doublon). Nettoie les jetons devenus
 * invalides.
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
  await db
    .collection(NOTIFICATIONS_COLLECTION)
    .doc(docId)
    .set(
      {
        recipientId,
        senderId,
        type,
        title,
        body,
        route,
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
        ...entityFields,
        data,
      },
      { merge: true }
    );

  const devices = await deviceTokensFor(recipientId);
  if (devices.length === 0) return;

  const pushData = {
    type,
    route: route ?? "",
    ...Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
  };

  try {
    const result = await fcm.sendEachForMulticast({
      tokens: devices.map((device) => device.token),
      notification: { title, body },
      data: pushData,
      android: { priority: "high", notification: { channelId: "occasion_channel" } },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    });

    await Promise.all(
      result.responses.map((res, i) => {
        const code = res.error?.code;
        if (
          !res.success &&
          (code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-argument")
        ) {
          return db
            .collection("users")
            .doc(recipientId)
            .collection("devices")
            .doc(devices[i].id)
            .delete()
            .catch(() => {});
        }
        return null;
      })
    );
  } catch (err) {
    console.error(`Erreur envoi notif -> ${recipientId} :`, err);
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

exports.onNewMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const msg = event.data.data();
    const receiverId = msg.receiverId;
    const senderId = msg.senderId;
    const chatId = event.params.chatId;
    const messageId = event.params.messageId;

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
      route: "/chat-list",
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

exports.onNewStatus = onDocumentCreated("statuses/{statusId}", async (event) => {
  const status = event.data.data();
  const sellerName = status.sellerName ?? "Un vendeur";
  const caption = status.caption;

  const buyersSnap = await db
    .collection("users")
    .where("role", "==", "buyer")
    .get();

  const tokenLists = await Promise.all(
    buyersSnap.docs.map((doc) => deviceTokensFor(doc.id))
  );
  const tokens = tokenLists.flat().map((device) => device.token);

  if (tokens.length === 0) {
    console.log("Aucun acheteur avec appareil enregistré.");
    return null;
  }

  const body = caption
    ? caption.length > 80
      ? `${caption.substring(0, 80)}...`
      : caption
    : "Découvrez ce nouvel article !";

  const chunkSize = 500;
  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    try {
      const result = await fcm.sendEachForMulticast({
        tokens: chunk,
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
          notification: { channelId: "occasion_channel" },
        },
        apns: {
          payload: { aps: { sound: "default" } },
        },
      });
      console.log(
        `Statut notifié : ${result.successCount} succès, ${result.failureCount} échecs (lot ${
          i / chunkSize + 1
        })`
      );
    } catch (err) {
      console.error("Erreur envoi notif statut :", err);
    }
  }

  return null;
});

/**
 * Applique le résultat d'un paiement (payé ou non) à Firestore : crée la
 * transaction, met à jour la commande ou active l'abonnement, et met à
 * jour l'intention de paiement elle-même.
 */
async function applySettlement({
  transactionId,
  intent,
  isPaid,
  paymentMethod,
  extra = {},
}) {
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();

  batch.set(
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
    batch.set(db.collection("orders").doc(intent.orderId), orderUpdate, {
      merge: true,
    });
  }

  if (intent.type === "subscription" && isPaid && intent.userId) {
    const durationDays = intent.durationDays ?? 30;
    const startDate = new Date();
    const expiryDate = new Date(
      startDate.getTime() + durationDays * 24 * 60 * 60 * 1000
    );

    batch.set(
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

    batch.set(
      db.collection("users").doc(intent.userId),
      {
        sellerSubscriptionActive: true,
        sellerSubscriptionExpiresAt: expiryDate,
        updatedAt: now,
      },
      { merge: true }
    );
  }

  batch.set(
    db.collection("paymentIntents").doc(transactionId),
    { status: isPaid ? "paid" : "failed", confirmedAt: now, ...extra },
    { merge: true }
  );

  try {
    await batch.commit();
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

  await notifySettlement({ transactionId, intent, isPaid });
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

    tx.set(viewerRef, { viewedAt: FieldValue.serverTimestamp() });
    tx.update(annonceRef, { vues: FieldValue.increment(1) });

    const sellerId =
      annonceSnap.data()?.sellerId ?? annonceSnap.data()?.vendeurId;
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

  const intentRef = db.collection("paymentIntents").doc(transactionId);
  const intentSnap = await intentRef.get();
  if (!intentSnap.exists) {
    console.error(
      `PAYMENT_ALERT confirmManualPayment: intention de paiement introuvable pour ${transactionId}`
    );
    throw new HttpsError("not-found", "Intention de paiement introuvable");
  }
  const intent = intentSnap.data();

  await applySettlement({
    transactionId,
    intent,
    isPaid: true,
    paymentMethod: intent.manualPaymentMethod ?? "Orange Money (manuel)",
    extra: { verifiedBy: request.auth.uid },
  });

  return { status: "paid" };
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

  const intentRef = db.collection("paymentIntents").doc(transactionId);
  const intentSnap = await intentRef.get();
  if (!intentSnap.exists) {
    console.error(
      `PAYMENT_ALERT rejectManualPayment: intention de paiement introuvable pour ${transactionId}`
    );
    throw new HttpsError("not-found", "Intention de paiement introuvable");
  }
  const intent = intentSnap.data();

  await applySettlement({
    transactionId,
    intent,
    isPaid: false,
    paymentMethod: intent.manualPaymentMethod ?? "Orange Money (manuel)",
    extra: { verifiedBy: request.auth.uid },
  });

  return { status: "payment_failed" };
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
