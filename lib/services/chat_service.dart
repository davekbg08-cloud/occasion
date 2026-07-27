import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat.dart';
import '../models/message.dart';

class ChatService {
  ChatService([this._firestore]);

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _chats {
    return _db.collection('chats');
  }

  CollectionReference<Map<String, dynamic>> _msgs(String chatId) {
    return _chats.doc(chatId).collection('messages');
  }

  String _chatId(String uid1, String uid2, String? listingId) {
    final ids = [uid1, uid2]..sort();
    final listingPart = listingId?.trim();
    if (listingPart != null && listingPart.isNotEmpty) {
      ids.add(listingPart.replaceAll('/', '_'));
    }
    return ids.join('_');
  }

  Future<Chat> getOrCreateChat({
    required String buyerId,
    required String sellerId,
    required String buyerName,
    required String sellerName,
    String? buyerProfileImageUrl,
    String? sellerProfileImageUrl,
    String? listingId,
    String? listingTitle,
  }) async {
    final id = _chatId(buyerId, sellerId, listingId);
    final doc = await _chats.doc(id).get();

    if (!doc.exists) {
      final chat = Chat(
        id: id,
        buyerId: buyerId,
        sellerId: sellerId,
        buyerName: buyerName,
        sellerName: sellerName,
        buyerProfileImageUrl: buyerProfileImageUrl,
        sellerProfileImageUrl: sellerProfileImageUrl,
        listingId: listingId,
        listingTitle: listingTitle,
      );
      await _chats.doc(id).set(chat.toMap());
      if (listingId != null && listingId.trim().isNotEmpty) {
        // Un seul incrément par nouveau fil de discussion, pas par message.
        try {
          await _db.collection('annonces').doc(listingId).update({
            'messagesCount': FieldValue.increment(1),
          });
        } catch (_) {
          // Best-effort : ne doit jamais bloquer la création du chat.
        }
      }
      return chat;
    }

    if ((listingTitle?.trim().isNotEmpty == true) ||
        (listingId?.trim().isNotEmpty == true)) {
      await _chats.doc(id).set({
        if (listingId?.trim().isNotEmpty == true) 'listingId': listingId,
        if (listingTitle?.trim().isNotEmpty == true)
          'listingTitle': listingTitle,
        'participants': [buyerId, sellerId],
      }, SetOptions(merge: true));
    }

    return Chat.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// Nombre de conversations les plus récentes écoutées en temps réel — pas
  /// d'écoute sans limite sur tout l'historique des conversations.
  static const int userChatsPageSize = 30;

  Stream<List<Chat>> userChats(String userId) {
    return _chats
        .where(
          Filter.or(
            Filter('buyerId', isEqualTo: userId),
            Filter('sellerId', isEqualTo: userId),
          ),
        )
        .orderBy('lastMessageAt', descending: true)
        .limit(userChatsPageSize)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Chat.fromMap({...doc.data(), 'id': doc.id}))
              .toList(),
        );
  }

  static const int messagePageSize = 50;

  /// Charge uniquement les [messagePageSize] messages les plus récents — pas
  /// tout l'historique en permanence. Utiliser [fetchOlderMessages] pour
  /// paginer vers les messages plus anciens.
  Stream<List<Message>> chatMessages(String chatId) {
    return _msgs(chatId)
        .orderBy('sentAt', descending: true)
        .limit(messagePageSize)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Message.fromMap({...doc.data(), 'id': doc.id}))
              .toList()
              .reversed
              .toList(),
        );
  }

  /// Lecture ponctuelle (pas un stream) des messages plus anciens que
  /// [before], pour la pagination vers l'historique.
  Future<List<Message>> fetchOlderMessages({
    required String chatId,
    required DateTime before,
    int pageSize = messagePageSize,
  }) async {
    final snapshot = await _msgs(chatId)
        .orderBy('sentAt', descending: true)
        .where('sentAt', isLessThan: before.millisecondsSinceEpoch)
        .limit(pageSize)
        .get();
    return snapshot.docs
        .map((doc) => Message.fromMap({...doc.data(), 'id': doc.id}))
        .toList()
        .reversed
        .toList();
  }

  /// Crée le message et met à jour uniquement les métadonnées non sensibles
  /// du chat (`lastMessage`/`lastMessageAt`/`lastSenderId`). L'incrément du
  /// compteur non-lu du destinataire est fait côté serveur par la Cloud
  /// Function `onNewMessage` (les règles Firestore interdisent à un
  /// participant de modifier le compteur de l'autre : un incrément client
  /// ferait échouer tout ce batch).
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final msgRef = _msgs(chatId).doc();
    final now = DateTime.now();
    final message = Message(
      id: msgRef.id,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: trimmed,
      sentAt: now,
    );

    final batch = _db.batch();
    batch.set(msgRef, message.toMap());
    batch.update(_chats.doc(chatId), {
      'lastMessage': trimmed,
      'lastMessageAt': now.millisecondsSinceEpoch,
      'lastSenderId': senderId,
    });
    await batch.commit();
  }

  /// Récupère un chat par son identifiant (contrairement à
  /// [getOrCreateChat], ne le crée jamais) — utilisé pour ouvrir une
  /// conversation depuis une notification (`chatId` connu, pas de
  /// buyerId/sellerId/noms à disposition).
  Future<Chat?> getChat(String chatId) async {
    final doc = await _chats.doc(chatId).get();
    if (!doc.exists) return null;
    return Chat.fromMap({...?doc.data(), 'id': doc.id});
  }

  /// Taille de lot pour marquer les messages non lus comme lus, sous la
  /// limite Firestore de 500 écritures/batch (marge pour l'écriture du
  /// compteur en plus des messages eux-mêmes).
  static const int _markAsReadBatchSize = 400;

  /// Ne marque comme lus que les messages reçus par [userId], et ne remet à
  /// zéro que le compteur de [userId] — jamais celui de l'autre participant.
  /// Traite les non-lus par lots successifs (au lieu d'un unique batch sans
  /// limite) pour ne jamais dépasser la limite Firestore de 500 écritures
  /// par batch sur un chat avec beaucoup de messages non lus.
  Future<void> markAsRead(String chatId, String userId) async {
    final chatDoc = await _chats.doc(chatId).get();
    final chatData = chatDoc.data();
    if (chatData == null) return;
    final buyerId = chatData['buyerId'] as String?;
    final unreadField = userId == buyerId
        ? 'buyerUnreadCount'
        : 'sellerUnreadCount';

    var hasMore = true;
    var isFirstBatch = true;
    while (hasMore) {
      final unread = await _msgs(chatId)
          .where('receiverId', isEqualTo: userId)
          .where('status', isNotEqualTo: MessageStatus.read.name)
          .limit(_markAsReadBatchSize)
          .get();

      final batch = _db.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'status': MessageStatus.read.name});
      }
      // Le compteur n'est remis à 0 qu'une fois, sur le premier lot : les
      // lots suivants ne font que rattraper le marquage `status` des
      // messages restants, le compteur est déjà à 0.
      if (isFirstBatch) {
        batch.update(_chats.doc(chatId), {unreadField: 0});
        isFirstBatch = false;
      }
      await batch.commit();

      hasMore = unread.docs.length == _markAsReadBatchSize;
    }
  }

  Future<void> deleteChat(String chatId) async {
    await _chats.doc(chatId).delete();
  }
}
