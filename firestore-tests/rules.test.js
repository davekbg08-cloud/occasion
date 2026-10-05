const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { serverTimestamp } = require("firebase/firestore");
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

test("un client peut renseigner un code de parrainage saisi à l'inscription", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("users").doc("buyer1").set({
      id: "buyer1",
      role: "buyer",
      referredByCode: "ABC123",
    })
  );
});

test("un client ne peut pas s'attribuer directement un parrain (referredBy) à la création", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").set({
      id: "buyer1",
      role: "buyer",
      referredBy: "parrain1",
    })
  );
});

test("un client ne peut pas s'attribuer son propre code de parrainage à la création", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").set({
      id: "buyer1",
      role: "buyer",
      referralCode: "TRICHE1",
    })
  );
});

test("un client ne peut jamais s'auto-créditer de points de récompense parrainage", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer", referralRewardPoints: 0 });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("users")
      .doc("buyer1")
      .update({ referralRewardPoints: 9999, referralRewardGranted: true })
  );
});

test("un client ne peut pas gonfler son propre referralCount", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer", referralCount: 0 });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("users").doc("buyer1").update({ referralCount: 50 })
  );
});

test("un client peut toujours lire son propre solde de récompense parrainage", async () => {
  await seed("buyer1", {
    id: "buyer1",
    role: "buyer",
    referralCode: "XYZ789",
    referralRewardPoints: 5,
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(buyer.collection("users").doc("buyer1").get());
});

test("un client ne peut pas passer une commande à 'paid' directement", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("orders").doc("order1").set({
      buyerId: "buyer1",
      status: "pending_payment",
      items: [{ productId: "annonce1", quantity: 1, unitPrice: 1000, totalPrice: 1000 }],
      sellerIds: ["seller1"],
      total: 1000,
      currency: "FC",
    })
  );
  await assertFails(
    buyer.collection("orders").doc("order1").update({ status: "paid" })
  );
});

test("un acheteur peut annuler une commande tant qu'elle n'a pas encore été payée", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("orders").doc("order-cancel-early").set({
      buyerId: "buyer1",
      status: "pending_payment",
    });
  });
  await assertSucceeds(
    buyer.collection("orders").doc("order-cancel-early").update({ status: "cancelled" })
  );
});

test("régression : un acheteur ne peut plus annuler une commande déjà payée (il garderait l'article ET l'argent)", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("orders").doc("order-cancel-paid").set({
      buyerId: "buyer1",
      status: "paid",
    });
  });
  await assertFails(
    buyer.collection("orders").doc("order-cancel-paid").update({ status: "cancelled" })
  );
});

test("régression : un acheteur ne peut plus annuler une commande déjà complétée (contourne le reversement au vendeur)", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("orders").doc("order-cancel-completed").set({
      buyerId: "buyer1",
      status: "completed",
    });
  });
  await assertFails(
    buyer.collection("orders").doc("order-cancel-completed").update({ status: "cancelled" })
  );
});

test("régression : un acheteur ne peut plus renvoyer une commande en litige vers 'cancelled' lui-même (contourne la résolution admin)", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("orders").doc("order-cancel-disputed").set({
      buyerId: "buyer1",
      status: "disputed",
    });
  });
  await assertFails(
    buyer.collection("orders").doc("order-cancel-disputed").update({ status: "cancelled" })
  );
});

test("création de commande : refuse un schéma incomplet (items/sellerIds/total manquants)", async () => {
  const buyer = testEnv.authenticatedContext("buyer2").firestore();
  await assertFails(
    buyer.collection("orders").doc("order-incomplete").set({
      buyerId: "buyer2",
      status: "pending_payment",
    })
  );
});

test("création de commande : refuse un panier surdimensionné (plus de 50 articles)", async () => {
  const buyer = testEnv.authenticatedContext("buyer2").firestore();
  const items = Array.from({ length: 51 }, (_, i) => ({
    productId: `annonce${i}`,
    quantity: 1,
    unitPrice: 100,
    totalPrice: 100,
  }));
  await assertFails(
    buyer.collection("orders").doc("order-too-big").set({
      buyerId: "buyer2",
      status: "pending_payment",
      items,
      sellerIds: ["seller1"],
      total: 5100,
      currency: "FC",
    })
  );
});

