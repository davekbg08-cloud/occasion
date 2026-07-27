// Tests réels des Cloud Functions (pas juste `node --check`) : appelle
// directement les fonctions exportées via `.run()` (fourni par
// firebase-functions v2 précisément pour ce cas d'usage) contre le vrai
// émulateur Firestore, sans mock de `firebase-admin`. À lancer avec :
//
//   firebase emulators:exec --only firestore --project demo-occasion \
//     "node --test functions/test/functions.test.js"
//
// Aucun de ces tests ne déclenche de véritable appel FCM/Storage réseau
// (voir commentaires par test) : uniquement la logique métier contre
// l'émulateur Firestore.
const test = require("node:test");
const assert = require("node:assert/strict");
const { getFirestore } = require("firebase-admin/firestore");

const functions = require("../index.js");
const db = getFirestore();

async function clearCollections(names) {
  for (const name of names) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  }
}

test.beforeEach(async () => {
  await clearCollections([
    "chats",
    "users",
    "notifications",
    "statuses",
    "statusLikes",
    "paymentIntents",
    "transactions",
    "orders",
    "subscriptions",
    "sellerStatistics",
    "annonces",
    "admins",
  ]);
});

test("incrementChatUnread (via onNewMessage) : idempotent malgré une redélivrance du trigger", async () => {
  const chatId = "chat-test-1";
  const messageId = "msg-test-1";
  await db.collection("chats").doc(chatId).set({
    buyerId: "buyer1",
    sellerId: "seller1",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });
  await db.collection("chats").doc(chatId).collection("messages").doc(messageId).set({
    senderId: "buyer1",
    receiverId: "seller1",
    content: "Bonjour",
    status: "sent",
  });
  await db.collection("users").doc("buyer1").set({ name: "Acheteur", role: "buyer" });
  await db.collection("users").doc("seller1").set({ name: "Vendeur", role: "seller" });

  const event = {
    data: {
      data: () => ({
        senderId: "buyer1",
        receiverId: "seller1",
        content: "Bonjour",
      }),
    },
    params: { chatId, messageId },
  };

  // Deux exécutions du même évènement (simule une redélivrance "au moins
  // une fois" du trigger Cloud Functions) : ne doit incrémenter qu'une
  // seule fois. `sendToUser` retourne tôt ici (aucun `devices` seedé pour
  // buyer1/seller1) : aucun appel FCM réel n'est déclenché.
  await functions.onNewMessage.run(event);
  await functions.onNewMessage.run(event);

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().sellerUnreadCount, 1);
  assert.equal(chatSnap.data().buyerUnreadCount, 0);
});

test("claimPushSlot : réserve l'envoi une seule fois, y compris pour des appels concurrents", async () => {
  const notifRef = db.collection("notifications").doc("notif-test-1");
  await notifRef.set({ recipientId: "buyer1", isRead: false });

  // Deux tentatives concurrentes (Promise.all, pas séquentielles) : un
  // simple `get()` puis `update()` séparés laisserait passer les deux ;
  // la transaction ne doit en laisser passer qu'une seule.
  const [first, second] = await Promise.all([
    functions._testables.claimPushSlot(notifRef),
    functions._testables.claimPushSlot(notifRef),
  ]);
  assert.equal([first, second].filter(Boolean).length, 1);

  // Un appel ultérieur (redélivrance) ne doit plus jamais réussir.
  const third = await functions._testables.claimPushSlot(notifRef);
  assert.equal(third, false);
});

test("toggleStatusLike : bascule aimer/ne plus aimer sans double comptage", async () => {
  await db.collection("statuses").doc("status1").set({
    sellerId: "seller1",
    likesCount: 0,
    // Pas de mediaUrl : n'affecte pas ce test (utilisé par deleteStatus).
  });

  const first = await functions.toggleStatusLike.run({
    data: { statusId: "status1" },
    auth: { uid: "buyer1" },
  });
  assert.equal(first.liked, true);
  let statusSnap = await db.collection("statuses").doc("status1").get();
  assert.equal(statusSnap.data().likesCount, 1);
  let likeSnap = await db.collection("statusLikes").doc("status1_buyer1").get();
  assert.equal(likeSnap.exists, true);

  const second = await functions.toggleStatusLike.run({
    data: { statusId: "status1" },
    auth: { uid: "buyer1" },
  });
  assert.equal(second.liked, false);
  statusSnap = await db.collection("statuses").doc("status1").get();
  assert.equal(statusSnap.data().likesCount, 0);
  likeSnap = await db.collection("statusLikes").doc("status1_buyer1").get();
  assert.equal(likeSnap.exists, false);
});

