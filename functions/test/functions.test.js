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
const crypto = require("node:crypto");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

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
    "favoris",
    "reviews",
    "publicProfiles",
    "searchAlerts",
    "playPurchases",
    "statusViews",
    "statusDailyCounters",
    "loyaltyPoints",
    "giftCatalogItems",
    "giftRedemptions",
    "payoutAccounts",
    "utilisateurs",
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

  const sellerSnap = await db.collection("users").doc("seller1").get();
  assert.equal(
    sellerSnap.data().unreadMessageCount,
    1,
    "le badge global du destinataire doit suivre le compteur par conversation, sans double incrément sur redélivrance"
  );
});

test("sendToUser (via onNewMessage) : crée la notification avec isRead=false, createdAt, et aucun appareil -> pending_no_device", async () => {
  const chatId = "chat-test-notif";
  const messageId = "msg-test-notif";
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
    data: { data: () => ({ senderId: "buyer1", receiverId: "seller1", content: "Bonjour" }) },
    params: { chatId, messageId },
  };

  // Aucun `devices` seedé pour seller1 : aucun appel FCM réel n'est déclenché.
  await functions.onNewMessage.run(event);

  const notifRef = db.collection("notifications").doc(`message_${chatId}_${messageId}`);
  let notifSnap = await notifRef.get();
  assert.equal(notifSnap.data().isRead, false);
  assert.ok(notifSnap.data().createdAt, "createdAt doit être renseigné dès la création");
  assert.equal(
    notifSnap.data().pushState,
    "pending_no_device",
    "aucun appareil enregistré : ne doit jamais être marqué comme envoyé"
  );

  // L'utilisateur ouvre la notification (comme notification_provider.dart) :
  // isRead/readAt passent à true côté client.
  await notifRef.update({ isRead: true, readAt: Timestamp.now() });

  // Redélivrance du trigger (au moins une fois) : le contenu peut être
  // réactualisé, mais isRead/readAt/createdAt ne doivent jamais régresser.
  const createdAtBefore = notifSnap.data().createdAt;
  await functions.onNewMessage.run(event);

  notifSnap = await notifRef.get();
  assert.equal(notifSnap.data().isRead, true, "une redélivrance ne doit jamais rendre une notification lue à nouveau non lue");
  assert.ok(notifSnap.data().readAt, "readAt ne doit jamais être effacé par une redélivrance");
  assert.deepEqual(notifSnap.data().createdAt, createdAtBefore, "createdAt ne doit jamais changer après la création");
});

async function seedChat(chatId, { buyerUnreadCount = 0, sellerUnreadCount = 0 } = {}) {
  await db.collection("chats").doc(chatId).set({
    buyerId: "buyer1",
    sellerId: "seller1",
    buyerUnreadCount,
    sellerUnreadCount,
  });
}

function newMessageEvent(chatId, messageId, { senderId, receiverId, status } = {}) {
  return {
    data: { data: () => ({ senderId, receiverId, content: "Bonjour", status }) },
    params: { chatId, messageId },
  };
}

test("incrementChatUnread : un message déjà marqué lu avant onNewMessage (course avec markChatAsRead) n'incrémente jamais le compteur", async () => {
  const chatId = "chat-race-read-before";
  const messageId = "msg1";
  await seedChat(chatId);
  // Simule une course : le message a déjà été marqué "read" par
  // markChatAsRead avant même qu'onNewMessage ne s'exécute (redélivrance
  // tardive du trigger).
  await db.collection("chats").doc(chatId).collection("messages").doc(messageId).set({
    senderId: "buyer1",
    receiverId: "seller1",
    content: "Bonjour",
    status: "read",
  });

  await functions.onNewMessage.run(
    newMessageEvent(chatId, messageId, { senderId: "buyer1", receiverId: "seller1" })
  );

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().sellerUnreadCount, 0);

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc(messageId).get();
  assert.equal(msgSnap.data().unreadProcessed, true);
  assert.equal(msgSnap.data().unreadIncrementApplied, false);
});

test("markChatAsRead : un message compté puis lu ramène le compteur à 0", async () => {
  const chatId = "chat-mark-read-basic";
  const messageId = "msg1";
  await seedChat(chatId);
  await db.collection("chats").doc(chatId).collection("messages").doc(messageId).set({
    senderId: "buyer1",
    receiverId: "seller1",
    content: "Bonjour",
    status: "sent",
  });
  await functions.onNewMessage.run(
    newMessageEvent(chatId, messageId, { senderId: "buyer1", receiverId: "seller1" })
  );
  let chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().sellerUnreadCount, 1);

  const result = await functions.markChatAsRead.run({
    data: { chatId },
    auth: { uid: "seller1" },
  });
  assert.equal(result.messagesMarkedRead, 1);
  assert.equal(result.counterBefore, 1);
  assert.equal(result.counterAfter, 0);

  chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().sellerUnreadCount, 0);
  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc(messageId).get();
  assert.equal(msgSnap.data().status, "read");
  assert.ok(msgSnap.data().readAt);

  const sellerSnap = await db.collection("users").doc("seller1").get();
  assert.equal(
    sellerSnap.data().unreadMessageCount,
    0,
    "le badge global doit revenir à 0 en miroir du compteur de conversation"
  );
});

test("markChatAsRead : un appel répété alors qu'il n'y a plus rien à lire ne modifie rien (idempotent)", async () => {
  const chatId = "chat-mark-read-idempotent";
  await seedChat(chatId);

  const first = await functions.markChatAsRead.run({ data: { chatId }, auth: { uid: "seller1" } });
  assert.equal(first.messagesMarkedRead, 0);
  assert.equal(first.counterAfter, 0);

  const second = await functions.markChatAsRead.run({ data: { chatId }, auth: { uid: "seller1" } });
  assert.equal(second.messagesMarkedRead, 0);
  assert.equal(second.counterBefore, 0);
  assert.equal(second.counterAfter, 0);
});

test("markChatAsRead : un compteur initial à 0 sans message ne peut jamais produire une valeur négative", async () => {
  const chatId = "chat-mark-read-no-message";
  await seedChat(chatId, { sellerUnreadCount: 0 });

  const result = await functions.markChatAsRead.run({ data: { chatId }, auth: { uid: "seller1" } });
  assert.equal(result.counterAfter, 0);
  assert.ok(result.counterAfter >= 0);
});

test("markChatAsRead : un compteur historique incohérent est borné à 0, jamais négatif", async () => {
  const chatId = "chat-mark-read-inconsistent";
  // Compteur stocké volontairement TROP BAS par rapport aux messages
  // réellement marqués `unreadIncrementApplied` (historique incohérent,
  // ex. avant la migration `tool/migrate_chat_unread_processing.dart`) :
  // decompter naïvement (1 - 2) donnerait -1, ce qui ne doit jamais arriver.
  await seedChat(chatId, { sellerUnreadCount: 1 });
  for (const messageId of ["msg1", "msg2"]) {
    await db.collection("chats").doc(chatId).collection("messages").doc(messageId).set({
      senderId: "buyer1",
      receiverId: "seller1",
      content: "Bonjour",
      status: "sent",
      unreadProcessed: true,
      unreadIncrementApplied: true,
    });
  }

  const result = await functions.markChatAsRead.run({ data: { chatId }, auth: { uid: "seller1" } });
  assert.equal(result.messagesMarkedRead, 2);
  assert.equal(result.counterAfter, 0, "jamais négatif même si l'historique est incohérent");

  const sellerSnap = await db.collection("users").doc("seller1").get();
  assert.equal(
    sellerSnap.data()?.unreadMessageCount ?? 0,
    0,
    "le badge global ne doit jamais non plus devenir négatif sur un historique incohérent"
  );
});

test("markChatAsRead : reste cohérent si un nouveau message est incrémenté pendant l'appel (aucune écriture perdue)", async () => {
  const chatId = "chat-mark-read-concurrent-new-message";
  await seedChat(chatId, { sellerUnreadCount: 3 });
  for (const messageId of ["msg1", "msg2", "msg3"]) {
    await db.collection("chats").doc(chatId).collection("messages").doc(messageId).set({
      senderId: "buyer1",
      receiverId: "seller1",
      content: "Bonjour",
      status: "sent",
      unreadProcessed: true,
      unreadIncrementApplied: true,
    });
  }
  await db.collection("chats").doc(chatId).collection("messages").doc("msg-new").set({
    senderId: "buyer1",
    receiverId: "seller1",
    content: "Nouveau message",
    status: "sent",
  });

  // Lance markChatAsRead (qui traite msg1/msg2/msg3) et l'incrément serveur
  // du nouveau message en parallèle (pas séquentiellement, Promise.all) :
  // markChatAsRead relit le compteur À L'INTÉRIEUR de sa transaction, donc
  // Firestore la relance automatiquement si onNewMessage écrit le même
  // document entre-temps — aucune écriture n'est jamais perdue, quel que
  // soit l'ordre réel d'exécution (les deux issues possibles sont
  // légitimes selon que la page de markChatAsRead ait ou non capturé le
  // nouveau message avant son propre traitement ; ce qui ne doit JAMAIS
  // arriver, c'est un compteur final incohérent avec l'état réel).
  const [markResult] = await Promise.all([
    functions.markChatAsRead.run({ data: { chatId }, auth: { uid: "seller1" } }),
    functions.onNewMessage.run(
      newMessageEvent(chatId, "msg-new", { senderId: "buyer1", receiverId: "seller1" })
    ),
  ]);

  const newMsgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("msg-new").get();
  const newMessageStillUnread = newMsgSnap.data().status !== "read";

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(
    chatSnap.data().sellerUnreadCount,
    newMessageStillUnread ? 1 : 0,
    "le compteur final doit refléter exactement l'état réel des messages, sans écriture perdue"
  );
  assert.ok(markResult.messagesMarkedRead === 3 || markResult.messagesMarkedRead === 4);
});

test("markChatAsRead : ne modifie jamais le compteur de l'autre participant", async () => {
  const chatId = "chat-mark-read-cross-participant";
  await seedChat(chatId, { buyerUnreadCount: 2, sellerUnreadCount: 1 });
  await db.collection("chats").doc(chatId).collection("messages").doc("msg1").set({
    senderId: "buyer1",
    receiverId: "seller1",
    content: "Bonjour",
    status: "sent",
    unreadProcessed: true,
    unreadIncrementApplied: true,
  });

  await functions.markChatAsRead.run({ data: { chatId }, auth: { uid: "seller1" } });

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().sellerUnreadCount, 0);
  assert.equal(
    chatSnap.data().buyerUnreadCount,
    2,
    "markChatAsRead appelé par le vendeur ne doit jamais toucher le compteur de l'acheteur"
  );
});

