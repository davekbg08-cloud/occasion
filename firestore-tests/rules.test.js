const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

let testEnv;

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "occasion-rules-test",
    firestore: {
      rules: fs.readFileSync(
        path.join(__dirname, "..", "firestore.rules"),
        "utf8"
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

test.after(async () => {
  await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seed(uid, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("users").doc(uid).set(data);
  });
}

test("un acheteur peut créer son propre compte avec le rôle buyer", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer
      .collection("users")
      .doc("buyer1")
      .set({
        id: "buyer1",
        role: "buyer",
        identityStatus: "unverified",
        sellerStatus: "unverified",
      })
  );
});

test("un acheteur ne peut pas s'attribuer le rôle seller après création (auto-élévation)", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer" });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").update({ role: "seller" })
  );
});

test("un acheteur ne peut pas s'auto-vérifier l'identité (identityStatus: 'verified')", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer", identityStatus: "unverified" });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("users")
      .doc("buyer1")
      .update({ identityStatus: "verified", sellerStatus: "verified" })
  );
});

test("un acheteur ne peut pas s'attribuer un abonnement vendeur actif", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer" });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").update({
      sellerSubscriptionActive: true,
      sellerSubscriptionExpiresAt: new Date(),
    })
  );
});

test("un client ne peut pas s'attribuer unreadMessageCount à la création du compte", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").set({
      id: "buyer1",
      role: "buyer",
      unreadMessageCount: 99,
    })
  );
});

test("un client ne peut jamais modifier son propre unreadMessageCount (source unique : le serveur)", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer", unreadMessageCount: 3 });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").update({ unreadMessageCount: 0 })
  );
});

test("un client ne peut pas passer une commande à 'paid' directement", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("orders").doc("order1").set({
      buyerId: "buyer1",
      status: "pending_payment",
    })
  );
  await assertFails(
    buyer.collection("orders").doc("order1").update({ status: "paid" })
  );
});

test("un client ne peut pas passer un paymentIntent à 'paid' directement", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("paymentIntents").doc("pi1").set({
      userId: "buyer1",
      status: "pending",
    })
  );
  await assertFails(
    buyer.collection("paymentIntents").doc("pi1").update({ status: "paid" })
  );
});

test("un client ne peut pas créer/modifier un document subscriptions", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("subscriptions").doc("buyer1").set({
      userId: "buyer1",
      isActive: true,
    })
  );
});

test("un client ne peut pas créer/modifier un document admins", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("admins").doc("buyer1").set({ uid: "buyer1" })
  );
});

test("un utilisateur peut lire un chat inexistant sans permission-denied (check-then-create)", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(buyer.collection("chats").doc("chat-inexistant").get());
});

test("un participant peut lire son propre chat existant", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(buyer.collection("chats").doc("chat1").get());
});

test("un utilisateur qui n'est pas participant ne peut pas lire un chat existant", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
  });
  const outsider = testEnv.authenticatedContext("buyer2").firestore();
  await assertFails(outsider.collection("chats").doc("chat1").get());
});

test("un acheteur ne peut plus remettre à zéro son propre compteur non-lu (passe par markChatAsRead)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 3,
      sellerUnreadCount: 2,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("chats").doc("chat1").update({ buyerUnreadCount: 0 })
  );
});

test("un acheteur ne peut pas modifier le compteur non-lu du vendeur", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 3,
      sellerUnreadCount: 2,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("chats").doc("chat1").update({ sellerUnreadCount: 0 })
  );
});

test("un acheteur ne peut plus incrémenter son propre compteur non-lu (serveur uniquement)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 0,
      sellerUnreadCount: 0,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("chats").doc("chat1").update({ buyerUnreadCount: 1 })
  );
});

test("un vendeur ne peut plus incrémenter son propre compteur non-lu (serveur uniquement)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 0,
      sellerUnreadCount: 0,
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller.collection("chats").doc("chat1").update({ sellerUnreadCount: 5 })
  );
});

test("un vendeur ne peut plus remettre à zéro son propre compteur non-lu (passe par markChatAsRead)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 1,
      sellerUnreadCount: 4,
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller.collection("chats").doc("chat1").update({ sellerUnreadCount: 0 })
  );
});

test("un acheteur ne peut plus décrémenter son propre compteur non-lu, même partiellement", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 5,
      sellerUnreadCount: 0,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("chats").doc("chat1").update({ buyerUnreadCount: 3 })
  );
});

test("un acheteur ne peut toujours pas augmenter son propre compteur même partiellement", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 2,
      sellerUnreadCount: 0,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("chats").doc("chat1").update({ buyerUnreadCount: 3 })
  );
});