test("deleteStatus : supprime un statut avec plus de 400 likes sans dépasser la limite de batch", async () => {
  const statusId = "status-many-likes";
  // Pas de mediaUrl valide : storagePathFromDownloadUrl renvoie null, la
  // branche de suppression Storage est ignorée (aucun appel réseau réel).
  await db.collection("statuses").doc(statusId).set({
    sellerId: "seller1",
    likesCount: 450,
  });

  const likesBatch = db.batch();
  for (let i = 0; i < 450; i++) {
    likesBatch.set(db.collection("statusLikes").doc(`${statusId}_buyer${i}`), {
      statusId,
      userId: `buyer${i}`,
    });
  }
  await likesBatch.commit();

  const result = await functions.deleteStatus.run({
    data: { statusId },
    auth: { uid: "seller1" },
  });
  assert.equal(result.status, "deleted");

  const statusSnap = await db.collection("statuses").doc(statusId).get();
  assert.equal(statusSnap.exists, false);

  const remainingLikes = await db
    .collection("statusLikes")
    .where("statusId", "==", statusId)
    .get();
  assert.equal(remainingLikes.size, 0);
});

test("applySettlement (via confirmManualPayment) : deux confirmations concurrentes ne règlent qu'une seule fois", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("paymentIntents").doc("intent1").set({
    type: "order",
    userId: "buyer1",
    orderId: "order1",
    amount: 10000,
    currency: "FC",
    status: "awaiting_manual_verification",
    manualPaymentMethod: "orange_money_manual",
  });
  await db.collection("orders").doc("order1").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
    items: [{ sellerId: "seller1", totalPrice: 10000 }],
    currency: "FC",
    status: "pending_payment",
  });

  const request = {
    data: { transactionId: "intent1" },
    auth: { uid: "admin1" },
  };

  const [first, second] = await Promise.all([
    functions.confirmManualPayment.run(request),
    functions.confirmManualPayment.run(request),
  ]);
  const settled = [first, second].filter((r) => !r.alreadySettled);
  assert.equal(settled.length, 1, "une seule des deux confirmations doit réellement régler la transaction");

  const statsSnap = await db.collection("sellerStatistics").doc("seller1").get();
  assert.equal(statsSnap.data().totalSales, 1);
});

test("recordAnnonceView : refuse l'auto-vue du propriétaire et les annonces inactives", async () => {
  await db.collection("annonces").doc("annonce1").set({
    sellerId: "seller1",
    isPublished: true,
    vues: 0,
  });
  await db.collection("annonces").doc("annonce2").set({
    sellerId: "seller1",
    isPublished: false,
    vues: 0,
  });

  await functions.recordAnnonceView.run({
    data: { annonceId: "annonce1" },
    auth: { uid: "seller1" },
  });
  let snap = await db.collection("annonces").doc("annonce1").get();
  assert.equal(snap.data().vues, 0, "auto-vue du propriétaire ne doit pas compter");

  await functions.recordAnnonceView.run({
    data: { annonceId: "annonce2" },
    auth: { uid: "buyer1" },
  });
  snap = await db.collection("annonces").doc("annonce2").get();
  assert.equal(snap.data().vues, 0, "annonce non publiée ne doit pas compter de vue");

  await functions.recordAnnonceView.run({
    data: { annonceId: "annonce1" },
    auth: { uid: "buyer1" },
  });
  snap = await db.collection("annonces").doc("annonce1").get();
  assert.equal(snap.data().vues, 1, "une vraie vue d'un tiers doit compter");
});