test("création de commande : accepte un schéma bien formé", async () => {
  const buyer = testEnv.authenticatedContext("buyer2").firestore();
  await assertSucceeds(
    buyer.collection("orders").doc("order-valid").set({
      buyerId: "buyer2",
      buyerName: "Acheteur Test",
      buyerPhone: "+243900000000",
      status: "pending_payment",
      items: [{ productId: "annonce1", quantity: 2, unitPrice: 500, totalPrice: 1000 }],
      sellerIds: ["seller1"],
      total: 1000,
      currency: "FC",
    })
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

test("un participant ne peut pas modifier hiddenFor directement (passe par deleteChatForMe) — jamais masquer la conversation pour L'AUTRE", async () => {
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
    buyer.collection("chats").doc("chat1").update({ hiddenFor: ["seller1"] })
  );
});

test("un participant peut toujours modifier une métadonnée libre (listingTitle) tant que hiddenFor reste inchangé", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 0,
      sellerUnreadCount: 0,
      hiddenFor: ["buyer1"],
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("chats").doc("chat1").update({ listingTitle: "Nouveau titre" })
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

test("un participant ne peut plus modifier lastMessage/lastMessageAt/lastSenderId (passe par sendChatMessage)", async () => {
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
  await assertFails(
    buyer
      .collection("chats")
      .doc("chat1")
      .update({ lastMessage: "Bonjour", lastMessageAt: Date.now(), lastSenderId: "buyer1" })
  );
});

test("un participant ne peut plus supprimer directement un chat (passe par la Cloud Function deleteChat)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 0,
      sellerUnreadCount: 0,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(buyer.collection("chats").doc("chat1").delete());
});

test("un acheteur peut créer un chat valide (participants cohérents, compteurs à 0)", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer
      .collection("chats")
      .doc("chat-valid")
      .set({
        buyerId: "buyer1",
        sellerId: "seller1",
        buyerName: "Acheteur",
        sellerName: "Vendeur",
        participants: ["buyer1", "seller1"],
        buyerUnreadCount: 0,
        sellerUnreadCount: 0,
      })
  );
});

test("un chat avec le même acheteur et vendeur est refusé", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("chats")
      .doc("chat-same")
      .set({
        buyerId: "buyer1",
        sellerId: "buyer1",
        participants: ["buyer1"],
        buyerUnreadCount: 0,
        sellerUnreadCount: 0,
      })
  );
});

test("un chat avec un participant vide est refusé", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("chats")
      .doc("chat-empty-participant")
      .set({
        buyerId: "buyer1",
        sellerId: "",
        participants: ["buyer1", ""],
        buyerUnreadCount: 0,
        sellerUnreadCount: 0,
      })
  );
});

test("un chat avec une liste participants incohérente (ne correspond pas à buyerId/sellerId) est refusé", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("chats")
      .doc("chat-bad-participants")
      .set({
        buyerId: "buyer1",
        sellerId: "seller1",
        participants: ["buyer1", "quelqu-un-d-autre"],
        buyerUnreadCount: 0,
        sellerUnreadCount: 0,
      })
  );
});

test("un chat avec un compteur initial non nul est refusé", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("chats")
      .doc("chat-nonzero-counter")
      .set({
        buyerId: "buyer1",
        sellerId: "seller1",
        participants: ["buyer1", "seller1"],
        buyerUnreadCount: 5,
        sellerUnreadCount: 0,
      })
  );
});

test("un tiers non participant ne peut pas créer un chat entre deux autres utilisateurs", async () => {
  const outsider = testEnv.authenticatedContext("outsider1").firestore();
  await assertFails(
    outsider
      .collection("chats")
      .doc("chat-outsider")
      .set({
        buyerId: "buyer1",
        sellerId: "seller1",
        participants: ["buyer1", "seller1"],
        buyerUnreadCount: 0,
        sellerUnreadCount: 0,
      })
  );
});

test("buyerId/sellerId sont immuables après création d'un chat", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      participants: ["buyer1", "seller1"],
      buyerUnreadCount: 0,
      sellerUnreadCount: 0,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("chats").doc("chat1").update({ sellerId: "seller2" })
  );
  await assertFails(
    buyer.collection("chats").doc("chat1").update({ buyerId: "buyer2" })
  );
});

test("participants ne peut pas être modifié vers une valeur incohérente", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      participants: ["buyer1", "seller1"],
      buyerUnreadCount: 0,
      sellerUnreadCount: 0,
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("chats")
      .doc("chat1")
      .update({ participants: ["buyer1", "quelqu-un-d-autre"] })
  );
});

test("un très ancien chat sans champ participants peut se le voir corriger à la bonne valeur (backfill), jamais à une valeur fausse", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat-legacy").set({
      buyerId: "buyer1",
      sellerId: "seller1",
      buyerUnreadCount: 0,
      sellerUnreadCount: 0,
      // Pas de champ `participants` du tout — simulate un chat créé avant
      // l'existence de ce champ.
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer
      .collection("chats")
      .doc("chat-legacy")
      .update({ participants: ["buyer1", "seller1"] })
  );
});

test("un acheteur ne peut plus créer directement un message (passe par sendChatMessage)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
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

test("un vendeur ne peut plus créer directement un message (passe par sendChatMessage)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("chats").doc("chat1").set({
      buyerId: "buyer1",
      sellerId: "seller1",
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
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

test("aucun participant ne peut modifier deletedFor/deletedForEveryone sur un message (passe par deleteChatMessage)", async () => {
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
      .update({ deletedFor: ["seller1"] })
  );
  await assertFails(
    buyer
      .collection("chats")
      .doc("chat1")
      .collection("messages")
      .doc("m1")
      .update({ content: "", deletedForEveryone: true })
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

test("régression : un utilisateur non connecté ne peut plus lire une annonce publiée (numéro de téléphone du vendeur exposé sans authentification)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed({ phone: "+243900000000" }));
  });
  const anonymous = testEnv.unauthenticatedContext().firestore();
  await assertFails(anonymous.collection("annonces").doc("annonce1").get());
});

test("un utilisateur connecté peut toujours lire une annonce publiée", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(buyer.collection("annonces").doc("annonce1").get());
});

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