test("un participant peut toujours modifier les autres métadonnées du chat (lastMessage)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 0,
      sellerUnreadCount: 0,
      lastMessage: "",
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer
      .collection("chats")
      .doc("chat1")
      .update({ lastMessage: "Bonjour", lastMessageAt: Date.now(), lastSenderId: "buyer1" })
  );
});

test("un acheteur peut créer un message vers le vendeur du chat", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer
      .collection("chats")
      .doc("chat1")
      .collection("messages")
      .doc("m1")
      .set({
        senderId: "buyer1",
        receiverId: "seller1",
        content: "Bonjour",
        status: "sent",
        sentAt: Date.now(),
      })
  );
});

test("un vendeur peut créer un message vers l'acheteur du chat", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(
    seller
      .collection("chats")
      .doc("chat1")
      .collection("messages")
      .doc("m2")
      .set({
        senderId: "seller1",
        receiverId: "buyer1",
        content: "Bonjour !",
        status: "sent",
        sentAt: Date.now(),
      })
  );
});

test("les deux participants peuvent lire les messages du chat, pas un tiers", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
    await ctx
      .firestore()
      .collection("chats")
      .doc("chat1")
      .collection("messages")
      .doc("m1")
      .set({
        senderId: "buyer1",
        receiverId: "seller1",
        content: "Bonjour",
        status: "sent",
        sentAt: Date.now(),
      });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  const seller = testEnv.authenticatedContext("seller1").firestore();
  const outsider = testEnv.authenticatedContext("buyer2").firestore();
  await assertSucceeds(
    buyer.collection("chats").doc("chat1").collection("messages").doc("m1").get()
  );
  await assertSucceeds(
    seller.collection("chats").doc("chat1").collection("messages").doc("m1").get()
  );
  await assertFails(
    outsider.collection("chats").doc("chat1").collection("messages").doc("m1").get()
  );
});

test("le destinataire ne peut plus marquer directement un message comme lu (passe par markChatAsRead)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
    await ctx.firestore().collection("chats").doc("chat1").collection("messages").doc("m1").set({
      senderId: "buyer1",
      receiverId: "seller1",
      content: "Bonjour",
      status: "sent",
      sentAt: Date.now(),
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller
      .collection("chats")
      .doc("chat1")
      .collection("messages")
      .doc("m1")
      .update({ status: "read" })
  );
});

test("aucun participant ne peut modifier unreadProcessed/unreadIncrementApplied sur un message", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
    await ctx.firestore().collection("chats").doc("chat1").collection("messages").doc("m1").set({
      senderId: "buyer1",
      receiverId: "seller1",
      content: "Bonjour",
      status: "sent",
      sentAt: Date.now(),
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("chats")
      .doc("chat1")
      .collection("messages")
      .doc("m1")
      .update({ unreadProcessed: true, unreadIncrementApplied: false })
  );
});

test("un message ne peut pas être supprimé par un participant", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
    await ctx.firestore().collection("chats").doc("chat1").collection("messages").doc("m1").set({
      senderId: "buyer1",
      receiverId: "seller1",
      content: "Bonjour",
      status: "sent",
      sentAt: Date.now(),
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("chats").doc("chat1").collection("messages").doc("m1").delete()
  );
});

test("un client ne peut pas créer directement une notification (réservé au serveur)", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("notifications").doc("n1").set({
      recipientId: "buyer1",
      type: "system",
      title: "Test",
      body: "Test",
      isRead: false,
    })
  );
});

test("un destinataire peut lire sa propre notification", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("notifications").doc("n1").set({
      recipientId: "buyer1",
      type: "message",
      title: "Test",
      body: "Test",
      isRead: false,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(buyer.collection("notifications").doc("n1").get());
});

test("un autre utilisateur ne peut pas lire la notification d'autrui", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("notifications").doc("n1").set({
      recipientId: "buyer1",
      type: "message",
      title: "Test",
      body: "Test",
      isRead: false,
    });
  });
  const outsider = testEnv.authenticatedContext("buyer2").firestore();
  await assertFails(outsider.collection("notifications").doc("n1").get());
});

test("un destinataire peut marquer sa notification comme lue", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("notifications").doc("n1").set({
      recipientId: "buyer1",
      type: "message",
      title: "Test",
      body: "Test",
      isRead: false,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer
      .collection("notifications")
      .doc("n1")
      .update({ isRead: true, readAt: new Date() })
  );
});

test("un destinataire ne peut pas modifier le contenu de sa notification", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("notifications").doc("n1").set({
      recipientId: "buyer1",
      type: "message",
      title: "Test",
      body: "Test",
      isRead: false,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("notifications").doc("n1").update({ title: "Modifié" })
  );
});