test("markChatAsRead : refuse un utilisateur qui ne participe pas à la conversation", async () => {
  const chatId = "chat-mark-read-outsider";
  await seedChat(chatId);

  await assert.rejects(
    () => functions.markChatAsRead.run({ data: { chatId }, auth: { uid: "outsider" } }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("markChatAsRead : refuse un appel non authentifié", async () => {
  const chatId = "chat-mark-read-unauth";
  await seedChat(chatId);

  await assert.rejects(
    () => functions.markChatAsRead.run({ data: { chatId }, auth: undefined }),
    (err) => {
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
});

test("markChatAsRead : traite plusieurs pages sur une conversation avec plus de 200 messages non lus", async () => {
  const chatId = "chat-mark-read-pagination";
  const totalMessages = 250;
  await seedChat(chatId, { sellerUnreadCount: totalMessages });

  const batchSize = 400; // marge Firestore (< 500 écritures/batch)
  for (let start = 0; start < totalMessages; start += batchSize) {
    const batch = db.batch();
    const end = Math.min(start + batchSize, totalMessages);
    for (let i = start; i < end; i++) {
      batch.set(db.collection("chats").doc(chatId).collection("messages").doc(`msg${i}`), {
        senderId: "buyer1",
        receiverId: "seller1",
        content: "Bonjour",
        status: "sent",
        unreadProcessed: true,
        unreadIncrementApplied: true,
      });
    }
    await batch.commit();
  }

  const result = await functions.markChatAsRead.run({
    data: { chatId },
    auth: { uid: "seller1" },
  });
  assert.equal(result.messagesMarkedRead, totalMessages);
  assert.equal(result.counterAfter, 0);

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().sellerUnreadCount, 0);
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
  assert.equal([first, second].filter((r) => r.claimed).length, 1);

  // Tant que le bail n'a pas expiré, aucun nouvel appel ne doit réussir
  // (redélivrance immédiate du trigger appelant).
  const third = await functions._testables.claimPushSlot(notifRef);
  assert.equal(third.claimed, false);
});

test("claimPushSlot : une réservation dont le bail a expiré peut être reprise (Function crashée en plein envoi)", async () => {
  const notifRef = db.collection("notifications").doc("notif-test-lease");
  await notifRef.set({ recipientId: "buyer1", isRead: false });

  const first = await functions._testables.claimPushSlot(notifRef);
  assert.equal(first.claimed, true);

  // Simule une Function arrêtée après la réservation mais avant d'avoir
  // appliqué un résultat FCM (jamais de `pushState: sent`/`failed`) : le
  // bail est expiré manuellement plutôt que d'attendre `PUSH_LEASE_MS` en
  // temps réel.
  await notifRef.update({ pushLeaseUntil: Timestamp.fromMillis(Date.now() - 1000) });

  const second = await functions._testables.claimPushSlot(notifRef);
  assert.equal(second.claimed, true, "le bail expiré doit permettre une nouvelle réservation");
});

test("applyPushResult : un envoi FCM sans exception mais 100% en échec ne marque jamais la notification comme envoyée", async () => {
  const notifRef = db.collection("notifications").doc("notif-test-allfail");
  await notifRef.set({ recipientId: "buyer1", isRead: false, pushState: "sending" });

  await functions._testables.applyPushResult({
    notifRef,
    recipientId: "buyer1",
    devices: [{ id: "device1", token: "tok1" }],
    result: {
      successCount: 0,
      failureCount: 1,
      responses: [{ success: false, error: { code: "messaging/unavailable" } }],
    },
  });

  const snap = await notifRef.get();
  assert.equal(snap.data().pushState, "failed");
  // Une redélivrance ultérieure du trigger appelant doit pouvoir retenter :
  // aucun bail ni verrou ne doit rester posé après un échec total.
  const retry = await functions._testables.claimPushSlot(notifRef);
  assert.equal(retry.claimed, true);
});

test("applyPushResult : au moins un succès marque la notification comme réellement envoyée", async () => {
  const notifRef = db.collection("notifications").doc("notif-test-partial");
  await notifRef.set({ recipientId: "buyer1", isRead: false, pushState: "sending" });

  await functions._testables.applyPushResult({
    notifRef,
    recipientId: "buyer1",
    devices: [
      { id: "device1", token: "tok1" },
      { id: "device2", token: "tok2" },
    ],
    result: {
      successCount: 1,
      failureCount: 1,
      responses: [
        { success: true },
        { success: false, error: { code: "messaging/registration-token-not-registered" } },
      ],
    },
  });

  const snap = await notifRef.get();
  assert.equal(snap.data().pushState, "sent");
  // Le jeton définitivement invalide doit être nettoyé.
  const deviceSnap = await db.collection("users").doc("buyer1").collection("devices").doc("device2").get();
  assert.equal(deviceSnap.exists, false);
});

test("badgeCountForUser : lit unreadMessageCount, 0 si le champ ou le document est absent", async () => {
  assert.equal(
    await functions._testables.badgeCountForUser("utilisateur-inexistant"),
    0,
    "aucun document utilisateur : ne doit jamais planter, renvoie 0"
  );

  await db.collection("users").doc("buyer1").set({ name: "Acheteur" });
  assert.equal(
    await functions._testables.badgeCountForUser("buyer1"),
    0,
    "document existant mais champ absent : 0, pas d'exception"
  );

  await db.collection("users").doc("buyer1").set({ unreadMessageCount: 5 }, { merge: true });
  assert.equal(await functions._testables.badgeCountForUser("buyer1"), 5);
});

test("upsertNotificationContent : une redélivrance du trigger appelant ne réinitialise jamais isRead", async () => {
  const notifRef = db.collection("notifications").doc("notif-test-content");
  const baseArgs = {
    notifRef,
    recipientId: "buyer1",
    senderId: "seller1",
    type: "chat_message",
    title: "Titre initial",
    body: "Corps initial",
    route: "/chat-list",
    data: {},
    entityFields: {},
  };

  await functions._testables.upsertNotificationContent(baseArgs);
  await notifRef.update({ isRead: true });

  // Redélivrance avec un contenu légèrement différent (ex. le message a
  // été édité entre les deux tentatives) : le contenu doit être mis à
  // jour, mais `isRead` ne doit jamais redevenir `false`.
  await functions._testables.upsertNotificationContent({
    ...baseArgs,
    title: "Titre mis à jour",
  });

  const snap = await notifRef.get();
  assert.equal(snap.data().isRead, true, "isRead ne doit jamais être réinitialisé par une redélivrance");
  assert.equal(snap.data().title, "Titre mis à jour");
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
  await db.collection("annonces").doc("annonce1").set({ sellerId: "seller1", price: 10000 });
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
    items: [{ sellerId: "seller1", productId: "annonce1", quantity: 1, totalPrice: 10000 }],
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

test("régression : confirmManualPayment refuse une commande dont le montant déclaré ne correspond pas au prix réel des articles", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("annonces").doc("annonce-fraude").set({ sellerId: "seller1", price: 50000 });
  await db.collection("orders").doc("order-fraude").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
    items: [{ sellerId: "seller1", productId: "annonce-fraude", quantity: 1, totalPrice: 100 }],
    currency: "FC",
    status: "pending_payment",
  });
  // L'acheteur (ou un appel Firestore brut) a déclaré un montant dérisoire
  // (100) alors que l'annonce vaut réellement 50000.
  await db.collection("paymentIntents").doc("intent-fraude").set({
    type: "order",
    userId: "buyer1",
    orderId: "order-fraude",
    amount: 100,
    currency: "FC",
    status: "awaiting_manual_verification",
    manualPaymentMethod: "orange_money_manual",
  });

  await assert.rejects(
    () =>
      functions.confirmManualPayment.run({
        data: { transactionId: "intent-fraude" },
        auth: { uid: "admin1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );

  const orderSnap = await db.collection("orders").doc("order-fraude").get();
  assert.equal(orderSnap.data().status, "pending_payment", "la commande ne doit jamais passer 'paid' sur un montant incohérent");
});

test("régression : confirmManualPayment refuse un abonnement dont la formule (planId) est inconnue", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("paymentIntents").doc("intent-plan-inconnu").set({
    type: "subscription",
    userId: "seller1",
    planId: "plan_qui_n_existe_pas",
    planName: "Formule bidon",
    amount: 1,
    durationDays: 36500,
    currency: "FC",
    status: "awaiting_manual_verification",
    manualPaymentMethod: "orange_money_manual",
  });

  await assert.rejects(
    () =>
      functions.confirmManualPayment.run({
        data: { transactionId: "intent-plan-inconnu" },
        auth: { uid: "admin1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );

  const subSnap = await db.collection("subscriptions").doc("seller1").get();
  assert.equal(subSnap.exists, false, "aucun abonnement ne doit être activé sur une formule inconnue");
});

test("régression : confirmManualPayment ignore le montant/durée déclarés par le client pour un abonnement, utilise toujours la formule canonique", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  // Le client a déclaré un montant dérisoire (1) et une durée énorme
  // (36500 jours) — exactement le scénario décrit par l'audit de
  // sécurité : sans la table canonique, un admin confirmant seulement la
  // référence de paiement activerait ces valeurs telles quelles.
  await db.collection("paymentIntents").doc("intent-plan-triche").set({
    type: "subscription",
    userId: "seller1",
    planId: "seller_monthly",
    planName: "Formule Premium Gratuite",
    amount: 1,
    durationDays: 36500,
    currency: "FC",
    status: "awaiting_manual_verification",
    manualPaymentMethod: "orange_money_manual",
  });

  await functions.confirmManualPayment.run({
    data: { transactionId: "intent-plan-triche" },
    auth: { uid: "admin1" },
  });

  const subSnap = await db.collection("subscriptions").doc("seller1").get();
  assert.equal(subSnap.data().price, 7);
  assert.equal(subSnap.data().currency, "USD");
  assert.equal(subSnap.data().planName, "Vendeur Mensuel");
  const durationMs = subSnap.data().expiryDate.toMillis() - subSnap.data().startDate.toMillis();
  const durationDays = Math.round(durationMs / (24 * 60 * 60 * 1000));
  assert.equal(durationDays, 30, "la durée doit venir de la table canonique (30 jours), jamais des 36500 jours déclarés par le client");
});

test("confirmManualPayment : active la formule franc congolais (seller_monthly_fc) au montant canonique de 15 000 FC", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("paymentIntents").doc("intent-plan-fc").set({
    type: "subscription",
    userId: "seller-fc",
    planId: "seller_monthly_fc",
    planName: "Vendeur Mensuel",
    amount: 1,
    durationDays: 1,
    currency: "USD",
    status: "awaiting_manual_verification",
    manualPaymentMethod: "orange_money_manual",
  });

  await functions.confirmManualPayment.run({
    data: { transactionId: "intent-plan-fc" },
    auth: { uid: "admin1" },
  });

  const subSnap = await db.collection("subscriptions").doc("seller-fc").get();
  assert.equal(subSnap.data().price, 15000);
  assert.equal(subSnap.data().currency, "FC");
});

test("sendChatMessage : crée le message avec senderId/receiverId/status déterminés côté serveur", async () => {
  const chatId = "chat-send-basic";
  await seedChat(chatId);

  const result = await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "client-msg-1", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.alreadyExisted, false);
  assert.equal(result.messageId, "client-msg-1");

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("client-msg-1").get();
  assert.equal(msgSnap.data().senderId, "buyer1");
  assert.equal(msgSnap.data().receiverId, "seller1", "le destinataire doit être déterminé par le serveur, jamais par le client");
  assert.equal(msgSnap.data().status, "sent");
  assert.equal(msgSnap.data().content, "Bonjour");
  assert.ok(typeof msgSnap.data().sentAt === "number");

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().lastMessage, "Bonjour");
  assert.equal(chatSnap.data().lastSenderId, "buyer1");
});

test("sendChatMessage : le client ne peut jamais imposer senderId/receiverId/status (ignorés, dérivés du serveur)", async () => {
  const chatId = "chat-send-spoof";
  await seedChat(chatId);

  await functions.sendChatMessage.run({
    data: {
      chatId,
      clientMessageId: "client-msg-spoof",
      content: "Tentative",
      senderId: "seller1",
      receiverId: "buyer1",
      status: "read",
    },
    auth: { uid: "buyer1" },
  });

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("client-msg-spoof").get();
  assert.equal(msgSnap.data().senderId, "buyer1", "senderId vient de request.auth.uid, jamais du payload client");
  assert.equal(msgSnap.data().receiverId, "seller1");
  assert.equal(msgSnap.data().status, "sent");
});

test("sendChatMessage : un rejeu sur le même clientMessageId ne crée jamais de doublon ni ne régresse lastMessage", async () => {
  const chatId = "chat-send-retry";
  await seedChat(chatId);

  const first = await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "client-msg-retry", content: "Premier envoi" },
    auth: { uid: "buyer1" },
  });
  assert.equal(first.alreadyExisted, false);

  // Un message plus récent est envoyé entre-temps (simulateur d'un vrai
  // scénario : le retry arrive après qu'un autre message a déjà été
  // envoyé) — le rejeu ne doit jamais écraser lastMessage avec l'ancien
  // contenu.
  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "client-msg-2", content: "Message suivant" },
    auth: { uid: "buyer1" },
  });

  const retry = await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "client-msg-retry", content: "Premier envoi" },
    auth: { uid: "buyer1" },
  });
  assert.equal(retry.alreadyExisted, true, "un rejeu sur le même clientMessageId ne doit jamais recréer le message");

  const messagesSnap = await db.collection("chats").doc(chatId).collection("messages").get();
  assert.equal(messagesSnap.size, 2, "aucun doublon créé par le rejeu");

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(
    chatSnap.data().lastMessage,
    "Message suivant",
    "le rejeu ne doit jamais régresser lastMessage vers un contenu plus ancien"
  );
});

test("sendChatMessage : rejette un appel non authentifié, un non-participant, un contenu invalide et un chat introuvable", async () => {
  const chatId = "chat-send-rejects";
  await seedChat(chatId);

  await assert.rejects(
    () => functions.sendChatMessage.run({ data: { chatId, clientMessageId: "x", content: "Bonjour" }, auth: undefined }),
    (err) => {
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId, clientMessageId: "x", content: "Bonjour" },
        auth: { uid: "outsider" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId, clientMessageId: "x", content: "   " },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId, clientMessageId: "x", content: "x".repeat(4001) },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId: "chat-inexistant", clientMessageId: "x", content: "Bonjour" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "not-found");
      return true;
    }
  );
});

test("sendChatMessage : refuse un message si le destinataire a bloqué l'expéditeur", async () => {
  const chatId = "chat-blocked-by-receiver";
  await db.collection("chats").doc(chatId).set({
    buyerId: "buyer-block-1",
    sellerId: "seller-block-1",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });
  await db
    .collection("users")
    .doc("seller-block-1")
    .collection("blockedUsers")
    .doc("buyer-block-1")
    .set({ userId: "buyer-block-1", userName: "Buyer" });

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId, clientMessageId: "x", content: "Bonjour" },
        auth: { uid: "buyer-block-1" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );

  const msgSnap = await db
    .collection("chats")
    .doc(chatId)
    .collection("messages")
    .doc("x")
    .get();
  assert.equal(msgSnap.exists, false, "aucun message ne doit être créé");
});

test("sendChatMessage : refuse un message si l'expéditeur a lui-même bloqué le destinataire", async () => {
  const chatId = "chat-blocked-by-sender";
  await db.collection("chats").doc(chatId).set({
    buyerId: "buyer-block-2",
    sellerId: "seller-block-2",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });
  // Ici c'est le VENDEUR qui envoie, après avoir lui-même bloqué l'acheteur.
  await db
    .collection("users")
    .doc("seller-block-2")
    .collection("blockedUsers")
    .doc("buyer-block-2")
    .set({ userId: "buyer-block-2", userName: "Buyer" });

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId, clientMessageId: "x", content: "Bonjour" },
        auth: { uid: "seller-block-2" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("sendChatMessage : fonctionne normalement en l'absence de tout blocage", async () => {
  const chatId = "chat-not-blocked";
  await db.collection("chats").doc(chatId).set({
    buyerId: "buyer-noblock",
    sellerId: "seller-noblock",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });

  const result = await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "x", content: "Bonjour" },
    auth: { uid: "buyer-noblock" },
  });
  assert.equal(result.alreadyExisted, false);
});

test("sendChatMessage puis onNewMessage : le pipeline compteur non lu/badge s'applique aux messages créés via la nouvelle fonction", async () => {
  const chatId = "chat-send-then-trigger";
  await seedChat(chatId);

  const { messageId } = await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "client-msg-chain", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  // Simule le déclenchement du trigger onDocumentCreated sur le document
  // réellement créé par sendChatMessage (même pattern que les autres tests
  // onNewMessage de ce fichier).
  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc(messageId).get();
  await functions.onNewMessage.run({
    data: { data: () => msgSnap.data() },
    params: { chatId, messageId },
  });

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().sellerUnreadCount, 1);
  const sellerSnap = await db.collection("users").doc("seller1").get();
  assert.equal(sellerSnap.data().unreadMessageCount, 1);
});

test("sendChatMessage (vendeur→acheteur) : seller1 peut répondre à buyer1, compteurs/badge/notification vont bien vers l'acheteur", async () => {
  const chatId = "chat-seller-to-buyer";
  await seedChat(chatId);

  const result = await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "client-msg-reply", content: "Voici ma réponse" },
    auth: { uid: "seller1" },
  });
  assert.equal(result.alreadyExisted, false);

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("client-msg-reply").get();
  assert.equal(msgSnap.data().senderId, "seller1");
  assert.equal(msgSnap.data().receiverId, "buyer1", "le destinataire doit être l'acheteur, déterminé par le serveur");
  assert.equal(msgSnap.data().status, "sent");

  const chatSnapBefore = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnapBefore.data().lastSenderId, "seller1");

  // Simule le trigger onDocumentCreated réel, comme pour le sens acheteur→vendeur.
  await functions.onNewMessage.run({
    data: { data: () => msgSnap.data() },
    params: { chatId, messageId: "client-msg-reply" },
  });

  const chatSnapAfter = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnapAfter.data().buyerUnreadCount, 1, "le compteur non lu de l'ACHETEUR doit augmenter");
  assert.equal(chatSnapAfter.data().sellerUnreadCount, 0, "le compteur du vendeur (expéditeur) ne doit jamais changer");

  const buyerSnap = await db.collection("users").doc("buyer1").get();
  assert.equal(buyerSnap.data().unreadMessageCount, 1, "le badge global de l'acheteur doit augmenter");
  const sellerUserSnap = await db.collection("users").doc("seller1").get();
  assert.equal(
    sellerUserSnap.data()?.unreadMessageCount ?? 0,
    0,
    "le badge global du vendeur (expéditeur) ne doit jamais changer"
  );

  const notifSnap = await db.collection("notifications").doc(`message_${chatId}_client-msg-reply`).get();
  assert.equal(notifSnap.exists, true, "une notification doit être créée pour ce message");
  assert.equal(notifSnap.data().recipientId, "buyer1", "la notification doit cibler l'acheteur, jamais l'expéditeur");
  assert.equal(notifSnap.data().route, `/chat/${chatId}`, "la notification doit ouvrir la bonne conversation");
});

test(
  "sendChatMessage : deux appels PARALLÈLES avec le même clientMessageId ne créent qu'un seul document, un seul incrément, une seule notification",
  async () => {
    const chatId = "chat-concurrent-same-id";
    await seedChat(chatId);

    const call = () =>
      functions.sendChatMessage.run({
        data: { chatId, clientMessageId: "client-msg-concurrent", content: "Bonjour" },
        auth: { uid: "buyer1" },
      });
    const [first, second] = await Promise.all([call(), call()]);

    // L'un des deux (peu importe lequel) a créé le message, l'autre a
    // reconnu un rejeu — jamais les deux `alreadyExisted: false`.
    const createdCount = [first, second].filter((r) => r.alreadyExisted === false).length;
    assert.equal(createdCount, 1, "un seul des deux appels concurrents doit avoir réellement créé le message");

    const messagesSnap = await db
      .collection("chats")
      .doc(chatId)
      .collection("messages")
      .get();
    assert.equal(messagesSnap.size, 1, "aucun doublon même avec deux appels strictement simultanés");

    const msgSnap = messagesSnap.docs[0];
    await functions.onNewMessage.run({
      data: { data: () => msgSnap.data() },
      params: { chatId, messageId: msgSnap.id },
    });
    // Un seul incrément malgré le message unique traité une seule fois par
    // le trigger (le trigger lui-même n'est déclenché qu'une fois ici, ce
    // qui reflète la réalité : un seul document créé = un seul trigger).
    const chatSnap = await db.collection("chats").doc(chatId).get();
    assert.equal(chatSnap.data().sellerUnreadCount, 1);
    const notifsSnap = await db
      .collection("notifications")
      .where("recipientId", "==", "seller1")
      .get();
    assert.equal(notifsSnap.size, 1, "une seule notification, jamais deux, pour ce message unique");
  }
);