test("régression : le vendeur propriétaire ne peut plus non plus gonfler vues/favoris/favoritesCount sur sa propre annonce", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller.collection("annonces").doc("annonce1").update({ vues: 999999 })
  );
  await assertFails(
    seller.collection("annonces").doc("annonce1").update({ favoris: 999999 })
  );
  await assertFails(
    seller.collection("annonces").doc("annonce1").update({ favoritesCount: 999999 })
  );
  // Le reste de l'annonce (titre, prix, ...) reste bien modifiable par son
  // propriétaire — seuls les compteurs de popularité sont gelés.
  await assertSucceeds(
    seller.collection("annonces").doc("annonce1").update({ title: "Titre modifié" })
  );
});

test("régression : un utilisateur ne peut plus écrire `favoris` à une valeur arbitraire sur une annonce d'un autre vendeur (aucun code client ne l'écrit réellement — la règle l'autorisait à tort)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("annonces").doc("annonce1").update({ favoris: 999999 })
  );
});

test("régression : ajouter une annonce aux favoris (forme exacte écrite par favoris_provider.dart) réussit désormais", async () => {
  // Reproduit EXACTEMENT la forme du document envoyé par
  // FavorisNotifier.toggleFavori après correction — avant ce correctif,
  // un cinquième champ ('createdAt', en plus de 'dateAjout') faisait
  // échouer cet appel en silence (hasOnly() dans validFavori() refuse
  // toute clé hors ['id', 'utilisateurId', 'annonceId', 'dateAjout']),
  // sans qu'aucune erreur ne remonte jamais à l'écran : le cœur
  // "favoris" ne faisait donc jamais rien.
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("favoris").doc("fav1").set({
      id: "fav1",
      utilisateurId: "buyer1",
      annonceId: "annonce1",
      dateAjout: new Date(),
    })
  );
});

test("régression : la forme AVANT correctif (champ `createdAt` en trop) est bien refusée — preuve du bug", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("favoris").doc("fav1").set({
      id: "fav1",
      utilisateurId: "buyer1",
      annonceId: "annonce1",
      dateAjout: new Date(),
      createdAt: new Date(),
    })
  );
});

test("favoris : impossible de créer un favori au nom d'un autre utilisateur", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("favoris").doc("fav1").set({
      id: "fav1",
      utilisateurId: "buyer2",
      annonceId: "annonce1",
      dateAjout: new Date(),
    })
  );
});

test("régression : `messagesCount` ne peut être incrémenté que de +1 exactement par un non-propriétaire (jamais une valeur arbitraire)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed({ messagesCount: 3 }));
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("annonces").doc("annonce1").update({ messagesCount: 4 })
  );
  await assertFails(
    buyer.collection("annonces").doc("annonce1").update({ messagesCount: 999 })
  );
  await assertFails(
    buyer.collection("annonces").doc("annonce1").update({ messagesCount: 3 })
  );
});

test("le vendeur peut mettre à jour le saleState de sa propre annonce", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(
    seller
      .collection("annonces")
      .doc("annonce1")
      .set(
        validAnnonceSeed({ saleState: "sold", etatVente: "sold" }),
        { merge: true }
      )
  );
});

test("un acheteur ne peut pas modifier le saleState de l'annonce d'un autre", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer
      .collection("annonces")
      .doc("annonce1")
      .update({ saleState: "sold", etatVente: "sold" })
  );
});

test("l'historique de prix d'une annonce est lisible par tout utilisateur connecté, jamais sans connexion (comme l'annonce elle-même)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .collection("priceHistory")
      .doc("entry1")
      .set({ oldPrice: 1000, newPrice: 800, currency: "FC" });
  });
  const entry = (db) =>
    db.collection("annonces").doc("annonce1").collection("priceHistory").doc("entry1");
  await assertSucceeds(
    entry(testEnv.authenticatedContext("buyer1").firestore()).get()
  );
  await assertFails(entry(testEnv.unauthenticatedContext().firestore()).get());
});