test("un destinataire peut supprimer sa propre notification", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("notifications").doc("n1").set({
      recipientId: "buyer1",
      type: "message",
      title: "Test",
      body: "Test",
      isRead: false,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(buyer.collection("notifications").doc("n1").delete());
});

test("un utilisateur peut gérer ses propres jetons d'appareil (devices)", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer
      .collection("users")
      .doc("buyer1")
      .collection("devices")
      .doc("device1")
      .set({ token: "fcm-token", platform: "android" })
  );
});

test("un utilisateur ne peut pas lire les jetons d'appareil d'autrui", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("users")
      .doc("buyer1")
      .collection("devices")
      .doc("device1")
      .set({ token: "fcm-token", platform: "android" });
  });
  const outsider = testEnv.authenticatedContext("buyer2").firestore();
  await assertFails(
    outsider
      .collection("users")
      .doc("buyer1")
      .collection("devices")
      .doc("device1")
      .get()
  );
});

function validAnnonceSeed(overrides) {
  return {
    sellerId: "seller1",
    title: "Annonce test",
    description: "Description test",
    price: 100,
    currency: "FC",
    category: "Divers",
    imageUrls: [],
    isPublished: true,
    status: "published",
    vues: 0,
    favoris: 0,
    ...overrides,
  };
}

test("un utilisateur ne peut plus incrémenter directement les vues d'une annonce", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("annonces").doc("annonce1").update({ vues: 1 })
  );
});

test("un utilisateur peut toujours (dé)favoriser une annonce (non affecté par le retrait de vues)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("annonces").doc("annonce1").update({ favoris: 1 })
  );
});

test("un client ne peut pas écrire dans la sous-collection viewers d'une annonce", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("annonces")
      .doc("annonce1")
      .collection("viewers")
      .doc("buyer1")
      .set({ viewedAt: new Date() })
  );
});

test("un vendeur peut lire ses propres statistiques", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("sellerStatistics").doc("seller1").set({
      totalViews: 10,
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(
    seller.collection("sellerStatistics").doc("seller1").get()
  );
});

test("un vendeur ne peut pas lire les statistiques d'un autre vendeur", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("sellerStatistics").doc("seller1").set({
      totalViews: 10,
    });
  });
  const outsider = testEnv.authenticatedContext("seller2").firestore();
  await assertFails(
    outsider.collection("sellerStatistics").doc("seller1").get()
  );
});

test("un vendeur ne peut pas écrire directement ses propres statistiques", async () => {
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller
      .collection("sellerStatistics")
      .doc("seller1")
      .set({ totalViews: 999 })
  );
});

test("un acheteur peut lire son propre solde de points de fidélité", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("loyaltyPoints").doc("buyer1_seller1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      balance: 40,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("loyaltyPoints").doc("buyer1_seller1").get()
  );
});

test("un acheteur ne peut pas lire le solde de points d'un autre acheteur", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("loyaltyPoints").doc("buyer1_seller1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      balance: 40,
    });
  });
  const outsider = testEnv.authenticatedContext("buyer2").firestore();
  await assertFails(
    outsider.collection("loyaltyPoints").doc("buyer1_seller1").get()
  );
});

test("un acheteur ne peut pas modifier directement son solde de points", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("loyaltyPoints").doc("buyer1_seller1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      balance: 40,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("loyaltyPoints")
      .doc("buyer1_seller1")
      .update({ balance: 999999 })
  );
});

function validGiftItemSeed(overrides) {
  return {
    sellerId: "seller1",
    title: "Casquette",
    description: "Casquette brodée",
    pointsCost: 100,
    isActive: true,
    ...overrides,
  };
}

test("n'importe qui peut lire un article de catalogue actif", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("giftCatalogItems")
      .doc("item1")
      .set(validGiftItemSeed());
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("giftCatalogItems").doc("item1").get()
  );
});

test("un acheteur ne peut pas lire un article de catalogue inactif d'un vendeur", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("giftCatalogItems")
      .doc("item1")
      .set(validGiftItemSeed({ isActive: false }));
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(buyer.collection("giftCatalogItems").doc("item1").get());
});

test("un vendeur peut créer un article dans son propre catalogue", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(
    seller
      .collection("giftCatalogItems")
      .doc("item1")
      .set(validGiftItemSeed())
  );
});

test("un vendeur ne peut pas créer un article pour un autre vendeur", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller
      .collection("giftCatalogItems")
      .doc("item1")
      .set(validGiftItemSeed({ sellerId: "seller2" }))
  );
});

test("un vendeur ne peut pas modifier le catalogue d'un autre vendeur", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("giftCatalogItems")
      .doc("item1")
      .set(validGiftItemSeed());
  });
  const outsider = testEnv.authenticatedContext("seller2").firestore();
  await assertFails(
    outsider
      .collection("giftCatalogItems")
      .doc("item1")
      .update({ pointsCost: 1 })
  );
});

