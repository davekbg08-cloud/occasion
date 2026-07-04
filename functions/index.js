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

exports.onNewMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const msg = event.data.data();
    const receiverId = msg.receiverId;
    const senderId = msg.senderId;

    const receiverDoc = await db.collection("users").doc(receiverId).get();
    const fcmToken = receiverDoc.data()?.fcmToken;
    if (!fcmToken) return null;

    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderName = senderDoc.data()?.name ?? "Quelqu'un";
    const content = msg.content ?? "";

    try {
      await fcm.send({
        token: fcmToken,
        notification: {
          title: `💬 ${senderName}`,
          body: content.length > 80 ? `${content.substring(0, 80)}...` : content,
        },
        data: {
          type: "message",
          chatId: event.params.chatId,
        },
        android: {
          priority: "high",
          notification: { channelId: "occasion_channel" },
        },
        apns: {
          payload: { aps: { sound: "default", badge: 1 } },
        },
      });
      console.log(`Notif message -> ${receiverId}`);
    } catch (err) {
      console.error("Erreur envoi notif message :", err);
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

  const tokens = buyersSnap.docs
    .map((doc) => doc.data().fcmToken)
    .filter(Boolean);

  if (tokens.length === 0) {
    console.log("Aucun acheteur avec token FCM.");
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
});
