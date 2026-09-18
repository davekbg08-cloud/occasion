// Peuple l'émulateur Firestore avec des fils dupliqués synthétiques, pour
// répéter mergeChatThreads.js avant tout run en production. À supprimer
// avec le reste du dossier une fois le chantier terminé.
const admin = require("firebase-admin");
admin.initializeApp({ projectId: "demo-occasion" });
const db = admin.firestore();

async function main() {
  // Groupe 1 : deux fils pour le même binôme buyer1/seller1 (comme
  // David/vendeur dans le scénario rapporté) — un via une annonce
  // ("buyer1_seller1_annonceA"), un général ("buyer1_seller1").
  await db.collection("chats").doc("buyer1_seller1_annonceA").set({
    buyerId: "buyer1",
    sellerId: "seller1",
    buyerName: "David",
    sellerName: "Vendeur X",
    listingId: "annonceA",
    listingTitle: "Chaise en bois",
    participants: ["buyer1", "seller1"],
    lastMessage: "Toujours dispo ?",
    lastMessageAt: 1000,
    lastSenderId: "buyer1",
    buyerUnreadCount: 0,
    sellerUnreadCount: 1,
  });
  await db
    .collection("chats")
    .doc("buyer1_seller1_annonceA")
    .collection("messages")
    .doc("msgA1")
    .set({
      senderId: "buyer1",
      receiverId: "seller1",
      content: "Bonjour, la chaise est dispo ?",
      status: "read",
      clientMessageId: "msgA1",
      sentAt: 500,
    });
  await db
    .collection("chats")
    .doc("buyer1_seller1_annonceA")
    .collection("messages")
    .doc("msgA2")
    .set({
      senderId: "buyer1",
      receiverId: "seller1",
      content: "Toujours dispo ?",
      status: "sent",
      clientMessageId: "msgA2",
      sentAt: 1000,
    });

  await db.collection("chats").doc("buyer1_seller1").set({
    buyerId: "buyer1",
    sellerId: "seller1",
    buyerName: "David",
    sellerName: "Vendeur X",
    participants: ["buyer1", "seller1"],
    lastMessage: "Merci, à bientôt",
    lastMessageAt: 3000,
    lastSenderId: "seller1",
    buyerUnreadCount: 1,
    sellerUnreadCount: 0,
  });
  await db
    .collection("chats")
    .doc("buyer1_seller1")
    .collection("messages")
    .doc("msgB1")
    .set({
      senderId: "seller1",
      receiverId: "buyer1",
      content: "Oui je vous envoie une photo",
      status: "read",
      clientMessageId: "msgB1",
      sentAt: 2000,
    });
  await db
    .collection("chats")
    .doc("buyer1_seller1")
    .collection("messages")
    .doc("msgB2")
    .set({
      senderId: "seller1",
      receiverId: "buyer1",
      content: "Merci, à bientôt",
      status: "sent",
      clientMessageId: "msgB2",
      sentAt: 3000,
    });

  // Groupe 2 : un seul fil, déjà à l'ancien format 3-segments (jamais
  // dupliqué), doit être RENOMMÉ vers l'id canonique.
  await db.collection("chats").doc("buyer2_seller2_annonceZ").set({
    buyerId: "buyer2",
    sellerId: "seller2",
    buyerName: "Alice",
    sellerName: "Vendeur Z",
    listingId: "annonceZ",
    listingTitle: "Vélo",
    participants: ["buyer2", "seller2"],
    lastMessage: "Ok merci",
    lastMessageAt: 500,
    lastSenderId: "buyer2",
    buyerUnreadCount: 0,
    sellerUnreadCount: 0,
  });
  await db
    .collection("chats")
    .doc("buyer2_seller2_annonceZ")
    .collection("messages")
    .doc("msgC1")
    .set({
      senderId: "buyer2",
      receiverId: "seller2",
      content: "Ok merci",
      status: "read",
      clientMessageId: "msgC1",
      sentAt: 500,
    });

  // Groupe 3 : déjà canonique (buyer3_seller3), ne doit RIEN déclencher.
  await db.collection("chats").doc("buyer3_seller3").set({
    buyerId: "buyer3",
    sellerId: "seller3",
    buyerName: "Bob",
    sellerName: "Vendeur W",
    participants: ["buyer3", "seller3"],
    lastMessage: "Salut",
    lastMessageAt: 100,
    lastSenderId: "buyer3",
    buyerUnreadCount: 0,
    sellerUnreadCount: 1,
  });
  await db
    .collection("chats")
    .doc("buyer3_seller3")
    .collection("messages")
    .doc("msgD1")
    .set({
      senderId: "buyer3",
      receiverId: "seller3",
      content: "Salut",
      status: "sent",
      clientMessageId: "msgD1",
      sentAt: 100,
    });

  console.log("Seed terminé : 4 documents chats créés (groupes 1, 2, 3).");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
