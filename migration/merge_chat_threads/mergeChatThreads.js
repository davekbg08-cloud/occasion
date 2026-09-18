#!/usr/bin/env node
/**
 * Migration UNIQUE : fusionne les fils de discussion `chats/{chatId}`
 * dupliqués pour un même binôme (acheteur, vendeur) — doublons créés avant
 * le correctif de `ChatService._chatId` (qui incluait `listingId` dans
 * l'identité du fil) — en un seul fil canonique `${sortedUid1}_${sortedUid2}`.
 *
 * SANS DRAPEAU (par défaut) : dry-run, n'écrit rien, affiche un rapport
 * complet par groupe.
 *
 *   --apply-merge   : écrit le document canonique et copie tous les
 *                     messages fusionnés dedans. NE SUPPRIME RIEN. Sûr à
 *                     rejouer (idempotent : un message déjà copié est
 *                     simplement réécrit à l'identique, jamais dupliqué).
 *   --apply-cleanup : en plus de ce qui précède (le merge est toujours
 *                     recalculé et réappliqué dans le même passage avant
 *                     toute suppression — jamais une suppression basée sur
 *                     un état déjà périmé), supprime les documents
 *                     dupliqués désormais redondants (et leurs messages)
 *                     UNE FOIS que ce même passage a vérifié que le total
 *                     de messages copiés correspond au total lu. Seule
 *                     étape réellement destructrice de ce script.
 *
 * Auth : Admin SDK via Application Default Credentials — fonctionne
 * directement dans le job GitHub Actions après `google-github-actions/auth@v2`
 * avec le secret GCP_SA_KEY (déjà utilisé par .github/workflows/deploy-firebase.yml),
 * qui exporte GOOGLE_APPLICATION_CREDENTIALS. Aucune étape Cloud Shell.
 *
 * Usage :
 *   node mergeChatThreads.js
 *   node mergeChatThreads.js --apply-merge
 *   node mergeChatThreads.js --apply-cleanup
 */

const admin = require("firebase-admin");

const APPLY_MERGE = process.argv.includes("--apply-merge");
const APPLY_CLEANUP = process.argv.includes("--apply-cleanup");
// Le nettoyage suppose toujours un merge frais dans le même passage — on
// n'efface jamais sur la foi d'un état lu avant ce script.
const DO_WRITE = APPLY_MERGE || APPLY_CLEANUP;

admin.initializeApp();
const db = admin.firestore();

function canonicalKey(buyerId, sellerId) {
  return [buyerId, sellerId].sort().join("_");
}

async function fetchAllChats() {
  const chats = [];
  let cursor = null;
  for (;;) {
    let q = db.collection("chats").orderBy("__name__").limit(500);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      chats.push({ id: doc.id, data: doc.data() });
    }
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < 500) break;
  }
  return chats;
}

async function fetchAllMessages(chatId) {
  const messages = [];
  let cursor = null;
  for (;;) {
    let q = db
      .collection("chats")
      .doc(chatId)
      .collection("messages")
      .orderBy("__name__")
      .limit(500);
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      messages.push({ id: doc.id, sourceChatId: chatId, data: doc.data() });
    }
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < 500) break;
  }
  return messages;
}

function sentAtMillis(message) {
  if (typeof message.sentAt === "number") return message.sentAt;
  if (message.createdAt && typeof message.createdAt.toMillis === "function") {
    return message.createdAt.toMillis();
  }
  return 0;
}

function messagesEqual(a, b) {
  return (
    a.senderId === b.senderId &&
    a.receiverId === b.receiverId &&
    a.content === b.content &&
    (a.mediaUrl ?? null) === (b.mediaUrl ?? null) &&
    sentAtMillis(a) === sentAtMillis(b)
  );
}

/** Fusionne les messages de plusieurs docs sources, dédoublonne par id,
 * régénère un id neuf en cas de collision sur un contenu différent. */