test("un client ne peut jamais écrire dans l'historique de prix d'une annonce", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("annonces")
      .doc("annonce1")
      .set(validAnnonceSeed());
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller
      .collection("annonces")
      .doc("annonce1")
      .collection("priceHistory")
      .doc("entry1")
      .set({ oldPrice: 1000, newPrice: 800, currency: "FC" })
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

test("régression : un statut n'est plus modifiable du tout par le client, même par son propriétaire (sellerId/createdAt/légende usurpables)", async () => {
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
  await assertFails(
    seller.collection("statuses").doc("status1").update({ caption: "Nouveau" })
  );
  await assertFails(
    seller.collection("statuses").doc("status1").update({ sellerId: "seller2" })
  );
  await assertFails(
    seller.collection("statuses").doc("status1").update({ createdAt: 9999999999999 })
  );
});

test("régression : un statut photo ne peut pas être transformé en vidéo après coup (contournement du quota vidéo quotidien)", async () => {
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
  await assertFails(
    seller.collection("statuses").doc("status1").update({ type: "video" })
  );
  await assertFails(
    seller
      .collection("statuses")
      .doc("status1")
      .update({ mediaUrl: "https://example.com/video.mp4" })
  );
});

test("statusDailyCounters : lisible uniquement par le vendeur concerné, jamais modifiable par un client", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("statusDailyCounters").doc("seller1_2026-09-27").set({
      sellerId: "seller1",
      videoStatusIds: ["v1"],
    });
  });
  const seller1 = testEnv.authenticatedContext("seller1").firestore();
  const seller2 = testEnv.authenticatedContext("seller2").firestore();
  await assertSucceeds(
    seller1.collection("statusDailyCounters").doc("seller1_2026-09-27").get()
  );
  await assertFails(
    seller2.collection("statusDailyCounters").doc("seller1_2026-09-27").get()
  );
  await assertFails(
    seller1
      .collection("statusDailyCounters")
      .doc("seller1_2026-09-27")
      .set({ sellerId: "seller1", videoStatusIds: [] })
  );
});

test("playPurchases : lisible uniquement par l'utilisateur concerné, jamais modifiable par un client", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("playPurchases").doc("token1").set({
      userId: "seller1",
      productId: "seller_monthly",
    });
  });
  const seller1 = testEnv.authenticatedContext("seller1").firestore();
  const seller2 = testEnv.authenticatedContext("seller2").firestore();
  await assertSucceeds(seller1.collection("playPurchases").doc("token1").get());
  await assertFails(seller2.collection("playPurchases").doc("token1").get());
  await assertFails(
    seller1
      .collection("playPurchases")
      .doc("token1")
      .set({ userId: "seller1", productId: "seller_monthly" })
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

test("statusViews : chacun peut marquer et lire ses propres statuts vus, jamais ceux d'un autre ni au nom d'un autre", async () => {
  const buyer1 = testEnv.authenticatedContext("buyer1").firestore();
  const buyer2 = testEnv.authenticatedContext("buyer2").firestore();

  await assertSucceeds(
    buyer1.collection("statusViews").doc("status1_buyer1").set({
      statusId: "status1",
      userId: "buyer1",
    })
  );
  await assertFails(
    buyer1.collection("statusViews").doc("status1_buyer2").set({
      statusId: "status1",
      userId: "buyer1",
    })
  );
  await assertSucceeds(
    buyer1.collection("statusViews").doc("status1_buyer1").get()
  );
  await assertFails(
    buyer2.collection("statusViews").doc("status1_buyer1").get()
  );
  await assertFails(
    buyer1.collection("statusViews").doc("status1_buyer1").update({
      statusId: "status2",
    })
  );
});

test("payoutAccounts : le vendeur gère son propre numéro de reversement, jamais celui d'un autre", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("admins").doc("admin1").set({});
  });
  const seller1 = testEnv.authenticatedContext("seller1").firestore();
  const seller2 = testEnv.authenticatedContext("seller2").firestore();
  const admin1 = testEnv.authenticatedContext("admin1").firestore();

  await assertSucceeds(
    seller1.collection("payoutAccounts").doc("seller1").set({
      provider: "AIRTEL_COD",
      phoneNumber: "0991234567",
      holderName: "Vendeur Un",
      updatedAt: new Date(),
    })
  );
  // Un fournisseur en dehors de la liste blanche ne doit jamais passer —
  // sans ça un client pourrait enregistrer un provider inventé que le
  // serveur pawaPay rejetterait silencieusement au moment du reversement.
  await assertFails(
    seller1.collection("payoutAccounts").doc("seller1").set({
      provider: "BITCOIN",
      phoneNumber: "0991234567",
      holderName: "Vendeur Un",
      updatedAt: new Date(),
    })
  );
  // Champ non prévu (ex. un solde ou un statut que le serveur seul doit
  // gérer) : refusé même s'il accompagne des champs par ailleurs valides.
  await assertFails(
    seller1.collection("payoutAccounts").doc("seller1").set({
      provider: "AIRTEL_COD",
      phoneNumber: "0991234567",
      holderName: "Vendeur Un",
      updatedAt: new Date(),
      balance: 999999,
    })
  );
  await assertFails(
    seller2.collection("payoutAccounts").doc("seller1").set({
      provider: "AIRTEL_COD",
      phoneNumber: "0999999999",
      holderName: "Usurpateur",
      updatedAt: new Date(),
    })
  );
  await assertSucceeds(
    seller1.collection("payoutAccounts").doc("seller1").get()
  );
  await assertFails(seller2.collection("payoutAccounts").doc("seller1").get());
  await assertSucceeds(
    admin1.collection("payoutAccounts").doc("seller1").get()
  );
});

test("pawapayPayouts : entièrement fermé côté client, y compris pour un administrateur (exclusivement serveur)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("pawapayPayouts").doc("payout1").set({
      orderId: "order1",
      sellerId: "seller1",
      amount: 9600,
      status: "ACCEPTED",
    });
    await ctx.firestore().collection("admins").doc("admin2").set({});
  });
  const admin2 = testEnv.authenticatedContext("admin2").firestore();
  const seller1 = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(admin2.collection("pawapayPayouts").doc("payout1").get());
  await assertFails(seller1.collection("pawapayPayouts").doc("payout1").get());
  await assertFails(
    admin2.collection("pawapayPayouts").doc("payout1").update({ status: "COMPLETED" })
  );
});