test(
  "sendChatMessage : une collision avec l'identifiant d'un message d'un autre expéditeur est refusée sans rien modifier",
  async () => {
    const chatId = "chat-hostile-collision";
    await seedChat(chatId);

    await functions.sendChatMessage.run({
      data: { chatId, clientMessageId: "shared-id", content: "Message légitime du vendeur" },
      auth: { uid: "seller1" },
    });

    await assert.rejects(
      () =>
        functions.sendChatMessage.run({
          data: { chatId, clientMessageId: "shared-id", content: "Tentative malveillante" },
          auth: { uid: "buyer1" },
        }),
      (err) => {
        assert.equal(err.code, "permission-denied");
        return true;
      }
    );

    const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("shared-id").get();
    assert.equal(msgSnap.data().senderId, "seller1", "le message original n'a jamais été modifié");
    assert.equal(msgSnap.data().content, "Message légitime du vendeur");

    const messagesSnap = await db.collection("chats").doc(chatId).collection("messages").get();
    assert.equal(messagesSnap.size, 1, "aucun second document créé par la tentative refusée");
  }
);

test(
  "sendChatMessage : un rejeu avec le même expéditeur mais un contenu différent est refusé (already-exists), jamais silencieusement ignoré ni n'écrase le message",
  async () => {
    const chatId = "chat-content-mismatch";
    await seedChat(chatId);

    await functions.sendChatMessage.run({
      data: { chatId, clientMessageId: "msg-1", content: "Contenu original" },
      auth: { uid: "buyer1" },
    });

    await assert.rejects(
      () =>
        functions.sendChatMessage.run({
          data: { chatId, clientMessageId: "msg-1", content: "Contenu modifié" },
          auth: { uid: "buyer1" },
        }),
      (err) => {
        assert.equal(err.code, "already-exists");
        return true;
      }
    );

    const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("msg-1").get();
    assert.equal(msgSnap.data().content, "Contenu original", "le contenu original ne doit jamais être écrasé");
  }
);

test("sendChatMessage : rejette un chatId/clientMessageId contenant '/' ou un chat aux participants corrompus", async () => {
  const chatId = "chat-corrupt-checks";
  await seedChat(chatId);

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId: "not/a-valid-id", clientMessageId: "x", content: "Bonjour" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId, clientMessageId: "not/valid", content: "Bonjour" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );

  const corruptChatId = "chat-corrupt-same-participant";
  await db.collection("chats").doc(corruptChatId).set({
    buyerId: "buyer1",
    sellerId: "buyer1",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });
  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId: corruptChatId, clientMessageId: "x", content: "Bonjour" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
});

function chatMediaUrl(chatId, fileName) {
  return `https://firebasestorage.googleapis.com/v0/b/test-bucket.appspot.com/o/chatMedia%2F${chatId}%2F${fileName}?alt=media&token=fake-token`;
}

test("sendChatMessage : accepte un média (mediaUrl du dossier Storage de CE chat), content devient une légende optionnelle", async () => {
  const chatId = "chat-send-media";
  await seedChat(chatId);
  const mediaUrl = chatMediaUrl(chatId, "client-msg-media.jpg");

  const result = await functions.sendChatMessage.run({
    data: {
      chatId,
      clientMessageId: "client-msg-media",
      content: "",
      mediaUrl,
      mediaType: "image",
      mediaWidth: 800,
      mediaHeight: 600,
    },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.alreadyExisted, false);

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("client-msg-media").get();
  assert.equal(msgSnap.data().mediaUrl, mediaUrl);
  assert.equal(msgSnap.data().mediaType, "image");
  assert.equal(msgSnap.data().mediaWidth, 800);
  assert.equal(msgSnap.data().mediaHeight, 600);
  assert.equal(msgSnap.data().content, "", "content vide est autorisé quand un média est présent");

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().lastMessage, "📷 Photo", "aperçu de conversation par défaut pour une photo sans légende");
});

test("sendChatMessage : refuse une mediaUrl pointant vers le dossier Storage d'UN AUTRE chat", async () => {
  const chatId = "chat-send-media-wrong-folder";
  await seedChat(chatId);

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: {
          chatId,
          clientMessageId: "client-msg-1",
          content: "",
          mediaUrl: chatMediaUrl("un-autre-chat", "vol.jpg"),
          mediaType: "image",
        },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );
});