function mergeMessages(perSourceMessages, warnings) {
  const byId = new Map();
  for (const list of perSourceMessages) {
    for (const msg of list) {
      const existing = byId.get(msg.id);
      if (!existing) {
        byId.set(msg.id, msg);
        continue;
      }
      if (messagesEqual(existing.data, msg.data)) {
        // Doublon réel (même contenu, même id) : ne garder qu'un exemplaire.
        continue;
      }
      // Collision improbable (id Firestore auto-généré, ~10^-20 de
      // probabilité par paire) sur un contenu DIFFÉRENT : régénère un id
      // neuf pour ne jamais perdre silencieusement l'un des deux messages.
      const freshId = db.collection("_ids").doc().id;
      warnings.push(
        `Collision d'id de message '${msg.id}' entre ${existing.sourceChatId} et ${msg.sourceChatId} ` +
          `(contenus différents) — réattribué à '${freshId}'.`
      );
      byId.set(freshId, { ...msg, id: freshId });
    }
  }
  return [...byId.values()].sort((a, b) => sentAtMillis(a.data) - sentAtMillis(b.data));
}

function computeUnreadCounts(mergedMessages, buyerId, sellerId) {
  let buyerUnread = 0;
  let sellerUnread = 0;
  for (const { data } of mergedMessages) {
    if (data.status === "read") continue;
    if (data.receiverId === buyerId) buyerUnread++;
    if (data.receiverId === sellerId) sellerUnread++;
  }
  return { buyerUnread, sellerUnread };
}

/** Doc source le plus récemment actif du groupe — sert à choisir
 * noms/photos/listingId/listingTitle "à jour" plutôt qu'une fusion
 * ambiguë champ par champ. */
function mostRecentSource(group) {
  return group.reduce((best, cur) => {
    const bestAt = typeof best.data.lastMessageAt === "number" ? best.data.lastMessageAt : -1;
    const curAt = typeof cur.data.lastMessageAt === "number" ? cur.data.lastMessageAt : -1;
    return curAt > bestAt ? cur : best;
  });
}

async function commitInChunks(operations, chunkSize = 400) {
  for (let i = 0; i < operations.length; i += chunkSize) {
    const batch = db.batch();
    for (const op of operations.slice(i, i + chunkSize)) op(batch);
    await batch.commit();
  }
}