test("reviews : illisible et inéditable directement par un client, même le propriétaire de l'avis", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("reviews").doc("order1_seller1_buyer_to_seller").set({
      orderId: "order1",
      sellerId: "seller1",
      reviewerId: "buyer1",
      revieweeId: "seller1",
      direction: "buyer_to_seller",
      rating: 5,
      comment: "",
    });
  });
  const outsider = testEnv.authenticatedContext("outsider1").firestore();
  await assertSucceeds(
    outsider.collection("reviews").doc("order1_seller1_buyer_to_seller").get()
  );

  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("reviews").doc("order2_seller1_buyer_to_seller").set({
      orderId: "order2",
      sellerId: "seller1",
      reviewerId: "buyer1",
      revieweeId: "seller1",
      direction: "buyer_to_seller",
      rating: 5,
      comment: "",
    })
  );
  await assertFails(
    buyer
      .collection("reviews")
      .doc("order1_seller1_buyer_to_seller")
      .update({ rating: 1 })
  );
});

test("un utilisateur non connecté ne peut jamais lire les avis", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("reviews").doc("order1_seller1_buyer_to_seller").set({
      orderId: "order1",
      sellerId: "seller1",
      reviewerId: "buyer1",
      revieweeId: "seller1",
      direction: "buyer_to_seller",
      rating: 5,
      comment: "",
    });
  });
  const anonymous = testEnv.unauthenticatedContext().firestore();
  await assertFails(
    anonymous.collection("reviews").doc("order1_seller1_buyer_to_seller").get()
  );
});

test("publicProfiles : le propriétaire ne peut jamais s'attribuer lui-même une note ou un nombre de ventes", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("publicProfiles").doc("seller1").set({
      id: "seller1",
      name: "Vendeur",
      role: "seller",
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();

  await assertFails(
    seller.collection("publicProfiles").doc("seller1").update({ ratingSum: 999 })
  );
  await assertFails(
    seller.collection("publicProfiles").doc("seller1").update({ ratingCount: 999 })
  );
  await assertFails(
    seller.collection("publicProfiles").doc("seller1").update({ averageRating: 5 })
  );
  await assertFails(
    seller.collection("publicProfiles").doc("seller1").update({ totalSales: 999 })
  );

  // Une mise à jour légitime (champs autorisés) doit toujours fonctionner :
  // la fraude est bloquée précisément par l'absence de ces 4 champs dans le
  // hasOnly, pas par un verrou global sur le document.
  await assertSucceeds(
    seller.collection("publicProfiles").doc("seller1").update({ name: "Nouveau nom" })
  );
});

test("régression : publicProfiles.identityStatus/sellerStatus ne peuvent jamais être auto-attribués à 'verified' (faux badge Vendeur vérifié)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("publicProfiles").doc("seller1").set({
      id: "seller1",
      name: "Vendeur",
      role: "seller",
      identityStatus: "unverified",
      sellerStatus: "unverified",
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();

  await assertFails(
    seller.collection("publicProfiles").doc("seller1").update({ identityStatus: "verified" })
  );
  await assertFails(
    seller.collection("publicProfiles").doc("seller1").update({ sellerStatus: "verified" })
  );
  await assertFails(
    seller.collection("publicProfiles").doc("seller1").update({ identityStatus: "rejected" })
  );

  // Les valeurs de "soumission" (jamais 'verified') restent permises.
  await assertSucceeds(
    seller.collection("publicProfiles").doc("seller1").update({ identityStatus: "identity_submitted" })
  );
});

test("régression : publicProfiles.phoneVerified ne peut jamais être auto-attribué à true (faux badge Téléphone vérifié, aucun flux SMS/OTP n'existe)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("publicProfiles").doc("seller1").set({
      id: "seller1",
      name: "Vendeur",
      role: "seller",
      phoneVerified: false,
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();

  await assertFails(
    seller.collection("publicProfiles").doc("seller1").update({ phoneVerified: true })
  );
  // false reste permis (c'est la valeur écrite à l'inscription).
  await assertSucceeds(
    seller.collection("publicProfiles").doc("seller1").update({ phoneVerified: false })
  );
});

test("régression : enregistrer une recherche (forme exacte écrite par SearchAlertService.create) réussit, avec mot-clé seul, ville seule, ou les deux", async () => {
  // Reproduit exactement {...alert.toJson(), 'createdAt': ...} pour les
  // trois combinaisons réellement atteignables depuis l'écran Rechercher
  // (le bouton signet est désactivé tant qu'aucun des deux n'est
  // renseigné, donc "les deux vides" n'est jamais envoyé par l'app).
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("searchAlerts").doc("kw-only").set({
      id: "kw-only",
      userId: "buyer1",
      keyword: "iphone",
      createdAt: new Date(),
    })
  );
  await assertSucceeds(
    buyer.collection("searchAlerts").doc("city-only").set({
      id: "city-only",
      userId: "buyer1",
      city: "Kinshasa",
      createdAt: new Date(),
    })
  );
  await assertSucceeds(
    buyer.collection("searchAlerts").doc("both").set({
      id: "both",
      userId: "buyer1",
      keyword: "iphone",
      city: "Kinshasa",
      category: "Électronique",
      createdAt: new Date(),
    })
  );
});

