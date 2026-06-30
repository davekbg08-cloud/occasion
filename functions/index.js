const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const fcm = getMessaging();

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
