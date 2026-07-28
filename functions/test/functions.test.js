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