test("searchAlerts : un utilisateur peut créer, lire et supprimer sa propre alerte", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertSucceeds(
    buyer.collection("searchAlerts").doc("alert1").set({
      userId: "buyer1",
      keyword: "iphone",
      createdAt: new Date(),
    })
  );
  await assertSucceeds(buyer.collection("searchAlerts").doc("alert1").get());
  await assertSucceeds(buyer.collection("searchAlerts").doc("alert1").delete());
});

test("searchAlerts : un utilisateur ne peut ni lire ni supprimer l'alerte d'un autre", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("searchAlerts").doc("alert1").set({
      userId: "buyer1",
      keyword: "iphone",
      createdAt: new Date(),
    });
  });
  const outsider = testEnv.authenticatedContext("buyer2").firestore();
  await assertFails(outsider.collection("searchAlerts").doc("alert1").get());
  await assertFails(outsider.collection("searchAlerts").doc("alert1").delete());
});

test("searchAlerts : un utilisateur ne peut pas créer une alerte au nom d'un autre", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("searchAlerts").doc("alert1").set({
      userId: "buyer2",
      keyword: "iphone",
      createdAt: new Date(),
    })
  );
});

test("searchAlerts : une alerte ne peut jamais être modifiée, uniquement supprimée puis recréée", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("searchAlerts").doc("alert1").set({
      userId: "buyer1",
      keyword: "iphone",
      createdAt: new Date(),
    });
  });
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("searchAlerts").doc("alert1").update({ keyword: "samsung" })
  );
});

test("régression : la collection héritée /messages (remplacée par chats/{id}/messages) est entièrement verrouillée", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("messages").doc("legacy1").set({
      expediteurId: "buyer1",
      destinataireId: "buyer2",
      contenu: "spam",
    })
  );
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("messages").doc("legacy1").set({
      expediteurId: "buyer1",
      destinataireId: "buyer2",
      contenu: "ancien message",
    });
  });
  await assertFails(buyer.collection("messages").doc("legacy1").get());
  await assertFails(
    buyer.collection("messages").doc("legacy1").update({ contenu: "falsifié" })
  );
});

test("régression : la collection morte /products (jamais utilisée, remplacée par annonces) est entièrement verrouillée", async () => {
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(
    seller.collection("products").doc("p1").set({ sellerId: "seller1", status: "active" })
  );
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("products").doc("p1").set({
      sellerId: "seller1",
      status: "active",
    });
  });
  await assertFails(seller.collection("products").doc("p1").get());
});

test("régression : la collection héritée /conversations (et sa sous-collection messages) est entièrement verrouillée", async () => {
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("conversations").doc("legacy-conv1").set({
      participants: ["buyer1", "buyer2"],
    })
  );
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("conversations").doc("legacy-conv1").set({
      participants: ["buyer1", "buyer2"],
    });
    await ctx
      .firestore()
      .collection("conversations")
      .doc("legacy-conv1")
      .collection("messages")
      .doc("legacy-m1")
      .set({ expediteurId: "buyer1", destinataireId: "buyer2", contenu: "ancien" });
  });
  await assertFails(buyer.collection("conversations").doc("legacy-conv1").get());
  await assertFails(
    buyer
      .collection("conversations")
      .doc("legacy-conv1")
      .collection("messages")
      .doc("legacy-m1")
      .get()
  );
});

// ---------------------------------------------------------------------------
// Abonnement vendeur imposé côté serveur (statuts, photos d'annonces)
// ---------------------------------------------------------------------------

// Comme applySettlement/confirmPlayPurchase : `subscriptions/{uid}` ET sa
// copie sur `users/{uid}`.
async function seedSubscription(uid, { isActive = true, daysLeft = 30 } = {}) {
  const expiryDate = new Date(Date.now() + daysLeft * 24 * 60 * 60 * 1000);
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("subscriptions").doc(uid).set({ userId: uid, isActive, expiryDate });
    await db.collection("users").doc(uid).set(
      { sellerSubscriptionActive: isActive, sellerSubscriptionExpiresAt: expiryDate },
      { merge: true }
    );
  });
}

function newStatus(overrides) {
  return {
    id: "s1",
    sellerId: "seller1",
    sellerName: "Vendeur test",
    sellerProfileImageUrl: null,
    mediaUrl: "https://example.com/photo.jpg",
    type: "image",
    caption: null,
    productId: null,
    likesCount: 0,
    status: "published",
    active: true,
    createdAt: Date.now(),
    ...overrides,
  };
}

test("statut : refusé sans abonnement vendeur actif, même pour un vendeur", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(seller.collection("statuses").doc("s1").set(newStatus()));
});