async function main() {
  console.log(
    DO_WRITE
      ? `=== MODE APPLICATION (merge${APPLY_CLEANUP ? " + cleanup" : ""}) ===`
      : "=== MODE DRY-RUN (aucune écriture) ==="
  );

  const chats = await fetchAllChats();
  const groups = new Map(); // canonicalKey -> [{id, data}]
  for (const chat of chats) {
    const { buyerId, sellerId } = chat.data;
    if (!buyerId || !sellerId) {
      console.warn(`Chat ${chat.id} sans buyerId/sellerId, ignoré.`);
      continue;
    }
    const key = canonicalKey(buyerId, sellerId);
    const list = groups.get(key) ?? [];
    list.push(chat);
    groups.set(key, list);
  }

  let groupsNeedingWork = 0;
  let groupsAlreadyCanonical = 0;
  let totalMessagesRead = 0;
  // Somme des messages UNIQUES après dédoublonnage (peut légitimement être
  // inférieure à totalMessagesRead : un message déjà copié lors d'un
  // --apply-merge précédent, puis relu depuis son doc source encore
  // présent, est un vrai doublon détecté par mergeMessages — jamais une
  // perte). C'est CETTE valeur, pas totalMessagesRead, qui doit être
  // comparée à ce qui est effectivement copié.
  let totalMessagesMerged = 0;
  let totalMessagesAfter = 0;
  let totalGroupErrors = 0;
  const warnings = [];

  for (const [key, group] of groups) {
    const needsWork = group.length > 1 || group[0].id !== key;
    if (!needsWork) {
      groupsAlreadyCanonical++;
      continue;
    }
    groupsNeedingWork++;

    const reference = mostRecentSource(group);
    const { buyerId, sellerId } = reference.data;

    const perSourceMessages = [];
    for (const source of group) {
      const msgs = await fetchAllMessages(source.id);
      totalMessagesRead += msgs.length;
      perSourceMessages.push(msgs);
    }
    const merged = mergeMessages(perSourceMessages, warnings);
    totalMessagesMerged += merged.length;
    const last = merged[merged.length - 1];
    const { buyerUnread, sellerUnread } = computeUnreadCounts(merged, buyerId, sellerId);

    const canonicalData = {
      buyerId,
      sellerId,
      buyerName: reference.data.buyerName ?? "",
      sellerName: reference.data.sellerName ?? "",
      buyerProfileImageUrl: reference.data.buyerProfileImageUrl ?? null,
      sellerProfileImageUrl: reference.data.sellerProfileImageUrl ?? null,
      listingId: reference.data.listingId ?? null,
      listingTitle: reference.data.listingTitle ?? null,
      participants: [buyerId, sellerId],
      lastMessage: last ? last.data.content || null : reference.data.lastMessage ?? null,
      lastMessageAt: last ? sentAtMillis(last.data) : reference.data.lastMessageAt ?? null,
      lastSenderId: last ? last.data.senderId : reference.data.lastSenderId ?? null,
      buyerUnreadCount: buyerUnread,
      sellerUnreadCount: sellerUnread,
    };

    console.log(
      `\nGroupe ${key} : ${group.length} fil(s) source(s) [${group.map((c) => c.id).join(", ")}] ` +
        `-> ${merged.length} message(s) unique(s) après fusion.`
    );
    console.log(
      `  lastMessage="${(canonicalData.lastMessage ?? "").slice(0, 60)}" lastMessageAt=${canonicalData.lastMessageAt} ` +
        `buyerUnreadCount=${buyerUnread} sellerUnreadCount=${sellerUnread}`
    );

    if (!DO_WRITE) continue;

    const canonicalRef = db.collection("chats").doc(key);
    await canonicalRef.set(canonicalData);

    const writeOps = merged.map(
      (msg) => (batch) => batch.set(canonicalRef.collection("messages").doc(msg.id), msg.data)
    );
    await commitInChunks(writeOps);

    const afterSnap = await canonicalRef.collection("messages").count().get();
    const afterCount = afterSnap.data().count;
    totalMessagesAfter += afterCount;
    if (afterCount !== merged.length) {
      totalGroupErrors++;
      console.error(
        `  ERREUR : ${afterCount} message(s) présents après copie, ${merged.length} attendus — ` +
          `nettoyage SAUTÉ pour ce groupe.`
      );
      continue;
    }
    console.log(`  Fusion écrite avec succès (${afterCount} messages sur ${key}).`);

    if (!APPLY_CLEANUP) continue;

    const redundant = group.filter((c) => c.id !== key);
    for (const dup of redundant) {
      await db.recursiveDelete(db.collection("chats").doc(dup.id));
      console.log(`  Supprimé : chats/${dup.id} (fusionné dans ${key}).`);
    }
  }

  if (warnings.length > 0) {
    console.log("\n--- Avertissements ---");
    for (const w of warnings) console.log(`  ${w}`);
  }

  console.log("\n--- Rapport final ---");
  console.log(`Groupes (binômes acheteur/vendeur) : ${groups.size}`);
  console.log(`Déjà canoniques (rien à faire) : ${groupsAlreadyCanonical}`);
  console.log(`Groupes fusionnés (ou à fusionner) : ${groupsNeedingWork}`);
  console.log(`Messages lus au total (avant dédoublonnage) : ${totalMessagesRead}`);
  console.log(`Messages uniques après fusion : ${totalMessagesMerged}`);
  if (DO_WRITE) {
    console.log(`Messages présents après copie (cible) : ${totalMessagesAfter}`);
    console.log(
      totalMessagesAfter === totalMessagesMerged
        ? "Auto-contrôle : OK (chaque message unique a bien été copié, rien perdu)."
        : "Auto-contrôle : ÉCART DÉTECTÉ — voir les erreurs de groupe ci-dessus."
    );
  }
  console.log(`Erreurs de groupe : ${totalGroupErrors}`);
  if (!DO_WRITE) {
    console.log("Relancer avec --apply-merge pour écrire les fils fusionnés.");
  } else if (!APPLY_CLEANUP) {
    console.log(
      "Rien supprimé (--apply-cleanup non fourni) : les anciens doublons restent en place."
    );
  }

  if (totalGroupErrors > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error("Échec du script de migration :", err);
  process.exitCode = 1;
});
