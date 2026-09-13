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
    "favoris",
    "reviews",
    "publicProfiles",
    "searchAlerts",
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

test("forwardChatMessage : transfère texte+média vers une autre conversation sans dupliquer le fichier Storage", async () => {
  const sourceChatId = "chat-fwd-source";
  const targetChatId = "chat-fwd-target";
  await seedChat(sourceChatId);
  await db.collection("chats").doc(targetChatId).set({
    buyerId: "buyer1",
    sellerId: "seller2",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });

  const mediaUrl = chatMediaUrl(sourceChatId, "src-msg.jpg");
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
  assert.equal(fwdSnap.data().mediaUrl, mediaUrl, "réutilise la MÊME URL, jamais un nouveau fichier Storage");
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
  await db.collection("orders").doc("order1").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
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
  await db.collection("orders").doc("order2").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
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
  await db.collection("orders").doc("order3").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
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
  await db.collection("orders").doc("order4").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
    status: "completed",
  });
  await db.collection("orders").doc("order5").set({
    buyerId: "buyer2",
    sellerIds: ["seller1"],
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
  await db.collection("orders").doc("order-paid").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
    status: "paid",
  });
  await db.collection("orders").doc("order-completed").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
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

test("submitReview : accepte aussi une commande déjà reversée (payout_sent), pas seulement completed", async () => {
  await db.collection("orders").doc("order-payout").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
    status: "payout_sent",
  });

  const result = await functions.submitReview.run({
    data: { orderId: "order-payout", sellerId: "seller1", rating: 5, comment: "" },
    auth: { uid: "buyer1" },
  });

  assert.equal(result.alreadyExisted, false);
});

test("notifySettlement (paiement) : mirroire aussi totalSales dans publicProfiles, pas seulement sellerStatistics", async () => {
  await db.collection("orders").doc("order-settle").set({
    buyerId: "buyer1",
    sellerIds: ["seller1"],
    items: [{ sellerId: "seller1", totalPrice: 5000 }],
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
