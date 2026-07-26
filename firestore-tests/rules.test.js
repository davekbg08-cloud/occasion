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

test("un acheteur peut remettre à zéro son propre compteur non-lu", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 3,
      sellerUnreadCount: 2,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
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