test("statut : refusé avec un abonnement expiré ou désactivé", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await seedSubscription("seller1", { daysLeft: -1 });
  await assertFails(seller.collection("statuses").doc("s1").set(newStatus()));
  await seedSubscription("seller1", { isActive: false });
  await assertFails(seller.collection("statuses").doc("s1").set(newStatus()));
});

test("statut : accepté pour un vendeur abonné, au format exact de l'app", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await seedSubscription("seller1");
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(seller.collection("statuses").doc("s1").set(newStatus()));
});

test("statut : un vendeur abonné ne peut ni gonfler likesCount, ni ajouter un champ inconnu, ni publier pour un autre", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await seedSubscription("seller1");
  const seller = testEnv.authenticatedContext("seller1").firestore();
  const statuses = seller.collection("statuses");
  await assertFails(statuses.doc("a").set(newStatus({ likesCount: 500 })));
  await assertFails(statuses.doc("b").set(newStatus({ verified: true })));
  await assertFails(statuses.doc("c").set(newStatus({ sellerId: "seller2" })));
  await assertFails(statuses.doc("d").set(newStatus({ type: "gif" })));
  await assertFails(statuses.doc("e").set(newStatus({ mediaUrl: "javascript:alert(1)" })));
});

test("statut : un acheteur abonné (rôle buyer) ne peut pas publier", async () => {
  await seed("buyer1", { id: "buyer1", role: "buyer" });
  await seedSubscription("buyer1");
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(
    buyer.collection("statuses").doc("s1").set(newStatus({ sellerId: "buyer1" }))
  );
});




// ---------------------------------------------------------------------------
// Une seule définition d'admin : admins/{uid}
// ---------------------------------------------------------------------------

test("catégories : gérées par un admin (admins/{uid}), jamais par un simple claim token.admin ni par un utilisateur", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("admins").doc("admin1").set({ since: 1 });
  });
  const categorie = { nom: "Téléphones", icone: "phone", ordre: 1 };

  const admin = testEnv.authenticatedContext("admin1").firestore();
  await assertSucceeds(admin.collection("categories").doc("c1").set(categorie));
  await assertSucceeds(admin.collection("categories").doc("c1").delete());

  const claimOnly = testEnv
    .authenticatedContext("pirate", { admin: true })
    .firestore();
  await assertFails(claimOnly.collection("categories").doc("c2").set(categorie));

  const user = testEnv.authenticatedContext("user1").firestore();
  await assertFails(user.collection("categories").doc("c3").set(categorie));
});

test("admins : un utilisateur ne voit que son propre document admin et ne peut jamais s'en créer un", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("admins").doc("admin1").set({ since: 1 });
  });
  const admin = testEnv.authenticatedContext("admin1").firestore();
  const user = testEnv.authenticatedContext("user1").firestore();
  await assertSucceeds(admin.collection("admins").doc("admin1").get());
  await assertFails(user.collection("admins").doc("admin1").get());
  await assertFails(user.collection("admins").doc("user1").set({ since: 1 }));
});

// ---------------------------------------------------------------------------
// Relecture finale des règles
// ---------------------------------------------------------------------------

test("régression : un vendeur ne peut plus supprimer son profil public (remise à zéro de sa note)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("publicProfiles").doc("seller1").set({
      id: "seller1",
      name: "Vendeur",
      ratingSum: 2,
      ratingCount: 2,
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertFails(seller.collection("publicProfiles").doc("seller1").delete());
});

test("statuts et catalogue de cadeaux : jamais lisibles sans connexion", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("statuses").doc("s1").set({
      sellerId: "seller1",
      status: "published",
      active: true,
    });
    await ctx.firestore().collection("giftCatalogItems").doc("g1").set({
      sellerId: "seller1",
      isActive: true,
    });
  });
  const anonymous = testEnv.unauthenticatedContext().firestore();
  const buyer = testEnv.authenticatedContext("buyer1").firestore();
  await assertFails(anonymous.collection("statuses").doc("s1").get());
  await assertSucceeds(buyer.collection("statuses").doc("s1").get());
  await assertFails(anonymous.collection("giftCatalogItems").doc("g1").get());
  await assertSucceeds(buyer.collection("giftCatalogItems").doc("g1").get());
});