test("sendChatMessage : refuse un message sans texte NI média, et un mediaType invalide", async () => {
  const chatId = "chat-send-empty-and-badtype";
  await seedChat(chatId);

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: { chatId, clientMessageId: "client-msg-1", content: "" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.sendChatMessage.run({
        data: {
          chatId,
          clientMessageId: "client-msg-2",
          content: "",
          mediaUrl: chatMediaUrl(chatId, "x.jpg"),
          mediaType: "audio",
        },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );
});

test("forwardChatMessage : transfère texte+média vers une autre conversation (copie Storage ignorée si le chemin source ne peut pas être résolu, aucun appel réseau réel)", async () => {
  const sourceChatId = "chat-fwd-source";
  const targetChatId = "chat-fwd-target";
  await seedChat(sourceChatId);
  await db.collection("chats").doc(targetChatId).set({
    buyerId: "buyer1",
    sellerId: "seller2",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });

  // Passe `isValidChatMediaUrl` (bon hôte + chemin contenant
  // `/chatMedia/{chatId}/`) mais N'A PAS le segment `/o/` d'une vraie URL de
  // téléchargement Firebase Storage : `storagePathFromDownloadUrl` renvoie
  // donc `null`, et `copyChatMediaToTargetChat` se rabat immédiatement sur
  // l'URL fournie SANS tenter de copie Storage — ce test reste hermétique
  // (aucun appel réseau réel), même schéma que `deleteStatus` plus haut. Le
  // comportement de copie réussie (nouveau chemin sous le chat cible) n'est
  // pas couvert ici : il nécessiterait un émulateur Storage, absent de
  // cette suite qui ne cible que Firestore.
  const mediaUrl = `https://firebasestorage.googleapis.com/chatMedia/${sourceChatId}/src-msg.jpg`;
  await functions.sendChatMessage.run({
    data: {
      chatId: sourceChatId,
      clientMessageId: "src-msg",
      content: "Regarde ça",
      mediaUrl,
      mediaType: "image",
      mediaWidth: 100,
      mediaHeight: 200,
    },
    auth: { uid: "buyer1" },
  });

  const result = await functions.forwardChatMessage.run({
    data: {
      sourceChatId,
      sourceMessageId: "src-msg",
      targetChatId,
      clientMessageId: "fwd-msg-1",
    },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.alreadyExisted, false);

  const fwdSnap = await db.collection("chats").doc(targetChatId).collection("messages").doc("fwd-msg-1").get();
  assert.equal(fwdSnap.data().content, "Regarde ça");
  assert.equal(fwdSnap.data().mediaUrl, mediaUrl, "chemin source non résolu -> repli sur l'URL d'origine, sans appel réseau");
  assert.equal(fwdSnap.data().mediaType, "image");
  assert.equal(fwdSnap.data().forwardedFromChatId, sourceChatId);
  assert.equal(fwdSnap.data().forwardedFromMessageId, "src-msg");
  assert.equal(fwdSnap.data().senderId, "buyer1");
  assert.equal(fwdSnap.data().receiverId, "seller2", "receiverId dérivé des participants de la conversation CIBLE");
});

test("forwardChatMessage : refuse un appelant qui ne participe pas à la conversation SOURCE", async () => {
  const sourceChatId = "chat-fwd-source-outsider";
  const targetChatId = "chat-fwd-target-outsider";
  await seedChat(sourceChatId);
  await db.collection("chats").doc(targetChatId).set({
    buyerId: "outsider",
    sellerId: "seller2",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });
  await functions.sendChatMessage.run({
    data: { chatId: sourceChatId, clientMessageId: "src-msg", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  await assert.rejects(
    () =>
      functions.forwardChatMessage.run({
        data: { sourceChatId, sourceMessageId: "src-msg", targetChatId, clientMessageId: "fwd-1" },
        auth: { uid: "outsider" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("forwardChatMessage : refuse un appelant qui ne participe pas à la conversation CIBLE", async () => {
  const sourceChatId = "chat-fwd-source-2";
  const targetChatId = "chat-fwd-target-not-participant";
  await seedChat(sourceChatId);
  await db.collection("chats").doc(targetChatId).set({
    buyerId: "seller1",
    sellerId: "seller2",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });
  await functions.sendChatMessage.run({
    data: { chatId: sourceChatId, clientMessageId: "src-msg", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  await assert.rejects(
    () =>
      functions.forwardChatMessage.run({
        data: { sourceChatId, sourceMessageId: "src-msg", targetChatId, clientMessageId: "fwd-1" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("forwardChatMessage : refuse un message source introuvable", async () => {
  const sourceChatId = "chat-fwd-source-3";
  const targetChatId = "chat-fwd-target-3";
  await seedChat(sourceChatId);
  await db.collection("chats").doc(targetChatId).set({
    buyerId: "buyer1",
    sellerId: "seller2",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });

  await assert.rejects(
    () =>
      functions.forwardChatMessage.run({
        data: { sourceChatId, sourceMessageId: "inexistant", targetChatId, clientMessageId: "fwd-1" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "not-found");
      return true;
    }
  );
});

test("forwardChatMessage : un rejeu sur le même clientMessageId ne crée jamais de doublon (idempotence partagée avec sendChatMessage)", async () => {
  const sourceChatId = "chat-fwd-source-4";
  const targetChatId = "chat-fwd-target-4";
  await seedChat(sourceChatId);
  await db.collection("chats").doc(targetChatId).set({
    buyerId: "buyer1",
    sellerId: "seller2",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });
  await functions.sendChatMessage.run({
    data: { chatId: sourceChatId, clientMessageId: "src-msg", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  const first = await functions.forwardChatMessage.run({
    data: { sourceChatId, sourceMessageId: "src-msg", targetChatId, clientMessageId: "fwd-retry" },
    auth: { uid: "buyer1" },
  });
  assert.equal(first.alreadyExisted, false);

  const retry = await functions.forwardChatMessage.run({
    data: { sourceChatId, sourceMessageId: "src-msg", targetChatId, clientMessageId: "fwd-retry" },
    auth: { uid: "buyer1" },
  });
  assert.equal(retry.alreadyExisted, true);

  const messagesSnap = await db.collection("chats").doc(targetChatId).collection("messages").get();
  assert.equal(messagesSnap.size, 1, "aucun doublon créé par le rejeu du transfert");
});

test("deleteChat : supprime le chat et décrémente le badge global des deux participants pour leurs messages non lus", async () => {
  const chatId = "chat-delete-basic";
  await seedChat(chatId, { buyerUnreadCount: 3, sellerUnreadCount: 2 });
  await db.collection("users").doc("buyer1").set({ unreadMessageCount: 5 });
  await db.collection("users").doc("seller1").set({ unreadMessageCount: 2 });

  const result = await functions.deleteChat.run({
    data: { chatId },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.deleted, true);

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.exists, false);

  const buyerSnap = await db.collection("users").doc("buyer1").get();
  assert.equal(buyerSnap.data().unreadMessageCount, 2, "5 - 3 messages non lus du chat supprimé");
  const sellerSnap = await db.collection("users").doc("seller1").get();
  assert.equal(sellerSnap.data().unreadMessageCount, 0, "2 - 2 messages non lus du chat supprimé");
});

test("deleteChat : ne fait jamais descendre le badge global sous 0, même avec un historique incohérent", async () => {
  const chatId = "chat-delete-negative-guard";
  await seedChat(chatId, { buyerUnreadCount: 10, sellerUnreadCount: 0 });
  await db.collection("users").doc("buyer1").set({ unreadMessageCount: 3 });

  await functions.deleteChat.run({ data: { chatId }, auth: { uid: "buyer1" } });

  const buyerSnap = await db.collection("users").doc("buyer1").get();
  assert.equal(buyerSnap.data().unreadMessageCount, 0);
});

test("deleteChat : supprime aussi la sous-collection messages (jamais supprimée en cascade par Firestore sinon)", async () => {
  const chatId = "chat-delete-messages";
  await seedChat(chatId);
  await db.collection("chats").doc(chatId).collection("messages").doc("m1").set({
    senderId: "buyer1",
    receiverId: "seller1",
    content: "Bonjour",
    status: "sent",
    sentAt: Date.now(),
  });

  await functions.deleteChat.run({ data: { chatId }, auth: { uid: "buyer1" } });

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("m1").get();
  assert.equal(msgSnap.exists, false);
});

test("deleteChat : idempotent — un rejeu sur un chat déjà supprimé ne lève pas d'erreur", async () => {
  const chatId = "chat-delete-idempotent";
  await seedChat(chatId, { buyerUnreadCount: 1 });
  await db.collection("users").doc("buyer1").set({ unreadMessageCount: 1 });

  await functions.deleteChat.run({ data: { chatId }, auth: { uid: "buyer1" } });
  const replay = await functions.deleteChat.run({ data: { chatId }, auth: { uid: "buyer1" } });
  assert.equal(replay.deleted, true);

  const buyerSnap = await db.collection("users").doc("buyer1").get();
  assert.equal(
    buyerSnap.data().unreadMessageCount,
    0,
    "le rejeu ne doit jamais décrémenter une seconde fois (le chat n'existe plus)"
  );
});

test("deleteChat : rejette un appel non authentifié et un utilisateur qui ne participe pas à la conversation", async () => {
  const chatId = "chat-delete-rejects";
  await seedChat(chatId);

  await assert.rejects(
    () => functions.deleteChat.run({ data: { chatId }, auth: undefined }),
    (err) => {
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );

  await assert.rejects(
    () => functions.deleteChat.run({ data: { chatId }, auth: { uid: "outsider" } }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.exists, true, "un appel rejeté ne doit rien supprimer");
});

test("deleteChatForMe : masque la conversation uniquement pour l'appelant (hiddenFor)", async () => {
  const chatId = "chat-hide-basic";
  await seedChat(chatId);

  const result = await functions.deleteChatForMe.run({
    data: { chatId },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.hidden, true);

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.exists, true, "rien n'est réellement supprimé");
  assert.deepEqual(chatSnap.data().hiddenFor, ["buyer1"]);
});

test("deleteChatForMe : idempotent — rejouer n'ajoute pas de doublon dans hiddenFor", async () => {
  const chatId = "chat-hide-idempotent";
  await seedChat(chatId);

  await functions.deleteChatForMe.run({ data: { chatId }, auth: { uid: "buyer1" } });
  await functions.deleteChatForMe.run({ data: { chatId }, auth: { uid: "buyer1" } });

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.deepEqual(chatSnap.data().hiddenFor, ["buyer1"]);
});

test("deleteChatForMe : un nouveau message réinitialise hiddenFor (réapparaît pour tout le monde)", async () => {
  const chatId = "chat-hide-reappear";
  await seedChat(chatId);
  await functions.deleteChatForMe.run({ data: { chatId }, auth: { uid: "buyer1" } });

  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "msg-after-hide", content: "Bonjour" },
    auth: { uid: "seller1" },
  });

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.deepEqual(chatSnap.data().hiddenFor, []);
});

test("deleteChatForMe : rejette un appel non authentifié et un utilisateur qui ne participe pas", async () => {
  const chatId = "chat-hide-rejects";
  await seedChat(chatId);

  await assert.rejects(
    () => functions.deleteChatForMe.run({ data: { chatId }, auth: undefined }),
    (err) => {
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
  await assert.rejects(
    () => functions.deleteChatForMe.run({ data: { chatId }, auth: { uid: "outsider" } }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );

  const chatSnap = await db.collection("chats").doc(chatId).get();
  assert.deepEqual(
    chatSnap.data().hiddenFor ?? [],
    [],
    "un appel rejeté ne doit rien masquer"
  );
});

test('deleteChatMessage "pour moi" : ajoute l\'appelant à deletedFor, laisse le contenu intact pour l\'autre participant', async () => {
  const chatId = "chat-msg-delete-for-me";
  await seedChat(chatId);
  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "msg1", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  const result = await functions.deleteChatMessage.run({
    data: { chatId, messageId: "msg1", forEveryone: false },
    auth: { uid: "seller1" },
  });
  assert.equal(result.deleted, true);

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("msg1").get();
  assert.deepEqual(msgSnap.data().deletedFor, ["seller1"]);
  assert.equal(msgSnap.data().content, "Bonjour", "le contenu reste intact, seul l'affichage de seller1 doit le filtrer");
  assert.equal(msgSnap.data().deletedForEveryone ?? false, false);
});

test('deleteChatMessage "pour moi" : idempotent — rejouer n\'ajoute pas de doublon', async () => {
  const chatId = "chat-msg-delete-for-me-idempotent";
  await seedChat(chatId);
  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "msg1", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  await functions.deleteChatMessage.run({
    data: { chatId, messageId: "msg1", forEveryone: false },
    auth: { uid: "seller1" },
  });
  await functions.deleteChatMessage.run({
    data: { chatId, messageId: "msg1", forEveryone: false },
    auth: { uid: "seller1" },
  });

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("msg1").get();
  assert.deepEqual(msgSnap.data().deletedFor, ["seller1"]);
});

test('deleteChatMessage "pour tout le monde" : réservé à l\'expéditeur, vide le contenu/média pour les deux participants', async () => {
  const chatId = "chat-msg-delete-everyone";
  await seedChat(chatId);
  await functions.sendChatMessage.run({
    data: {
      chatId,
      clientMessageId: "msg1",
      content: "Regarde",
      mediaUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/chatMedia%2Fchat-msg-delete-everyone%2Fbuyer1%2Fseller1%2Fmsg1.jpg?alt=media",
      mediaType: "image",
    },
    auth: { uid: "buyer1" },
  });

  const result = await functions.deleteChatMessage.run({
    data: { chatId, messageId: "msg1", forEveryone: true },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.deleted, true);

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("msg1").get();
  assert.equal(msgSnap.data().content, "");
  assert.equal(msgSnap.data().mediaUrl, undefined, "mediaUrl doit être entièrement effacé, pas juste vidé");
  assert.equal(msgSnap.data().deletedForEveryone, true);
  assert.ok(msgSnap.data().deletedAt);
});

test('deleteChatMessage "pour tout le monde" : un non-expéditeur est rejeté, rien n\'est modifié', async () => {
  const chatId = "chat-msg-delete-everyone-rejects";
  await seedChat(chatId);
  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "msg1", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  await assert.rejects(
    () =>
      functions.deleteChatMessage.run({
        data: { chatId, messageId: "msg1", forEveryone: true },
        auth: { uid: "seller1" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc("msg1").get();
  assert.equal(msgSnap.data().content, "Bonjour", "le message ne doit jamais être modifié par un appel rejeté");
  assert.equal(msgSnap.data().deletedForEveryone ?? false, false);
});

test('deleteChatMessage "pour tout le monde" : idempotent, jamais d\'erreur sur un message déjà supprimé', async () => {
  const chatId = "chat-msg-delete-everyone-idempotent";
  await seedChat(chatId);
  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "msg1", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  await functions.deleteChatMessage.run({
    data: { chatId, messageId: "msg1", forEveryone: true },
    auth: { uid: "buyer1" },
  });
  const replay = await functions.deleteChatMessage.run({
    data: { chatId, messageId: "msg1", forEveryone: true },
    auth: { uid: "buyer1" },
  });
  assert.equal(replay.deleted, true);
});

test('deleteChatMessage "pour tout le monde" : met à jour l\'aperçu de la conversation UNIQUEMENT si c\'était le dernier message', async () => {
  const chatId = "chat-msg-delete-last-preview";
  await seedChat(chatId);
  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "msg1", content: "Premier" },
    auth: { uid: "buyer1" },
  });
  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "msg2", content: "Dernier" },
    auth: { uid: "buyer1" },
  });

  // Supprimer un message qui N'EST PAS le dernier ne doit jamais toucher
  // l'aperçu affiché dans la liste des conversations.
  await functions.deleteChatMessage.run({
    data: { chatId, messageId: "msg1", forEveryone: true },
    auth: { uid: "buyer1" },
  });
  let chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().lastMessage, "Dernier");

  // Supprimer le DERNIER message doit refléter la suppression dans l'aperçu.
  await functions.deleteChatMessage.run({
    data: { chatId, messageId: "msg2", forEveryone: true },
    auth: { uid: "buyer1" },
  });
  chatSnap = await db.collection("chats").doc(chatId).get();
  assert.equal(chatSnap.data().lastMessage, "Message supprimé");
});

test("deleteChatMessage : rejette un appel non authentifié et un utilisateur qui ne participe pas à la conversation", async () => {
  const chatId = "chat-msg-delete-rejects";
  await seedChat(chatId);
  await functions.sendChatMessage.run({
    data: { chatId, clientMessageId: "msg1", content: "Bonjour" },
    auth: { uid: "buyer1" },
  });

  await assert.rejects(
    () =>
      functions.deleteChatMessage.run({
        data: { chatId, messageId: "msg1", forEveryone: false },
        auth: undefined,
      }),
    (err) => {
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
  await assert.rejects(
    () =>
      functions.deleteChatMessage.run({
        data: { chatId, messageId: "msg1", forEveryone: false },
        auth: { uid: "outsider" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("deleteChatMessage : un message déjà inexistant est idempotent (jamais d'erreur)", async () => {
  const chatId = "chat-msg-delete-missing";
  await seedChat(chatId);

  const result = await functions.deleteChatMessage.run({
    data: { chatId, messageId: "never-existed", forEveryone: false },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.deleted, true);
});

test("applyPushResult : un succès FCM réel fait passer un message de sent à delivered", async () => {
  const chatId = "chat-delivered-basic";
  const messageId = "msg-delivered-1";
  await db.collection("chats").doc(chatId).collection("messages").doc(messageId).set({
    senderId: "buyer1",
    receiverId: "seller1",
    content: "Bonjour",
    status: "sent",
  });
  const notifRef = db.collection("notifications").doc("notif-delivered-1");
  await notifRef.set({ recipientId: "seller1", isRead: false, pushState: "sending" });

  await functions._testables.applyPushResult({
    notifRef,
    recipientId: "seller1",
    devices: [{ id: "device1", token: "tok1" }],
    result: { successCount: 1, failureCount: 0, responses: [{ success: true }] },
    type: "message",
    data: { chatId, messageId },
  });

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc(messageId).get();
  assert.equal(msgSnap.data().status, "delivered");
  assert.ok(msgSnap.data().deliveredAt);
});

test("applyPushResult : ne régresse jamais un message déjà lu vers delivered (course avec markChatAsRead)", async () => {
  const chatId = "chat-delivered-race-read";
  const messageId = "msg-delivered-2";
  await db.collection("chats").doc(chatId).collection("messages").doc(messageId).set({
    senderId: "buyer1",
    receiverId: "seller1",
    content: "Bonjour",
    status: "read",
    readAt: Timestamp.now(),
  });
  const notifRef = db.collection("notifications").doc("notif-delivered-2");
  await notifRef.set({ recipientId: "seller1", isRead: false, pushState: "sending" });

  await functions._testables.applyPushResult({
    notifRef,
    recipientId: "seller1",
    devices: [{ id: "device1", token: "tok1" }],
    result: { successCount: 1, failureCount: 0, responses: [{ success: true }] },
    type: "message",
    data: { chatId, messageId },
  });

  const msgSnap = await db.collection("chats").doc(chatId).collection("messages").doc(messageId).get();
  assert.equal(msgSnap.data().status, "read", "un message déjà lu ne doit jamais redevenir delivered");
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

test("onAnnonceUpdated : une baisse de prix historise l'entrée et notifie les favoris (pas le vendeur)", async () => {
  await db.collection("annonces").doc("annonce-price-drop-1").set({
    sellerId: "seller1",
    price: 1000,
    currency: "FC",
    title: "Chaise",
  });
  await db.collection("favoris").add({ utilisateurId: "buyer1", annonceId: "annonce-price-drop-1" });
  await db.collection("favoris").add({ utilisateurId: "buyer2", annonceId: "annonce-price-drop-1" });
  // Favori défensif du vendeur lui-même : ne doit jamais recevoir sa propre alerte.
  await db.collection("favoris").add({ utilisateurId: "seller1", annonceId: "annonce-price-drop-1" });
  // Favori sur une AUTRE annonce : ne doit jamais être notifié.
  await db.collection("favoris").add({ utilisateurId: "buyer3", annonceId: "annonce-autre" });

  const event = {
    id: "event-price-drop-1",
    data: {
      before: { data: () => ({ sellerId: "seller1", price: 1000, currency: "FC", title: "Chaise" }) },
      after: { data: () => ({ sellerId: "seller1", price: 800, currency: "FC", title: "Chaise" }) },
    },
    params: { annonceId: "annonce-price-drop-1" },
  };

  await functions.onAnnonceUpdated.run(event);

  const historySnap = await db
    .collection("annonces")
    .doc("annonce-price-drop-1")
    .collection("priceHistory")
    .get();
  assert.equal(historySnap.docs.length, 1);
  assert.equal(historySnap.docs[0].data().oldPrice, 1000);
  assert.equal(historySnap.docs[0].data().newPrice, 800);

  const notifBuyer1 = await db
    .collection("notifications")
    .doc(`priceDropped_annonce-price-drop-1_buyer1_event-price-drop-1`)
    .get();
  const notifBuyer2 = await db
    .collection("notifications")
    .doc(`priceDropped_annonce-price-drop-1_buyer2_event-price-drop-1`)
    .get();
  const notifSeller = await db
    .collection("notifications")
    .doc(`priceDropped_annonce-price-drop-1_seller1_event-price-drop-1`)
    .get();
  const notifBuyer3 = await db
    .collection("notifications")
    .doc(`priceDropped_annonce-autre_buyer3_event-price-drop-1`)
    .get();

  assert.ok(notifBuyer1.exists, "buyer1 a mis l'annonce en favori : doit être notifié");
  assert.ok(notifBuyer2.exists, "buyer2 a mis l'annonce en favori : doit être notifié");
  assert.equal(notifSeller.exists, false, "le vendeur ne doit jamais être notifié de sa propre baisse");
  assert.equal(notifBuyer3.exists, false, "un favori sur une autre annonce ne doit jamais être notifié");
});

test("onAnnonceUpdated : une hausse de prix historise l'entrée mais ne notifie personne", async () => {
  await db.collection("annonces").doc("annonce-price-up-1").set({
    sellerId: "seller1",
    price: 800,
    currency: "FC",
  });
  await db.collection("favoris").add({ utilisateurId: "buyer1", annonceId: "annonce-price-up-1" });

  const event = {
    id: "event-price-up-1",
    data: {
      before: { data: () => ({ sellerId: "seller1", price: 800, currency: "FC" }) },
      after: { data: () => ({ sellerId: "seller1", price: 1200, currency: "FC" }) },
    },
    params: { annonceId: "annonce-price-up-1" },
  };

  await functions.onAnnonceUpdated.run(event);

  const historySnap = await db
    .collection("annonces")
    .doc("annonce-price-up-1")
    .collection("priceHistory")
    .get();
  assert.equal(historySnap.docs.length, 1, "une hausse doit quand même être historisée");
  assert.equal(historySnap.docs[0].data().newPrice, 1200);

  const notifBuyer1 = await db
    .collection("notifications")
    .doc(`priceDropped_annonce-price-up-1_buyer1_event-price-up-1`)
    .get();
  assert.equal(notifBuyer1.exists, false, "une hausse de prix ne doit jamais notifier");
});

test("onAnnonceUpdated : aucun changement de prix -> aucune entrée d'historique", async () => {
  await db.collection("annonces").doc("annonce-no-change-1").set({ sellerId: "seller1", price: 500 });

  const event = {
    id: "event-no-change-1",
    data: {
      before: { data: () => ({ sellerId: "seller1", price: 500, title: "Ancien titre" }) },
      after: { data: () => ({ sellerId: "seller1", price: 500, title: "Nouveau titre" }) },
    },
    params: { annonceId: "annonce-no-change-1" },
  };

  await functions.onAnnonceUpdated.run(event);

  const historySnap = await db
    .collection("annonces")
    .doc("annonce-no-change-1")
    .collection("priceHistory")
    .get();
  assert.equal(historySnap.docs.length, 0);
});

test("onAnnonceUpdated : une redélivrance du même évènement n'écrit jamais deux entrées d'historique", async () => {
  await db.collection("annonces").doc("annonce-redelivered-1").set({ sellerId: "seller1", price: 1000 });

  const event = {
    id: "event-redelivered-1",
    data: {
      before: { data: () => ({ sellerId: "seller1", price: 1000 }) },
      after: { data: () => ({ sellerId: "seller1", price: 900 }) },
    },
    params: { annonceId: "annonce-redelivered-1" },
  };

  await functions.onAnnonceUpdated.run(event);
  await functions.onAnnonceUpdated.run(event);

  const historySnap = await db
    .collection("annonces")
    .doc("annonce-redelivered-1")
    .collection("priceHistory")
    .get();
  assert.equal(historySnap.docs.length, 1, "même event.id : une seule entrée, jamais un doublon");
});

test("submitReview : l'acheteur note le vendeur d'une commande complétée, met à jour publicProfiles et marque la commande", async () => {
  await db.collection("annonces").doc("annonce-review1").set({ sellerId: "seller1", price: 1000 });
  await db.collection("orders").doc("order1").set({
    buyerId: "buyer1",
    items: [{ productId: "annonce-review1", quantity: 1 }],
    status: "completed",
  });

  const result = await functions.submitReview.run({
    data: { orderId: "order1", sellerId: "seller1", rating: 5, comment: "Très bien" },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.alreadyExisted, false);

  const reviewSnap = await db.collection("reviews").doc("order1_seller1_buyer_to_seller").get();
  assert.ok(reviewSnap.exists);
  assert.equal(reviewSnap.data().reviewerId, "buyer1");
  assert.equal(reviewSnap.data().revieweeId, "seller1");
  assert.equal(reviewSnap.data().rating, 5);
  assert.equal(reviewSnap.data().comment, "Très bien");

  const profileSnap = await db.collection("publicProfiles").doc("seller1").get();
  assert.equal(profileSnap.data().ratingSum, 5);
  assert.equal(profileSnap.data().ratingCount, 1);
  assert.equal(profileSnap.data().averageRating, 5);

  const orderSnap = await db.collection("orders").doc("order1").get();
  assert.deepEqual(orderSnap.data().buyerReviewedSellerIds, ["seller1"]);
});

test("submitReview : le vendeur note l'acheteur d'une commande complétée (sens inverse)", async () => {
  await db.collection("annonces").doc("annonce-review1").set({ sellerId: "seller1", price: 1000 });
  await db.collection("orders").doc("order2").set({
    buyerId: "buyer1",
    items: [{ productId: "annonce-review1", quantity: 1 }],
    status: "completed",
  });

  const result = await functions.submitReview.run({
    data: { orderId: "order2", sellerId: "seller1", rating: 4, comment: "" },
    auth: { uid: "seller1" },
  });
  assert.equal(result.alreadyExisted, false);

  const reviewSnap = await db.collection("reviews").doc("order2_seller1_seller_to_buyer").get();
  assert.ok(reviewSnap.exists);
  assert.equal(reviewSnap.data().reviewerId, "seller1");
  assert.equal(reviewSnap.data().revieweeId, "buyer1");

  const profileSnap = await db.collection("publicProfiles").doc("buyer1").get();
  assert.equal(profileSnap.data().ratingSum, 4);
  assert.equal(profileSnap.data().ratingCount, 1);

  const orderSnap = await db.collection("orders").doc("order2").get();
  assert.deepEqual(orderSnap.data().sellerReviewedBuyerIds, ["seller1"]);
});

test("submitReview : un second appel sur le même triplet (orderId, sellerId, direction) ne réécrit jamais l'avis ni les stats", async () => {
  await db.collection("annonces").doc("annonce-review1").set({ sellerId: "seller1", price: 1000 });
  await db.collection("orders").doc("order3").set({
    buyerId: "buyer1",
    items: [{ productId: "annonce-review1", quantity: 1 }],
    status: "completed",
  });

  await functions.submitReview.run({
    data: { orderId: "order3", sellerId: "seller1", rating: 5, comment: "Premier avis" },
    auth: { uid: "buyer1" },
  });
  const result = await functions.submitReview.run({
    data: { orderId: "order3", sellerId: "seller1", rating: 1, comment: "Rejeu hostile" },
    auth: { uid: "buyer1" },
  });

  assert.equal(result.alreadyExisted, true);

  const reviewSnap = await db.collection("reviews").doc("order3_seller1_buyer_to_seller").get();
  assert.equal(reviewSnap.data().rating, 5, "l'avis original ne doit jamais être écrasé");
  assert.equal(reviewSnap.data().comment, "Premier avis");

  const profileSnap = await db.collection("publicProfiles").doc("seller1").get();
  assert.equal(profileSnap.data().ratingCount, 1, "un rejeu ne doit jamais compter deux fois");
});

test("submitReview : la moyenne se recalcule correctement sur plusieurs avis", async () => {
  await db.collection("annonces").doc("annonce-review1").set({ sellerId: "seller1", price: 1000 });
  await db.collection("orders").doc("order4").set({
    buyerId: "buyer1",
    items: [{ productId: "annonce-review1", quantity: 1 }],
    status: "completed",
  });
  await db.collection("orders").doc("order5").set({
    buyerId: "buyer2",
    items: [{ productId: "annonce-review1", quantity: 1 }],
    status: "completed",
  });

  await functions.submitReview.run({
    data: { orderId: "order4", sellerId: "seller1", rating: 5, comment: "" },
    auth: { uid: "buyer1" },
  });
  await functions.submitReview.run({
    data: { orderId: "order5", sellerId: "seller1", rating: 3, comment: "" },
    auth: { uid: "buyer2" },
  });

  const profileSnap = await db.collection("publicProfiles").doc("seller1").get();
  assert.equal(profileSnap.data().ratingSum, 8);
  assert.equal(profileSnap.data().ratingCount, 2);
  assert.equal(profileSnap.data().averageRating, 4);
});

test("submitReview : rejette une commande pas encore complétée, un tiers hors commande, une note invalide et un vendeur hors commande", async () => {
  await db.collection("annonces").doc("annonce-review1").set({ sellerId: "seller1", price: 1000 });
  await db.collection("orders").doc("order-paid").set({
    buyerId: "buyer1",
    items: [{ productId: "annonce-review1", quantity: 1 }],
    status: "paid",
  });
  await db.collection("orders").doc("order-completed").set({
    buyerId: "buyer1",
    items: [{ productId: "annonce-review1", quantity: 1 }],
    status: "completed",
  });

  await assert.rejects(
    () =>
      functions.submitReview.run({
        data: { orderId: "order-paid", sellerId: "seller1", rating: 5, comment: "" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.submitReview.run({
        data: { orderId: "order-completed", sellerId: "seller1", rating: 5, comment: "" },
        auth: { uid: "outsider" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.submitReview.run({
        data: { orderId: "order-completed", sellerId: "seller1", rating: 0, comment: "" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.submitReview.run({
        data: { orderId: "order-completed", sellerId: "seller1", rating: 6, comment: "" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.submitReview.run({
        data: { orderId: "order-completed", sellerId: "seller-not-in-order", rating: 5, comment: "" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );

  await assert.rejects(
    () =>
      functions.submitReview.run({
        data: { orderId: "order-completed", sellerId: "seller1", rating: 5, comment: "" },
        auth: undefined,
      }),
    (err) => {
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
});

test("submitReview : un `order.sellerIds` falsifié (tiers étranger à l'annonce réelle) ne permet jamais de lui poster un avis", async () => {
  // L'acheteur a réellement acheté chez seller1 (l'annonce référencée par
  // `items` le confirme), mais avait mis "victim" dans `sellerIds` — jamais
  // recoupé avec les articles avant le correctif verifiedSellerId.
  await db.collection("annonces").doc("annonce-review-spoof").set({ sellerId: "seller1", price: 100 });
  await db.collection("orders").doc("order-spoofed-seller").set({
    buyerId: "buyer1",
    sellerIds: ["victim"],
    items: [{ sellerId: "victim", productId: "annonce-review-spoof", quantity: 1 }],
    status: "completed",
  });

  await assert.rejects(
    () =>
      functions.submitReview.run({
        data: { orderId: "order-spoofed-seller", sellerId: "victim", rating: 1, comment: "faux avis" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );

  const profileSnap = await db.collection("publicProfiles").doc("victim").get();
  assert.equal(profileSnap.exists, false, "aucun profil ne doit être créé/modifié pour la victime");
});

test("submitReview : accepte aussi une commande déjà reversée (payout_sent), pas seulement completed", async () => {
  await db.collection("annonces").doc("annonce-review1").set({ sellerId: "seller1", price: 1000 });
  await db.collection("orders").doc("order-payout").set({
    buyerId: "buyer1",
    items: [{ productId: "annonce-review1", quantity: 1 }],
    status: "payout_sent",
  });

  const result = await functions.submitReview.run({
    data: { orderId: "order-payout", sellerId: "seller1", rating: 5, comment: "" },
    auth: { uid: "buyer1" },
  });

  assert.equal(result.alreadyExisted, false);
});

test("notifySettlement (paiement) : mirroire aussi totalSales dans publicProfiles, pas seulement sellerStatistics", async () => {
  await db.collection("annonces").doc("annonce-settle").set({ sellerId: "seller1", price: 5000 });
  await db.collection("orders").doc("order-settle").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
    items: [{ sellerId: "seller1", productId: "annonce-settle", quantity: 1, totalPrice: 5000 }],
    currency: "FC",
    status: "pending_payment",
  });
  await db.collection("paymentIntents").doc("intent-settle").set({
    type: "order",
    orderId: "order-settle",
    userId: "buyer1",
    amount: 5000,
    currency: "FC",
    status: "created",
  });
  await db.collection("admins").doc("admin1").set({});

  await functions.confirmManualPayment.run({
    data: { transactionId: "intent-settle" },
    auth: { uid: "admin1" },
  });

  const profileSnap = await db.collection("publicProfiles").doc("seller1").get();
  assert.equal(profileSnap.data().totalSales, 1);

  const statsSnap = await db.collection("sellerStatistics").doc("seller1").get();
  assert.equal(statsSnap.data().totalSales, 1);
});

test("notifySettlement (paiement) : les stats/notifications vont au vrai vendeur de l'annonce, jamais à un sellerId falsifié par l'acheteur", async () => {
  await db.collection("annonces").doc("annonce-forge-1").set({ sellerId: "realSeller", price: 5000 });
  await db.collection("orders").doc("order-forge-1").set({
    buyerId: "buyer1",
    // L'acheteur prétend que le vendeur est "accomplice" — le vrai
    // propriétaire de l'annonce est "realSeller".
    sellerIds: ["accomplice"],
    items: [{ sellerId: "accomplice", productId: "annonce-forge-1", quantity: 1, totalPrice: 5000 }],
    currency: "FC",
    status: "pending_payment",
  });
  await db.collection("paymentIntents").doc("intent-forge-1").set({
    type: "order",
    orderId: "order-forge-1",
    userId: "buyer1",
    amount: 5000,
    currency: "FC",
    status: "created",
  });
  await db.collection("admins").doc("admin2").set({});

  await functions.confirmManualPayment.run({
    data: { transactionId: "intent-forge-1" },
    auth: { uid: "admin2" },
  });

  const realSellerProfile = await db.collection("publicProfiles").doc("realSeller").get();
  assert.equal(realSellerProfile.data().totalSales, 1, "le vrai vendeur doit être crédité");

  const realSellerStats = await db.collection("sellerStatistics").doc("realSeller").get();
  assert.equal(realSellerStats.data().totalSales, 1);

  const accompliceProfile = await db.collection("publicProfiles").doc("accomplice").get();
  assert.equal(
    accompliceProfile.exists,
    false,
    "le complice désigné par l'acheteur ne doit jamais être crédité"
  );

  const notifSeller = await db
    .collection("notifications")
    .doc("order_intent-forge-1_seller_realSeller")
    .get();
  assert.ok(notifSeller.exists, "le vrai vendeur doit être notifié pour préparer l'envoi");
});

test("onOrderCompleted : les points de fidélité vont au vrai vendeur de l'annonce, jamais à un sellerId falsifié", async () => {
  await db.collection("annonces").doc("annonce-forge-2").set({ sellerId: "realSeller2", price: 10000 });

  const event = {
    data: {
      before: { data: () => ({ status: "paid" }) },
      after: {
        data: () => ({
          status: "completed",
          buyerId: "buyer1",
          currency: "FC",
          sellerIds: ["accomplice2"],
          items: [{ sellerId: "accomplice2", productId: "annonce-forge-2", quantity: 1 }],
        }),
      },
    },
    params: { orderId: "order-forge-2" },
  };

  await functions.onOrderCompleted.run(event);

  const notif = await db
    .collection("notifications")
    .doc("loyalty_earned_order-forge-2_realSeller2")
    .get();
  assert.ok(notif.exists, "le vrai vendeur doit déclencher le crédit de points, pas le complice");

  const statsReal = await db.collection("sellerStatistics").doc("realSeller2").get();
  assert.equal(statsReal.data()?.loyaltyPoints, 10, "10000 FC à 1pt/1000FC = 10 points");

  const statsAccomplice = await db.collection("sellerStatistics").doc("accomplice2").get();
  assert.equal(
    statsAccomplice.exists,
    false,
    "le complice désigné par l'acheteur ne doit jamais être crédité"
  );
});

test("onAnnonceCreated : notifie un utilisateur dont l'alerte correspond au mot-clé", async () => {
  await db.collection("searchAlerts").doc("alert1").set({
    userId: "buyer1",
    keyword: "iphone",
  });

  const event = {
    data: {
      data: () => ({
        sellerId: "seller1",
        title: "iPhone 13 comme neuf",
        description: "Bon état",
        isPublished: true,
      }),
    },
    params: { annonceId: "annonce1" },
  };
  await functions.onAnnonceCreated.run(event);

  const notifSnap = await db
    .collection("notifications")
    .doc("searchAlertMatch_alert1_annonce1")
    .get();
  assert.ok(notifSnap.exists, "l'alerte correspond au mot-clé : doit notifier");
});

test("onAnnonceCreated : le vendeur n'est jamais notifié de sa propre annonce, même si elle correspond à sa propre alerte", async () => {
  await db.collection("searchAlerts").doc("alert-seller").set({
    userId: "seller1",
    keyword: "iphone",
  });

  const event = {
    data: {
      data: () => ({
        sellerId: "seller1",
        title: "iPhone 13 comme neuf",
        description: "Bon état",
        isPublished: true,
      }),
    },
    params: { annonceId: "annonce1" },
  };
  await functions.onAnnonceCreated.run(event);

  const notifSnap = await db
    .collection("notifications")
    .doc("searchAlertMatch_alert-seller_annonce1")
    .get();
  assert.equal(notifSnap.exists, false);
});

test("onAnnonceCreated : aucune notification si aucun critère ne correspond (ville différente)", async () => {
  await db.collection("searchAlerts").doc("alert-city").set({
    userId: "buyer1",
    city: "Kinshasa",
  });

  const event = {
    data: {
      data: () => ({
        sellerId: "seller1",
        title: "Vélo",
        description: "",
        isPublished: true,
        city: "Lubumbashi",
      }),
    },
    params: { annonceId: "annonce1" },
  };
  await functions.onAnnonceCreated.run(event);

  const notifSnap = await db
    .collection("notifications")
    .doc("searchAlertMatch_alert-city_annonce1")
    .get();
  assert.equal(notifSnap.exists, false);
});

test("onAnnonceCreated : une annonce non publiée ne notifie jamais personne", async () => {
  await db.collection("searchAlerts").doc("alert-unpub").set({
    userId: "buyer1",
    keyword: "vélo",
  });

  const event = {
    data: {
      data: () => ({
        sellerId: "seller1",
        title: "Vélo pas cher",
        description: "",
        isPublished: false,
      }),
    },
    params: { annonceId: "annonce1" },
  };
  await functions.onAnnonceCreated.run(event);

  const notifSnap = await db
    .collection("notifications")
    .doc("searchAlertMatch_alert-unpub_annonce1")
    .get();
  assert.equal(notifSnap.exists, false);
});

test("onAnnonceCreated : une alerte sans aucun critère correspond à toute nouvelle annonce publiée d'un autre vendeur", async () => {
  await db.collection("searchAlerts").doc("alert-empty").set({ userId: "buyer1" });

  const event = {
    data: {
      data: () => ({
        sellerId: "seller1",
        title: "N'importe quoi",
        description: "",
        isPublished: true,
      }),
    },
    params: { annonceId: "annonce1" },
  };
  await functions.onAnnonceCreated.run(event);

  const notifSnap = await db
    .collection("notifications")
    .doc("searchAlertMatch_alert-empty_annonce1")
    .get();
  assert.ok(notifSnap.exists);
});

test("ensureReferralCode : génère et enregistre un code pour un compte qui n'en a pas encore", async () => {
  await db.collection("users").doc("user1").set({ name: "Alice" });

  const result = await functions.ensureReferralCode.run({
    data: {},
    auth: { uid: "user1" },
  });

  assert.equal(typeof result.referralCode, "string");
  assert.ok(result.referralCode.length > 0);
  const userSnap = await db.collection("users").doc("user1").get();
  assert.equal(userSnap.data().referralCode, result.referralCode);
});

test("ensureReferralCode : idempotent, ne régénère jamais un code déjà présent (ne casse pas un code déjà partagé)", async () => {
  await db.collection("users").doc("user1").set({
    name: "Alice",
    referralCode: "ABCDEF",
  });

  const result = await functions.ensureReferralCode.run({
    data: {},
    auth: { uid: "user1" },
  });

  assert.equal(result.referralCode, "ABCDEF");
  const userSnap = await db.collection("users").doc("user1").get();
  assert.equal(userSnap.data().referralCode, "ABCDEF");
});

test("ensureReferralCode : refuse un utilisateur non connecté", async () => {
  await assert.rejects(
    () => functions.ensureReferralCode.run({ data: {}, auth: undefined }),
    (err) => {
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
});

test("ensureReferralCode : refuse un compte introuvable", async () => {
  await assert.rejects(
    () => functions.ensureReferralCode.run({ data: {}, auth: { uid: "ghost" } }),
    (err) => {
      assert.equal(err.code, "not-found");
      return true;
    }
  );
});

test("requestGiftRedemption : débite les points et crée la demande", async () => {
  await db.collection("giftCatalogItems").doc("gift1").set({
    sellerId: "seller1",
    title: "Bon d'achat",
    pointsCost: 30,
    isActive: true,
  });
  await db
    .collection("loyaltyPoints")
    .doc("buyer1_seller1")
    .set({ buyerId: "buyer1", sellerId: "seller1", balance: 100 });

  const result = await functions.requestGiftRedemption.run({
    data: { itemId: "gift1", clientRequestId: "req1" },
    auth: { uid: "buyer1" },
  });
  assert.equal(result.status, "pending");
  assert.equal(result.redemptionId, "req1");

  const redemptionSnap = await db.collection("giftRedemptions").doc("req1").get();
  assert.ok(redemptionSnap.exists);
  assert.equal(redemptionSnap.data().pointsCost, 30);

  const pointsSnap = await db.collection("loyaltyPoints").doc("buyer1_seller1").get();
  assert.equal(pointsSnap.data().balance, 70);
});

test("régression : requestGiftRedemption avec le même clientRequestId ne débite jamais deux fois (relance après timeout)", async () => {
  await db.collection("giftCatalogItems").doc("gift2").set({
    sellerId: "seller1",
    title: "Bon d'achat 2",
    pointsCost: 20,
    isActive: true,
  });
  await db
    .collection("loyaltyPoints")
    .doc("buyer2_seller1")
    .set({ buyerId: "buyer2", sellerId: "seller1", balance: 100 });

  const first = await functions.requestGiftRedemption.run({
    data: { itemId: "gift2", clientRequestId: "req2" },
    auth: { uid: "buyer2" },
  });
  const second = await functions.requestGiftRedemption.run({
    data: { itemId: "gift2", clientRequestId: "req2" },
    auth: { uid: "buyer2" },
  });

  assert.equal(first.redemptionId, second.redemptionId);

  const pointsSnap = await db.collection("loyaltyPoints").doc("buyer2_seller1").get();
  assert.equal(pointsSnap.data().balance, 80, "un seul débit malgré les deux appels");
});

test("requestGiftRedemption : refuse un clientRequestId manquant", async () => {
  await assert.rejects(
    () =>
      functions.requestGiftRedemption.run({
        data: { itemId: "gift1" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "invalid-argument");
      return true;
    }
  );
});

test("onUserCreated : attribue un code de parrainage et résout le code du parrain", async () => {
  await db.collection("users").doc("referrer1").set({
    referralCode: "REFCODE1",
    referralCount: 0,
  });
  await db.collection("users").doc("newuser1").set({ referredByCode: "REFCODE1" });

  const event = {
    data: { data: () => ({ referredByCode: "REFCODE1" }) },
    params: { userId: "newuser1" },
  };
  await functions.onUserCreated.run(event);

  const newUserSnap = await db.collection("users").doc("newuser1").get();
  assert.ok(newUserSnap.data().referralCode, "un code doit être généré");
  assert.equal(newUserSnap.data().referredBy, "referrer1");

  const referrerSnap = await db.collection("users").doc("referrer1").get();
  assert.equal(referrerSnap.data().referralCount, 1);
});

test("régression : onUserCreated tolère une redélivrance du trigger sans régénérer referralCode ni réincrémenter referralCount", async () => {
  await db.collection("users").doc("referrer2").set({
    referralCode: "REFCODE2",
    referralCount: 0,
  });
  await db.collection("users").doc("newuser2").set({ referredByCode: "REFCODE2" });

  const event = {
    data: { data: () => ({ referredByCode: "REFCODE2" }) },
    params: { userId: "newuser2" },
  };
  await functions.onUserCreated.run(event);
  const firstSnap = await db.collection("users").doc("newuser2").get();
  const firstCode = firstSnap.data().referralCode;

  // Simule une redélivrance "au moins une fois" du même évènement.
  await functions.onUserCreated.run(event);
  const secondSnap = await db.collection("users").doc("newuser2").get();

  assert.equal(
    secondSnap.data().referralCode,
    firstCode,
    "le code ne doit jamais être régénéré sur redélivrance"
  );
  assert.equal(secondSnap.data().referredBy, "referrer2");

  const referrerSnap = await db.collection("users").doc("referrer2").get();
  assert.equal(
    referrerSnap.data().referralCount,
    1,
    "le compteur du parrain ne doit jamais être réincrémenté sur redélivrance"
  );
});

test("androidChannelIdForType : annonces (alertes de recherche) et feed routées vers le canal dédié occasion_listings", () => {
  assert.equal(functions.androidChannelIdForType("status"), "occasion_listings");
  assert.equal(functions.androidChannelIdForType("search_alert"), "occasion_listings");
});

test("androidChannelIdForType : les autres types ne sont jamais affectés par l'ajout du canal occasion_listings", () => {
  assert.equal(functions.androidChannelIdForType("message"), "occasion_messages");
  assert.equal(functions.androidChannelIdForType("order"), "occasion_orders");
  assert.equal(functions.androidChannelIdForType("subscription"), "occasion_orders");
  assert.equal(functions.androidChannelIdForType("price_drop"), "occasion_general");
  assert.equal(functions.androidChannelIdForType("gift"), "occasion_general");
});

test("MAX_VIDEO_STATUSES_PER_DAY : 10 statuts vidéo par jour (bande passante R2 gratuite, limite fixée pour la qualité du fil)", () => {
  assert.equal(functions._testables.MAX_VIDEO_STATUSES_PER_DAY, 10);
});

test("sellerPayoutAmount : commission Occasion 4 %, arrondi entier en CDF, 2 décimales en USD, rejette les montants invalides", () => {
  const { sellerPayoutAmount } = functions._testables;
  assert.equal(sellerPayoutAmount(10000, "CDF"), 9600);
  assert.equal(sellerPayoutAmount(10, "USD"), 9.6);
  assert.equal(sellerPayoutAmount(0, "CDF"), null);
  assert.equal(sellerPayoutAmount(-5, "USD"), null);
  assert.equal(sellerPayoutAmount(NaN, "CDF"), null);
});

test("startPawapayPayout : refuse un appelant non connecté", async () => {
  await assert.rejects(
    () => functions.startPawapayPayout.run({ data: { orderId: "order1" }, auth: null }),
    (err) => {
      assert.equal(err.code, "unauthenticated");
      return true;
    }
  );
});

test("startPawapayPayout : refuse un appelant non administrateur", async () => {
  await assert.rejects(
    () =>
      functions.startPawapayPayout.run({
        data: { orderId: "order1" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("startPawapayPayout : refuse une commande introuvable", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await assert.rejects(
    () =>
      functions.startPawapayPayout.run({
        data: { orderId: "commande-inexistante" },
        auth: { uid: "admin1" },
      }),
    (err) => {
      assert.equal(err.code, "not-found");
      return true;
    }
  );
});

test("startPawapayPayout : refuse une commande pas encore reçue par l'acheteur", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("orders").doc("order-pas-complete").set({ status: "paid", items: [] });
  await assert.rejects(
    () =>
      functions.startPawapayPayout.run({
        data: { orderId: "order-pas-complete" },
        auth: { uid: "admin1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
});

test("régression : startPawapayPayout refuse un reversement déjà en cours (pas de double envoi si l'admin déclenche deux fois)", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("orders").doc("order-en-cours").set({
    status: "completed",
    payoutStatus: "processing",
    items: [],
  });
  await assert.rejects(
    () =>
      functions.startPawapayPayout.run({
        data: { orderId: "order-en-cours" },
        auth: { uid: "admin1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
});

test("startPawapayPayout : refuse une commande non payée via pawaPay (aucune transaction correspondante)", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("orders").doc("order-pas-pawapay").set({ status: "completed", items: [] });
  await assert.rejects(
    () =>
      functions.startPawapayPayout.run({
        data: { orderId: "order-pas-pawapay" },
        auth: { uid: "admin1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
});

test("régression : startPawapayPayout refuse une commande à plusieurs vendeurs (reversement manuel requis, jamais reversé au mauvais vendeur)", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("annonces").doc("annonce-a").set({ sellerId: "sellerA", price: 5000 });
  await db.collection("annonces").doc("annonce-b").set({ sellerId: "sellerB", price: 5000 });
  await db.collection("transactions").doc("tx-multi").set({
    status: "paid",
    pawapayDepositId: "dep-multi",
    amount: 10000,
    currency: "FC",
  });
  await db.collection("orders").doc("order-multi").set({
    status: "completed",
    transactionId: "tx-multi",
    items: [
      { sellerId: "sellerA", productId: "annonce-a", quantity: 1, totalPrice: 5000 },
      { sellerId: "sellerB", productId: "annonce-b", quantity: 1, totalPrice: 5000 },
    ],
  });
  await assert.rejects(
    () =>
      functions.startPawapayPayout.run({
        data: { orderId: "order-multi" },
        auth: { uid: "admin1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
});

test("régression : startPawapayPayout refuse tant que le vendeur n'a pas enregistré de numéro de reversement", async () => {
  await db.collection("admins").doc("admin1").set({ uid: "admin1" });
  await db.collection("annonces").doc("annonce-c").set({ sellerId: "sellerC", price: 10000 });
  await db.collection("transactions").doc("tx-c").set({
    status: "paid",
    pawapayDepositId: "dep-c",
    amount: 10000,
    currency: "FC",
  });
  await db.collection("orders").doc("order-c").set({
    status: "completed",
    transactionId: "tx-c",
    items: [{ sellerId: "sellerC", productId: "annonce-c", quantity: 1, totalPrice: 10000 }],
  });
  await assert.rejects(
    () =>
      functions.startPawapayPayout.run({
        data: { orderId: "order-c" },
        auth: { uid: "admin1" },
      }),
    (err) => {
      assert.equal(err.code, "failed-precondition");
      return true;
    }
  );
});

test("checkPawapayPayout : refuse un appelant non administrateur", async () => {
  await assert.rejects(
    () =>
      functions.checkPawapayPayout.run({
        data: { orderId: "order1" },
        auth: { uid: "buyer1" },
      }),
    (err) => {
      assert.equal(err.code, "permission-denied");
      return true;
    }
  );
});

test("statusDayKey : journée à l'heure de Kinshasa (UTC+1), bascule à 23h UTC", () => {
  const { statusDayKey } = functions._testables;
  assert.equal(statusDayKey(Date.parse("2026-09-27T22:59:00Z")), "2026-09-27");
  assert.equal(statusDayKey(Date.parse("2026-09-27T23:00:00Z")), "2026-09-28");
});

test("reserveVideoStatusSlot : quota de statuts vidéo par jour, le suivant est refusé, jamais compté deux fois", async () => {
  const { reserveVideoStatusSlot, MAX_VIDEO_STATUSES_PER_DAY } = functions._testables;
  const now = Date.parse("2026-09-27T10:00:00Z");
  for (let i = 1; i <= MAX_VIDEO_STATUSES_PER_DAY; i++) {
    assert.equal(await reserveVideoStatusSlot("seller-quota", `video-${i}`, now), true);
  }
  // Trigger redélivré pour un statut déjà compté : toujours accepté, sans
  // consommer de place supplémentaire.
  assert.equal(await reserveVideoStatusSlot("seller-quota", "video-3", now), true);
  assert.equal(await reserveVideoStatusSlot("seller-quota", "video-en-trop", now), false);

  // Le lendemain, le quota repart de zéro.
  const tomorrow = Date.parse("2026-09-28T10:00:00Z");
  assert.equal(await reserveVideoStatusSlot("seller-quota", "video-en-trop", tomorrow), true);
  // Un autre vendeur n'est jamais affecté par le quota du premier.
  assert.equal(await reserveVideoStatusSlot("autre-vendeur", "video-x", now), true);
});

async function seedActiveSubscription(uid, daysLeft = 30) {
  await db.collection("subscriptions").doc(uid).set({
    userId: uid,
    isActive: true,
    expiryDate: Timestamp.fromMillis(Date.now() + daysLeft * 86400000),
  });
}

test("régression : onNewStatus retire un statut vidéo publié au-delà du quota quotidien", async () => {
  const { statusDayKey, MAX_VIDEO_STATUSES_PER_DAY } = functions._testables;
  await seedActiveSubscription("seller-plein");
  await db
    .collection("statusDailyCounters")
    .doc(`seller-plein_${statusDayKey()}`)
    .set({
      sellerId: "seller-plein",
      videoStatusIds: Array.from({ length: MAX_VIDEO_STATUSES_PER_DAY }, (_, i) => `v${i}`),
    });
  const statusData = {
    sellerId: "seller-plein",
    sellerName: "Vendeur",
    type: "video",
    mediaUrl: "https://example.com/video.mp4",
    status: "published",
    active: true,
    createdAt: Date.now(),
  };
  await db.collection("statuses").doc("video-en-trop").set(statusData);

  await functions.onNewStatus.run({
    data: { data: () => statusData },
    params: { statusId: "video-en-trop" },
  });

  const snap = await db.collection("statuses").doc("video-en-trop").get();
  assert.equal(snap.exists, false, "le statut au-delà du quota doit être retiré");
});

test("r2KeyFromPublicUrl : ne reconnaît que les URL publiques du bucket R2 (jamais Firebase Storage ni un domaine tiers)", () => {
  const { r2KeyFromPublicUrl, R2_PUBLIC_BASE_URL } = functions._testables;
  assert.equal(
    r2KeyFromPublicUrl(`${R2_PUBLIC_BASE_URL}/statuses/u1/1_abc.mp4`),
    "statuses/u1/1_abc.mp4"
  );
  assert.equal(
    r2KeyFromPublicUrl(
      "https://firebasestorage.googleapis.com/v0/b/x/o/annonces%2Fu1%2Fstatuses%2F1.mp4?alt=media"
    ),
    null
  );
  assert.equal(r2KeyFromPublicUrl("https://pub-autre.r2.dev/statuses/u1/1.mp4"), null);
  assert.equal(r2KeyFromPublicUrl(`${R2_PUBLIC_BASE_URL}/`), null);
  assert.equal(r2KeyFromPublicUrl(undefined), null);
});

test("presignR2Put : taille et type signés (R2 refusera tout envoi différent), validité 10 min", async () => {
  const { presignR2Put } = functions._testables;
  const url = new URL(
    await presignR2Put({
      credentials: { accountId: "acct", accessKeyId: "AK", secretAccessKey: "SK" },
      key: "statuses/u1/1_abc.mp4",
      size: 1234,
      contentType: "video/mp4",
    })
  );
  assert.equal(url.host, "acct.r2.cloudflarestorage.com");
  assert.equal(url.pathname, "/occasion-videos/statuses/u1/1_abc.mp4");
  assert.equal(url.searchParams.get("X-Amz-SignedHeaders"), "content-length;content-type;host");
  assert.equal(url.searchParams.get("X-Amz-Expires"), "600");
  assert.ok(url.searchParams.get("X-Amz-Signature"));
});

test("isActiveSubscription : actif et non expiré uniquement", () => {
  const { isActiveSubscription } = functions._testables;
  const now = Date.parse("2026-09-27T10:00:00Z");
  const future = Timestamp.fromMillis(now + 86400000);
  const past = Timestamp.fromMillis(now - 1);
  assert.equal(isActiveSubscription({ isActive: true, expiryDate: future }, now), true);
  assert.equal(isActiveSubscription({ isActive: true, expiryDate: past }, now), false);
  assert.equal(isActiveSubscription({ isActive: false, expiryDate: future }, now), false);
  assert.equal(isActiveSubscription(undefined, now), false);
});

async function seedR2Seller(uid, { subscribed = true } = {}) {
  await db.collection("users").doc(uid).set({ role: "seller" });
  if (subscribed) {
    await db.collection("subscriptions").doc(uid).set({
      isActive: true,
      expiryDate: Timestamp.fromMillis(Date.now() + 86400000),
    });
  }
}

function expectHttpsError(code) {
  return (err) => {
    assert.equal(err.code, code);
    return true;
  };
}

test("createStatusVideoUpload : refuse un appelant non connecté", async () => {
  await assert.rejects(
    () => functions.createStatusVideoUpload.run({ data: { size: 1000 }, auth: null }),
    expectHttpsError("unauthenticated")
  );
});

test("createStatusVideoUpload : refuse une taille absente, nulle ou au-delà de 5 Mo", async () => {
  await seedR2Seller("seller-r2-size");
  for (const size of [undefined, 0, -1, 1.5, 5 * 1024 * 1024 + 1]) {
    await assert.rejects(
      () =>
        functions.createStatusVideoUpload.run({
          data: { size },
          auth: { uid: "seller-r2-size" },
        }),
      expectHttpsError("invalid-argument")
    );
  }
});

test("createStatusVideoUpload : réservé aux vendeurs abonnés", async () => {
  await db.collection("users").doc("buyer-r2").set({ role: "buyer" });
  await assert.rejects(
    () =>
      functions.createStatusVideoUpload.run({ data: { size: 1000 }, auth: { uid: "buyer-r2" } }),
    expectHttpsError("permission-denied")
  );
  await seedR2Seller("seller-r2-sans-abo", { subscribed: false });
  await assert.rejects(
    () =>
      functions.createStatusVideoUpload.run({
        data: { size: 1000 },
        auth: { uid: "seller-r2-sans-abo" },
      }),
    expectHttpsError("failed-precondition")
  );
});

test("createStatusVideoUpload : refuse d'emblée quand le quota vidéo du jour est atteint", async () => {
  const { statusDayKey, MAX_VIDEO_STATUSES_PER_DAY } = functions._testables;
  await seedR2Seller("seller-r2-plein");
  await db
    .collection("statusDailyCounters")
    .doc(`seller-r2-plein_${statusDayKey()}`)
    .set({
      sellerId: "seller-r2-plein",
      videoStatusIds: Array.from({ length: MAX_VIDEO_STATUSES_PER_DAY }, (_, i) => `v${i}`),
    });
  await assert.rejects(
    () =>
      functions.createStatusVideoUpload.run({
        data: { size: 1000 },
        auth: { uid: "seller-r2-plein" },
      }),
    expectHttpsError("resource-exhausted")
  );
});

test("createStatusVideoUpload : délivre une adresse présignée dans le dossier du vendeur et l'URL publique correspondante", async () => {
  const { R2_PUBLIC_BASE_URL } = functions._testables;
  const previous = {
    key: process.env.R2_ACCESS_KEY_ID,
    secret: process.env.R2_SECRET_ACCESS_KEY,
  };
  process.env.R2_ACCESS_KEY_ID = "AK";
  process.env.R2_SECRET_ACCESS_KEY = "SK";
  try {
    await seedR2Seller("seller-r2-ok");
    const result = await functions.createStatusVideoUpload.run({
      data: { size: 4000000 },
      auth: { uid: "seller-r2-ok" },
    });
    const upload = new URL(result.uploadUrl);
    assert.equal(upload.host, "c5fc6cd0419101796af7b6316a790ab4.r2.cloudflarestorage.com");
    assert.ok(upload.pathname.startsWith("/occasion-videos/statuses/seller-r2-ok/"));
    assert.ok(result.publicUrl.startsWith(`${R2_PUBLIC_BASE_URL}/statuses/seller-r2-ok/`));
    assert.equal(
      upload.pathname.replace("/occasion-videos/", ""),
      result.publicUrl.replace(`${R2_PUBLIC_BASE_URL}/`, "")
    );
    assert.equal(result.contentType, "video/mp4");
  } finally {
    for (const [name, value] of [
      ["R2_ACCESS_KEY_ID", previous.key],
      ["R2_SECRET_ACCESS_KEY", previous.secret],
    ]) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
});

// --- Achat intégré Google Play (confirmPlayPurchase) -----------------------

test("evaluatePlaySubscriptionPurchase : refuse un jeton sans compte externe correspondant à l'appelant", () => {
  const { evaluatePlaySubscriptionPurchase } = functions._testables;
  const sansCompte = evaluatePlaySubscriptionPurchase({
    response: {
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      lineItems: [{ productId: "seller_monthly", expiryTime: "2026-11-01T00:00:00Z" }],
    },
    productId: "seller_monthly",
    uid: "seller1",
  });
  assert.equal(sansCompte.ok, false);
  assert.equal(sansCompte.reason, "account-mismatch");

  const autreCompte = evaluatePlaySubscriptionPurchase({
    response: {
      externalAccountIdentifiers: { obfuscatedExternalAccountId: "un-autre-uid" },
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      lineItems: [{ productId: "seller_monthly", expiryTime: "2026-11-01T00:00:00Z" }],
    },
    productId: "seller_monthly",
    uid: "seller1",
  });
  assert.equal(autreCompte.ok, false);
  assert.equal(autreCompte.reason, "account-mismatch");
});

test("evaluatePlaySubscriptionPurchase : refuse un produit absent des lignes de l'abonnement", () => {
  const { evaluatePlaySubscriptionPurchase } = functions._testables;
  const result = evaluatePlaySubscriptionPurchase({
    response: {
      externalAccountIdentifiers: { obfuscatedExternalAccountId: "seller1" },
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      lineItems: [{ productId: "autre_produit", expiryTime: "2026-11-01T00:00:00Z" }],
    },
    productId: "seller_monthly",
    uid: "seller1",
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, "product-mismatch");
});

test("evaluatePlaySubscriptionPurchase : refuse un abonnement Google Play non actif", () => {
  const { evaluatePlaySubscriptionPurchase } = functions._testables;
  const result = evaluatePlaySubscriptionPurchase({
    response: {
      externalAccountIdentifiers: { obfuscatedExternalAccountId: "seller1" },
      subscriptionState: "SUBSCRIPTION_STATE_CANCELED",
      lineItems: [{ productId: "seller_monthly", expiryTime: "2026-11-01T00:00:00Z" }],
    },
    productId: "seller_monthly",
    uid: "seller1",
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, "not-active");
});

test("evaluatePlaySubscriptionPurchase : accepte un abonnement actif ou en période de grâce, avec sa date d'expiration", () => {
  const { evaluatePlaySubscriptionPurchase } = functions._testables;
  for (const state of ["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"]) {
    const result = evaluatePlaySubscriptionPurchase({
      response: {
        externalAccountIdentifiers: { obfuscatedExternalAccountId: "seller1" },
        subscriptionState: state,
        lineItems: [{ productId: "seller_monthly", expiryTime: "2026-11-01T00:00:00Z" }],
      },
      productId: "seller_monthly",
      uid: "seller1",
    });
    assert.equal(result.ok, true, `état ${state} devrait être accepté`);
    assert.equal(result.expiryDate.toISOString(), "2026-11-01T00:00:00.000Z");
  }
});

/**
 * Clé de service factice (jamais utilisée pour un vrai appel Google, la
 * requête OAuth elle-même est stubbée) — juste assez valide pour que
 * `crypto.sign("RSA-SHA256", ...)` ne lève pas.
 */
function fakePlayServiceAccountJson() {
  const { privateKey } = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });
  return JSON.stringify({
    client_email: "play-verifier@example.iam.gserviceaccount.com",
    private_key: privateKey,
  });
}

async function withStubbedPlayApi(subscriptionResponseFactory, run) {
  const previousSecret = process.env.PLAY_SERVICE_ACCOUNT_JSON;
  const previousFetch = global.fetch;
  process.env.PLAY_SERVICE_ACCOUNT_JSON = fakePlayServiceAccountJson();
  global.fetch = async (url) => {
    const href = String(url);
    if (href.includes("oauth2.googleapis.com/token")) {
      return { ok: true, json: async () => ({ access_token: "fake-access-token" }) };
    }
    if (href.includes("androidpublisher.googleapis.com")) {
      return { ok: true, json: async () => subscriptionResponseFactory() };
    }
    throw new Error(`URL inattendue dans le test : ${href}`);
  };
  try {
    await run();
  } finally {
    global.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.PLAY_SERVICE_ACCOUNT_JSON;
    else process.env.PLAY_SERVICE_ACCOUNT_JSON = previousSecret;
  }
}

test("confirmPlayPurchase : refuse un appel non connecté ou un productId/purchaseToken manquant ou inconnu", async () => {
  await assert.rejects(
    () => functions.confirmPlayPurchase.run({ data: {}, auth: null }),
    expectHttpsError("unauthenticated")
  );
  await assert.rejects(
    () =>
      functions.confirmPlayPurchase.run({
        data: { purchaseToken: "tok1" },
        auth: { uid: "seller1" },
      }),
    expectHttpsError("invalid-argument")
  );
  await assert.rejects(
    () =>
      functions.confirmPlayPurchase.run({
        data: { productId: "seller_monthly" },
        auth: { uid: "seller1" },
      }),
    expectHttpsError("invalid-argument")
  );
  await assert.rejects(
    () =>
      functions.confirmPlayPurchase.run({
        data: { productId: "produit_inconnu", purchaseToken: "tok1" },
        auth: { uid: "seller1" },
      }),
    expectHttpsError("invalid-argument")
  );
});

test("confirmPlayPurchase : vérifie l'achat auprès de Google Play puis active l'abonnement, de façon idempotente", async () => {
  await withStubbedPlayApi(
    () => ({
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      externalAccountIdentifiers: { obfuscatedExternalAccountId: "seller-play" },
      lineItems: [{ productId: "seller_monthly", expiryTime: "2026-11-01T00:00:00Z" }],
    }),
    async () => {
      await db.collection("users").doc("seller-play").set({ role: "seller" });

      const result = await functions.confirmPlayPurchase.run({
        data: { productId: "seller_monthly", purchaseToken: "tok-play-1" },
        auth: { uid: "seller-play" },
      });
      assert.equal(result.status, "active");
      assert.equal(result.expiryDate, "2026-11-01T00:00:00.000Z");

      const subSnap = await db.collection("subscriptions").doc("seller-play").get();
      assert.equal(subSnap.data().isActive, true);
      assert.equal(subSnap.data().paymentMethod, "google_play");
      assert.equal(subSnap.data().planId, "seller_monthly");
      assert.equal(subSnap.data().transactionId, "tok-play-1");

      const userSnap = await db.collection("users").doc("seller-play").get();
      assert.equal(userSnap.data().sellerSubscriptionActive, true);

      const purchaseSnap = await db.collection("playPurchases").doc("tok-play-1").get();
      assert.equal(purchaseSnap.data().userId, "seller-play");

      // Même jeton revérifié (ex. restorePurchases() au démarrage de l'app,
      // seule façon de refléter un renouvellement automatique faute de
      // notification serveur Play en place) : idempotent, ne fait que
      // rafraîchir l'expiration, jamais dupliquer/écraser au hasard.
      const second = await functions.confirmPlayPurchase.run({
        data: { productId: "seller_monthly", purchaseToken: "tok-play-1" },
        auth: { uid: "seller-play" },
      });
      assert.equal(second.status, "active");

      // Le même jeton, revendiqué par un AUTRE compte, doit être refusé —
      // un purchaseToken Play ne prouve rien sur qui l'a réellement payé.
      // Rejeté dès `evaluatePlaySubscriptionPurchase` (le compte externe
      // renvoyé par Google reste "seller-play", pas "seller-play-2") : voir
      // le test dédié ci-dessous pour le filet de sécurité supplémentaire
      // au niveau de la transaction Firestore (`playPurchases`).
      await db.collection("users").doc("seller-play-2").set({ role: "seller" });
      await assert.rejects(
        () =>
          functions.confirmPlayPurchase.run({
            data: { productId: "seller_monthly", purchaseToken: "tok-play-1" },
            auth: { uid: "seller-play-2" },
          }),
        expectHttpsError("failed-precondition")
      );
    }
  );
});

test("confirmPlayPurchase : filet de sécurité — refuse un jeton déjà enregistré (playPurchases) au nom d'un autre compte", async () => {
  // Scénario qui ne devrait jamais se produire via le flux normal (le
  // compte externe Google est déjà vérifié avant d'atteindre ce point),
  // mais défendu quand même : si `playPurchases/{token}.userId` diffère de
  // l'appelant, la transaction refuse plutôt que d'écraser le propriétaire
  // enregistré.
  await db.collection("playPurchases").doc("tok-hijack").set({ userId: "victime" });
  await withStubbedPlayApi(
    () => ({
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      externalAccountIdentifiers: { obfuscatedExternalAccountId: "attaquant" },
      lineItems: [{ productId: "seller_monthly", expiryTime: "2026-11-01T00:00:00Z" }],
    }),
    async () => {
      await db.collection("users").doc("attaquant").set({ role: "seller" });
      await assert.rejects(
        () =>
          functions.confirmPlayPurchase.run({
            data: { productId: "seller_monthly", purchaseToken: "tok-hijack" },
            auth: { uid: "attaquant" },
          }),
        expectHttpsError("permission-denied")
      );
    }
  );
});

test("confirmPlayPurchase : refuse un abonnement Google Play non actif (annulé/expiré)", async () => {
  await withStubbedPlayApi(
    () => ({
      subscriptionState: "SUBSCRIPTION_STATE_CANCELED",
      externalAccountIdentifiers: { obfuscatedExternalAccountId: "seller-play-3" },
      lineItems: [{ productId: "seller_monthly", expiryTime: "2026-11-01T00:00:00Z" }],
    }),
    async () => {
      await db.collection("users").doc("seller-play-3").set({ role: "seller" });
      await assert.rejects(
        () =>
          functions.confirmPlayPurchase.run({
            data: { productId: "seller_monthly", purchaseToken: "tok-play-3" },
            auth: { uid: "seller-play-3" },
          }),
        expectHttpsError("failed-precondition")
      );

      const purchaseSnap = await db.collection("playPurchases").doc("tok-play-3").get();
      assert.equal(purchaseSnap.exists, false);
    }
  );
});

// ---------------------------------------------------------------------------
// Suppression de compte (deleteAccount / deleteUserData)
// ---------------------------------------------------------------------------

function fakeDeletionDeps() {
  const calls = { storage: [], presence: [], auth: [] };
  return {
    calls,
    deps: {
      deleteStorageFiles: async (uid) => calls.storage.push(uid),
      deleteRealtimePresence: async (uid) => calls.presence.push(uid),
      deleteAuthUser: async (uid) => calls.auth.push(uid),
    },
  };
}

test("deleteUserData : efface ou anonymise toutes les données de la personne, jamais celles des autres", async () => {
  const { deleteUserData, DELETED_USER_NAME } = functions._testables;
  const uid = "partant";
  const other = "autre";

  await db.collection("users").doc(uid).set({
    name: "Alice",
    phone: "+243800000000",
    role: "seller",
    referralCode: "ALICE1",
  });
  await db.collection("users").doc(uid).collection("devices").doc("d1").set({ token: "t" });
  await db.collection("users").doc(uid).collection("blockedUsers").doc(other).set({ at: 1 });
  await db.collection("publicProfiles").doc(uid).set({
    id: uid,
    name: "Alice",
    profileImageUrl: "https://x/alice.jpg",
    ratingCount: 3,
  });
  await db.collection("annonces").doc("a-partant").set({ vendeurId: uid, titre: "Vélo" });
  await db.collection("annonces").doc("a-partant").collection("viewers").doc("v").set({ at: 1 });
  await db.collection("annonces").doc("a-autre").set({ vendeurId: other, titre: "Table" });
  await db.collection("statuses").doc("s-partant").set({ sellerId: uid, likesCount: 1 });
  await db.collection("statusLikes").doc(`s-partant_${other}`).set({ statusId: "s-partant", userId: other });
  await db.collection("statuses").doc("s-autre").set({ sellerId: other, likesCount: 1 });
  await db.collection("statusLikes").doc(`s-autre_${uid}`).set({ statusId: "s-autre", userId: uid });
  await db.collection("statusViews").doc(`s-autre_${uid}`).set({ statusId: "s-autre", userId: uid });
  await db.collection("favoris").doc("f").set({ utilisateurId: uid, annonceId: "a-autre" });
  await db.collection("searchAlerts").doc("al").set({ userId: uid, keyword: "vélo" });
  await db.collection("notifications").doc("n").set({ recipientId: uid, title: "x" });
  await db.collection("notifications").doc("n-autre").set({ recipientId: other, title: "x" });
  await db.collection("chats").doc("c").set({
    buyerId: uid,
    sellerId: other,
    buyerName: "Alice",
    buyerProfileImageUrl: "https://x/alice.jpg",
    sellerName: "Bob",
  });
  await db.collection("orders").doc("o-pending").set({
    buyerId: uid,
    buyerName: "Alice",
    buyerPhone: "+243800000000",
    status: "pending_payment",
  });
  await db.collection("orders").doc("o-done").set({
    buyerId: uid,
    buyerName: "Alice",
    buyerPhone: "+243800000000",
    status: "payout_sent",
  });
  await db.collection("subscriptions").doc(uid).set({ isActive: true });
  await db.collection("payoutAccounts").doc(uid).set({ phoneNumber: "0800" });
  await db.collection("loyaltyPoints").doc(`${uid}_${other}`).set({ buyerId: uid, sellerId: other });
  await db.collection("giftCatalogItems").doc("g").set({ sellerId: uid, isActive: true });
  await db.collection("admins").doc(uid).set({ since: 1 });

  const { calls, deps } = fakeDeletionDeps();
  await deleteUserData(uid, deps);

  const user = (await db.collection("users").doc(uid).get()).data();
  assert.deepEqual(Object.keys(user).sort(), ["deletedAt", "isDeleted", "name"]);
  assert.equal(user.name, DELETED_USER_NAME);
  assert.equal((await db.collection("users").doc(uid).collection("devices").get()).size, 0);
  assert.equal((await db.collection("users").doc(uid).collection("blockedUsers").get()).size, 0);

  const profile = (await db.collection("publicProfiles").doc(uid).get()).data();
  assert.equal(profile.name, DELETED_USER_NAME);
  assert.equal(profile.profileImageUrl, null);
  assert.equal(profile.isDeleted, true);

  assert.equal((await db.collection("annonces").doc("a-partant").get()).exists, false);
  assert.equal((await db.collection("annonces").doc("a-partant").collection("viewers").get()).size, 0);
  assert.equal((await db.collection("annonces").doc("a-autre").get()).exists, true);

  assert.equal((await db.collection("statuses").doc("s-partant").get()).exists, false);
  assert.equal((await db.collection("statusLikes").doc(`s-partant_${other}`).get()).exists, false);
  assert.equal((await db.collection("statusLikes").doc(`s-autre_${uid}`).get()).exists, false);
  assert.equal((await db.collection("statuses").doc("s-autre").get()).data().likesCount, 0);

  for (const [collection, id] of [
    ["statusViews", `s-autre_${uid}`],
    ["favoris", "f"],
    ["searchAlerts", "al"],
    ["notifications", "n"],
    ["subscriptions", uid],
    ["payoutAccounts", uid],
    ["loyaltyPoints", `${uid}_${other}`],
    ["giftCatalogItems", "g"],
    ["admins", uid],
  ]) {
    assert.equal(
      (await db.collection(collection).doc(id).get()).exists,
      false,
      `${collection}/${id} aurait dû être supprimé`
    );
  }
  assert.equal((await db.collection("notifications").doc("n-autre").get()).exists, true);

  const chat = (await db.collection("chats").doc("c").get()).data();
  assert.equal(chat.buyerName, DELETED_USER_NAME);
  assert.equal(chat.buyerProfileImageUrl, null);
  assert.equal(chat.sellerName, "Bob");

  const pending = (await db.collection("orders").doc("o-pending").get()).data();
  assert.equal(pending.status, "cancelled");
  assert.equal(pending.buyerName, DELETED_USER_NAME);
  assert.equal(pending.buyerPhone, "");
  const done = (await db.collection("orders").doc("o-done").get()).data();
  assert.equal(done.status, "payout_sent", "historique comptable conservé");
  assert.equal(done.buyerPhone, "");

  assert.deepEqual(calls, { storage: [uid], presence: [uid], auth: [uid] });
});

test("deleteUserData : relançable après une interruption (aucune erreur au second passage)", async () => {
  const { deleteUserData } = functions._testables;
  await db.collection("users").doc("u").set({ name: "A" });
  await db.collection("favoris").doc("f").set({ utilisateurId: "u" });

  await deleteUserData("u", fakeDeletionDeps().deps);
  await deleteUserData("u", fakeDeletionDeps().deps);

  assert.equal((await db.collection("favoris").doc("f").get()).exists, false);
});

test("deleteUserData : le compte Auth n'est jamais supprimé si une étape précédente échoue", async () => {
  const { deleteUserData } = functions._testables;
  await db.collection("users").doc("u").set({ name: "A" });
  const { calls, deps } = fakeDeletionDeps();
  deps.deleteStorageFiles = async () => {
    throw new Error("Storage indisponible");
  };

  await assert.rejects(deleteUserData("u", deps), /Storage indisponible/);
  assert.deepEqual(calls.auth, []);
});

test("accountDeletionBlockers : bloque tant que de l'argent ou des points sont en jeu", async () => {
  const { accountDeletionBlockers } = functions._testables;

  assert.deepEqual(await accountDeletionBlockers("u"), []);

  await db.collection("orders").doc("buyer-done").set({ buyerId: "u", sellerIds: ["s"], status: "completed" });
  await db.collection("orders").doc("buyer-cancel").set({ buyerId: "u", sellerIds: ["s"], status: "cancelled" });
  assert.deepEqual(
    await accountDeletionBlockers("u"),
    [],
    "'completed' côté acheteur est terminé pour lui"
  );
  assert.deepEqual(
    await accountDeletionBlockers("s"),
    ["orders"],
    "'completed' côté vendeur = reversement encore à envoyer"
  );

  await db.collection("orders").doc("buyer-paid").set({ buyerId: "u", sellerIds: ["s"], status: "paid" });
  assert.deepEqual(await accountDeletionBlockers("u"), ["orders"]);

  await db.collection("giftRedemptions").doc("r").set({ buyerId: "x", sellerId: "y", status: "pending" });
  assert.deepEqual(await accountDeletionBlockers("x"), ["giftRedemptions"]);
  assert.deepEqual(await accountDeletionBlockers("y"), ["giftRedemptions"]);
});

test("deleteAccount : refuse sans connexion, et refuse sans rien effacer si une commande est en cours", async () => {
  await assert.rejects(
    functions.deleteAccount.run({ data: {} }),
    (err) => err.code === "unauthenticated"
  );

  await db.collection("users").doc("u").set({ name: "Alice" });
  await db.collection("orders").doc("o").set({ buyerId: "u", sellerIds: ["s"], status: "disputed" });

  await assert.rejects(
    functions.deleteAccount.run({ data: {}, auth: { uid: "u" } }),
    (err) => err.code === "failed-precondition"
  );
  assert.equal((await db.collection("users").doc("u").get()).data().name, "Alice");
});

// ---------------------------------------------------------------------------
// Verrouillage serveur : statuts et formule gratuite
// ---------------------------------------------------------------------------

function statusEvent(statusId, statusData, time) {
  return { data: { data: () => statusData }, params: { statusId }, time };
}

test("onNewStatus : retire un statut publié sans abonnement actif (client modifié / abonnement expiré)", async () => {
  const data = { sellerId: "s-sans-abo", type: "image", mediaUrl: null, createdAt: 1 };
  await db.collection("statuses").doc("st1").set(data);
  await db.collection("subscriptions").doc("s-sans-abo").set({
    isActive: true,
    expiryDate: Timestamp.fromMillis(Date.now() - 1000),
  });

  await functions.onNewStatus.run(statusEvent("st1", data));

  assert.equal((await db.collection("statuses").doc("st1").get()).exists, false);
});

test("onNewStatus : garde le statut d'un abonné et recale createdAt sur l'heure serveur", async () => {
  await seedActiveSubscription("s-abo");
  const data = {
    sellerId: "s-abo",
    type: "image",
    mediaUrl: null,
    createdAt: 9999999999999, // horloge de téléphone dans le futur
  };
  await db.collection("statuses").doc("st2").set(data);

  const time = "2026-10-02T12:00:00.000Z";
  await functions.onNewStatus.run(statusEvent("st2", data, time));

  const snap = await db.collection("statuses").doc("st2").get();
  assert.equal(snap.exists, true);
  assert.equal(snap.data().createdAt, Date.parse(time));
});

test("isVideoStatus : une vidéo déclarée « image » est quand même comptée comme vidéo", () => {
  const { isVideoStatus } = functions._testables;
  assert.equal(isVideoStatus({ type: "video" }), true);
  assert.equal(
    isVideoStatus({ type: "image", mediaUrl: "https://pub.r2.dev/statuses/u/1_a.mp4" }),
    true
  );
  assert.equal(
    isVideoStatus({
      type: "image",
      mediaUrl:
        "https://firebasestorage.googleapis.com/v0/b/x/o/annonces%2Fu%2Fstatuses%2F1.MP4?alt=media&token=t",
    }),
    true
  );
  assert.equal(
    isVideoStatus({ type: "image", mediaUrl: "https://x/o/annonces%2Fu%2Fstatuses%2F1.jpg?alt=media" }),
    false
  );
});

function liveAnnonce(sellerId, extra = {}) {
  return {
    vendeurId: sellerId,
    sellerId,
    title: "Article",
    description: "",
    isPublished: true,
    active: true,
    status: "published",
    statut: "published",
    ...extra,
  };
}

test("formule gratuite : une 2e annonce mise en ligne repasse en brouillon, la 1re reste en ligne", async () => {
  await db.collection("annonces").doc("premiere").set(liveAnnonce("gratuit"));
  const seconde = liveAnnonce("gratuit");
  await db.collection("annonces").doc("seconde").set(seconde);

  await functions.onAnnonceCreated.run({
    data: { data: () => seconde },
    params: { annonceId: "seconde" },
  });

  const second = (await db.collection("annonces").doc("seconde").get()).data();
  assert.equal(second.isPublished, false);
  assert.equal(second.active, false);
  assert.equal(second.status, "draft");
  assert.equal((await db.collection("annonces").doc("premiere").get()).data().isPublished, true);
  assert.ok(
    (await db.collection("notifications").doc("freePlanLimit_seconde").get()).exists,
    "le vendeur est prévenu"
  );
});

test("formule vendeur : plusieurs annonces en ligne autorisées", async () => {
  await seedActiveSubscription("abonne");
  await db.collection("annonces").doc("a1").set(liveAnnonce("abonne"));
  const a2 = liveAnnonce("abonne");
  await db.collection("annonces").doc("a2").set(a2);

  await functions.onAnnonceCreated.run({ data: { data: () => a2 }, params: { annonceId: "a2" } });

  assert.equal((await db.collection("annonces").doc("a2").get()).data().isPublished, true);
});

test("formule gratuite : republier un brouillon est vérifié, modifier une annonce déjà en ligne ne dépublie jamais", async () => {
  await db.collection("annonces").doc("en-ligne").set(liveAnnonce("gratuit2"));
  const draft = liveAnnonce("gratuit2", {
    isPublished: false,
    active: false,
    status: "draft",
    statut: "draft",
  });
  const republished = liveAnnonce("gratuit2");
  await db.collection("annonces").doc("brouillon").set(republished);

  await functions.onAnnonceUpdated.run({
    id: "evt-republish",
    data: {
      before: { data: () => draft },
      after: { data: () => republished },
    },
    params: { annonceId: "brouillon" },
  });
  assert.equal((await db.collection("annonces").doc("brouillon").get()).data().isPublished, false);

  // Abonnement expiré avec deux annonces déjà en ligne : une simple
  // modification (ex. vendue) ne touche à rien.
  await db.collection("annonces").doc("autre-en-ligne").set(liveAnnonce("gratuit2"));
  const before = liveAnnonce("gratuit2");
  const after = liveAnnonce("gratuit2", { saleState: "sold" });
  await functions.onAnnonceUpdated.run({
    id: "evt-edit",
    data: { before: { data: () => before }, after: { data: () => after } },
    params: { annonceId: "autre-en-ligne" },
  });
  assert.equal((await db.collection("annonces").doc("autre-en-ligne").get()).data().isPublished, true);
});

// ---------------------------------------------------------------------------
// Formule gratuite : 2 photos par annonce (appliqué par les triggers, plus
// par firestore.rules — voir enforceFreePlanPhotoLimit)
// ---------------------------------------------------------------------------

const photoUrls = (n) => Array.from({ length: n }, (_, i) => `https://example.com/${i}.jpg`);

test("formule gratuite : une annonce à 3 photos est ramenée à ses 2 premières, le vendeur est prévenu", async () => {
  const annonce = { vendeurId: "gratuit-photos", imageUrls: photoUrls(3), images: photoUrls(3), isPublished: false };
  await db.collection("annonces").doc("p3").set(annonce);

  await functions.onAnnonceCreated.run({ data: { data: () => annonce }, params: { annonceId: "p3" } });

  const data = (await db.collection("annonces").doc("p3").get()).data();
  assert.deepEqual(data.imageUrls, photoUrls(2));
  assert.deepEqual(data.images, photoUrls(2));
  assert.ok((await db.collection("notifications").doc("freePlanPhotos_p3_3").get()).exists);
});

test("formule vendeur : une annonce à 5 photos est gardée telle quelle", async () => {
  await seedActiveSubscription("abonne-photos");
  const annonce = { vendeurId: "abonne-photos", imageUrls: photoUrls(5), images: photoUrls(5), isPublished: false };
  await db.collection("annonces").doc("p5").set(annonce);

  await functions.onAnnonceCreated.run({ data: { data: () => annonce }, params: { annonceId: "p5" } });

  assert.equal((await db.collection("annonces").doc("p5").get()).data().imageUrls.length, 5);
});

test("abonnement expiré : modifier une annonce à 5 photos sans toucher aux photos ne les réduit jamais", async () => {
  const before = { vendeurId: "expire-photos", imageUrls: photoUrls(5), price: 10 };
  const after = { ...before, saleState: "sold" };
  await db.collection("annonces").doc("e5").set(after);

  await functions.onAnnonceUpdated.run({
    id: "evt-e5",
    data: { before: { data: () => before }, after: { data: () => after } },
    params: { annonceId: "e5" },
  });

  assert.equal((await db.collection("annonces").doc("e5").get()).data().imageUrls.length, 5);
});