test("un client ne peut jamais créer une demande d'échange directement", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("giftRedemptions").doc("r1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      itemId: "item1",
      itemTitle: "Casquette",
      pointsCost: 100,
      status: "pending",
    })
  );
});

test("un client ne peut jamais modifier une demande d'échange directement", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("giftRedemptions").doc("r1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      itemId: "item1",
      itemTitle: "Casquette",
      pointsCost: 100,
      status: "pending",
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller
      .collection("giftRedemptions")
      .doc("r1")
      .update({ status: "fulfilled" })
  );
});

test("l'acheteur et le vendeur concernés peuvent lire une demande d'échange", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("giftRedemptions").doc("r1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      itemId: "item1",
      itemTitle: "Casquette",
      pointsCost: 100,
      status: "pending",
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(buyer.collection("giftRedemptions").doc("r1").get());
  await assertSucceeds(seller.collection("giftRedemptions").doc("r1").get());
});

test("un tiers ne peut pas lire une demande d'échange qui ne le concerne pas", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("giftRedemptions").doc("r1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      itemId: "item1",
      itemTitle: "Casquette",
      pointsCost: 100,
      status: "pending",
    });
  });
  const outsider = testEnv.authenticatedContext("buyer2").firestore();
  await assertFails(outsider.collection("giftRedemptions").doc("r1").get());
});

test("le journal d'audit des points est réservé aux admins", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("loyaltyPointsAuditLog").doc("log1").set({
      targetBuyerId: "buyer1",
      sellerId: "seller1",
      previousBalance: 40,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("loyaltyPointsAuditLog").doc("log1").get()
  );
});

test("un admin peut lire le journal d'audit des points", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("loyaltyPointsAuditLog").doc("log1").set({
      targetBuyerId: "buyer1",
      sellerId: "seller1",
      previousBalance: 40,
    });
    await ctx.firestore().collection("admins").doc("admin1").set({});
  });
  const admin = testEnv.authenticatedContext("admin1").firestore();
  await assertSucceeds(
    admin.collection("loyaltyPointsAuditLog").doc("log1").get()
  );
});

test("un client ne peut pas écrire dans le journal d'audit des points", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("loyaltyPointsAuditLog").doc("log1").set({
      targetBuyerId: "buyer1",
    })
  );
});

test("le marqueur d'idempotence du crédit de points est fermé à tout client (lecture et écriture)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("loyaltyPointsLedger").doc("order1_seller1").set({
      orderId: "order1",
      sellerId: "seller1",
      buyerId: "buyer1",
      points: 10,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("loyaltyPointsLedger").doc("order1_seller1").get()
  );
  await assertFails(
    buyer.collection("loyaltyPointsLedger").doc("order2_seller1").set({
      orderId: "order2",
    })
  );
});

test("un client ne peut plus du tout modifier likesCount d'un statut (passe par la Cloud Function toggleStatusLike)", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("statuses").doc("status1").set({
      sellerId: "seller1",
      sellerName: "Vendeur test",
      mediaUrl: "https://example.com/photo.jpg",
      type: "image",
      status: "published",
      active: true,
      likesCount: 0,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("statuses").doc("status1").update({ likesCount: 1 })
  );
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller.collection("statuses").doc("status1").update({ likesCount: 1 })
  );
});

test("le propriétaire peut toujours modifier les autres champs de son propre statut", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("statuses").doc("status1").set({
      sellerId: "seller1",
      sellerName: "Vendeur test",
      mediaUrl: "https://example.com/photo.jpg",
      type: "image",
      status: "published",
      active: true,
      likesCount: 0,
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(
    seller.collection("statuses").doc("status1").update({ caption: "Nouveau" })
  );
});

test("un statut ne peut plus être supprimé directement par le client, même par son propriétaire (passe par la Cloud Function deleteStatus)", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("statuses").doc("status1").set({
      sellerId: "seller1",
      sellerName: "Vendeur test",
      mediaUrl: "https://example.com/photo.jpg",
      type: "image",
      status: "published",
      active: true,
      likesCount: 0,
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(seller.collection("statuses").doc("status1").delete());
});

test("un utilisateur peut lire son propre statusLikes, pas celui d'un autre, et ne peut jamais y écrire", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("statusLikes").doc("status1_buyer1").set({
      statusId: "status1",
      userId: "buyer1",
    });
  });
  const buyer1 = testEnv.authenticatedContext("buyer1").firestore();
  const buyer2 = testEnv.authenticatedContext("buyer2").firestore();
  await assertSucceeds(
    buyer1.collection("statusLikes").doc("status1_buyer1").get()
  );
  await assertFails(
    buyer2.collection("statusLikes").doc("status1_buyer1").get()
  );
  await assertFails(
    buyer1.collection("statusLikes").doc("status1_buyer2").set({
      statusId: "status1",
      userId: "buyer1",
    })
  );
});