function report(overrides) {
  return {
    reporterId: "user1",
    targetId: "annonce1",
    targetType: "product",
    reason: "scam",
    details: null,
    status: "pending",
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

test("signalement : accepté au format exact de l'app, refusé déjà « traité », avec champ inconnu ou sous un autre id", async () => {
  const user = testEnv.authenticatedContext("user1").firestore();
  const reports = user.collection("reports");
  await assertSucceeds(reports.doc("user1_product_annonce1").set(report()));
  await assertFails(
    reports.doc("user1_product_annonce2").set(report({ targetId: "annonce2", status: "resolved" }))
  );
  await assertFails(
    reports.doc("user1_product_annonce3").set(report({ targetId: "annonce3", priority: "high" }))
  );
  await assertFails(reports.doc("n-importe-quoi").set(report({ targetId: "annonce4" })));
  await assertFails(
    reports.doc("user1_product_annonce5").set(report({ targetId: "annonce5", reporterId: "user2" }))
  );
});

test("collections héritées utilisateurs/signalements : entièrement verrouillées", async () => {
  const user = testEnv.authenticatedContext("user1").firestore();
  await assertFails(user.collection("utilisateurs").doc("user1").set({ nom: "x" }));
  await assertFails(user.collection("utilisateurs").doc("user1").get());
  await assertFails(
    user.collection("signalements").doc("s1").set({ utilisateurId: "user1" })
  );
});

// ---------------------------------------------------------------------------
// Régression : annonce COMPLÈTE telle qu'écrite par l'app (Annonce.toJson,
// ~36 champs). Avec un document réduit, les tests passaient alors qu'en
// production la règle dépassait la limite de 1000 expressions évaluées dès
// qu'il fallait vérifier l'abonnement (plus de 2 photos).
// ---------------------------------------------------------------------------

function appAnnonce(id, photoCount) {
  const urls = Array.from(
    { length: photoCount },
    (_, i) =>
      `https://firebasestorage.googleapis.com/v0/b/x/o/annonces%2Fseller1%2F${id}%2F${i}.jpg?alt=media&token=t`
  );
  return {
    id,
    sellerId: "seller1",
    title: "Montre",
    titre: "Montre",
    description: "Belle montre",
    price: 60,
    prix: 60,
    currency: "USD",
    devise: "USD",
    category: "Mode",
    categorie: "Mode",
    marque: "",
    modele: "",
    annee: 2024,
    etat: "Bon état",
    localisation: "Likasi",
    city: "Likasi",
    ville: "Likasi",
    district: "Likasi",
    quartier: "Likasi",
    vendeurId: "seller1",
    telephone: "+243856373707",
    imageUrls: urls,
    images: urls,
    favoris: 0,
    vues: 0,
    messagesCount: 0,
    status: "published",
    statut: "published",
    active: true,
    isPublished: true,
    saleState: "available",
    etatVente: "available",
    dateCreation: serverTimestamp(),
    dateModification: serverTimestamp(),
  };
}

test("régression : un vendeur ABONNÉ publie une annonce complète de l'app avec 2, 3 ou 5 photos", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await seedSubscription("seller1");
  const seller = testEnv.authenticatedContext("seller1").firestore();
  for (const n of [2, 3, 5]) {
    await assertSucceeds(
      seller.collection("annonces").doc(`a${n}`).set(appAnnonce(`a${n}`, n))
    );
  }
});


test("régression : un vendeur abonné peut passer une annonce complète existante de 2 à 5 photos", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  await seedSubscription("seller1");
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const data = appAnnonce("a", 2);
    data.dateCreation = new Date();
    data.dateModification = new Date();
    await ctx.firestore().collection("annonces").doc("a").set(data);
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(seller.collection("annonces").doc("a").set(appAnnonce("a", 5)));
});

test("annonce complète de l'app : les règles n'appliquent pas la limite de photos (onAnnonceCreated s'en charge) — jamais de refus par dépassement de limite", async () => {
  await seed("seller1", { id: "seller1", role: "seller" });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(seller.collection("annonces").doc("a5").set(appAnnonce("a5", 5)));
});

test("users : un admin lit l'identité d'un utilisateur (paiement manuel), un autre utilisateur jamais", async () => {
  await seed("seller1", { id: "seller1", name: "Alice", phone: "+243800000000", role: "seller" });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("admins").doc("admin1").set({ since: 1 });
  });
  const admin = testEnv.authenticatedContext("admin1").firestore();
  const other = testEnv.authenticatedContext("user2").firestore();
  await assertSucceeds(admin.collection("users").doc("seller1").get());
  await assertFails(other.collection("users").doc("seller1").get());
});

test("paiement manuel d'abonnement : numéro et titulaire du payeur acceptés, valeurs démesurées refusées", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("paymentIntents").doc("pi1").set({
      userId: "seller1",
      type: "subscription",
      status: "pending",
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  const ref = seller.collection("paymentIntents").doc("pi1");
  await assertFails(
    ref.set(
      {
        status: "awaiting_manual_verification",
        manualPaymentMethod: "orange_money_manual",
        manualPaymentReference: "MP241005.1234.A56789",
        manualPayerPhone: "9".repeat(50),
        manualPayerName: "Dave",
      },
      { merge: true }
    )
  );
  await assertSucceeds(
    ref.set(
      {
        status: "awaiting_manual_verification",
        manualPaymentMethod: "orange_money_manual",
        manualPaymentReference: "MP241005.1234.A56789",
        manualPayerPhone: "+243856373707",
        manualPayerName: "Dave K.",
      },
      { merge: true }
    )
  );
});

test("paiement manuel d'abonnement : une ancienne version de l'app (sans numéro du payeur) fonctionne toujours", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("paymentIntents").doc("pi2").set({
      userId: "seller1",
      type: "subscription",
      status: "pending",
    });
  });
  const seller = testEnv.authenticatedContext("seller1").firestore();
  await assertSucceeds(
    seller.collection("paymentIntents").doc("pi2").set(
      {
        status: "awaiting_manual_verification",
        manualPaymentMethod: "orange_money_manual",
        manualPaymentReference: "MP241005.1234.A56789",
      },
      { merge: true }
    )
  );
});
