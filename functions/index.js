const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const fcm = getMessaging();

// Identifiants CinetPay côté serveur (jamais exposés au client).
// A configurer avec : firebase functions:secrets:set CINETPAY_APIKEY
//                      firebase functions:secrets:set CINETPAY_SITE_ID
const CINETPAY_APIKEY = defineSecret("CINETPAY_APIKEY");
const CINETPAY_SITE_ID = defineSecret("CINETPAY_SITE_ID");
const CINETPAY_CHECK_URL = "https://api-checkout.cinetpay.com/v2/payment/check";

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
 * Revérifie un paiement CinetPay auprès de leur API et met à jour Firestore
 * (orders / subscriptions / transactions / paymentIntents) en conséquence.
 * Idempotent : peut être appelée plusieurs fois sans effet de bord (merge).
 */
async function settleCinetPayTransaction(transactionId) {
  const intentRef = db.collection("paymentIntents").doc(transactionId);
  const intentSnap = await intentRef.get();
  if (!intentSnap.exists) {
    throw new Error(`Intent de paiement inconnu : ${transactionId}`);
  }
  const intent = intentSnap.data();

  const checkResponse = await fetch(CINETPAY_CHECK_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      apikey: CINETPAY_APIKEY.value(),
      site_id: CINETPAY_SITE_ID.value(),
      transaction_id: transactionId,
    }),
  });
  const checkResult = await checkResponse.json();
  const cinetpayStatus = checkResult?.data?.status;
  const isPaid = cinetpayStatus === "ACCEPTED";

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();

  const transactionRef = db.collection("transactions").doc(transactionId);
  batch.set(
    transactionRef,
    {
      id: transactionId,
      type: intent.type,
      userId: intent.userId,
      orderId: intent.orderId ?? null,
      planId: intent.planId ?? null,
      amount: intent.amount,
      currency: intent.currency ?? "FC",
      paymentMethod: "CinetPay",
      status: isPaid ? "paid" : "failed",
      cinetpayRawStatus: cinetpayStatus ?? "UNKNOWN",
      createdAt: now,
    },
    { merge: true }
  );

  if (intent.type === "order" && intent.orderId) {
    batch.set(
      db.collection("orders").doc(intent.orderId),
      {
        status: isPaid ? "paid" : "payment_failed",
        transactionId,
        updatedAt: now,
      },
      { merge: true }
    );
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
        paymentMethod: "CinetPay",
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
    intentRef,
    {
      status: isPaid ? "paid" : "failed",
      cinetpayRawStatus: cinetpayStatus ?? "UNKNOWN",
      confirmedAt: now,
    },
    { merge: true }
  );

  await batch.commit();
  return isPaid;
}

/**
 * Webhook CinetPay (notify_url). CinetPay appelle cette URL en POST après
 * une tentative de paiement, avec au minimum `cpm_trans_id`.
 *
 * Par sécurité on ne fait JAMAIS confiance au contenu du POST : on
 * revérifie systématiquement le statut réel auprès de l'API CinetPay
 * (endpoint /v2/payment/check) avec les identifiants secrets serveur,
 * avant de mettre à jour Firestore. C'est la seule source de vérité.
 */
exports.cinetpayNotify = onRequest(
  { secrets: [CINETPAY_APIKEY, CINETPAY_SITE_ID] },
  async (req, res) => {
    try {
      const transactionId = req.body?.cpm_trans_id || req.query?.cpm_trans_id;
      if (!transactionId) {
        console.error("cinetpayNotify: cpm_trans_id manquant");
        res.status(400).send("cpm_trans_id manquant");
        return;
      }

      const isPaid = await settleCinetPayTransaction(transactionId);
      console.log(
        `cinetpayNotify: transaction ${transactionId} -> ${
          isPaid ? "paid" : "failed"
        }`
      );
      res.status(200).send("OK");
    } catch (err) {
      console.error("cinetpayNotify: erreur", err);
      res.status(200).send("OK");
    }
  }
);

/**
 * Fonction callable depuis l'app Flutter juste après le callback
 * "waitResponse" du SDK CinetPay côté client. Permet une confirmation
 * quasi immédiate dans l'UI, sans attendre le webhook asynchrone (qui
 * reste néanmoins le filet de sécurité en arrière-plan).
 */
exports.confirmCinetPayPayment = onCall(
  { secrets: [CINETPAY_APIKEY, CINETPAY_SITE_ID] },
  async (request) => {
    const transactionId = request.data?.transactionId;
    if (!transactionId || typeof transactionId !== "string") {
      throw new HttpsError("invalid-argument", "transactionId manquant");
    }
    const isPaid = await settleCinetPayTransaction(transactionId);
    return { status: isPaid ? "paid" : "failed" };
  }
);
