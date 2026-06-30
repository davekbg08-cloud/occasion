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

  Stream<List<Chat>> userChats(String userId) {
    return _chats
        .where(
          Filter.or(
            Filter('buyerId', isEqualTo: userId),
            Filter('sellerId', isEqualTo: userId),
          ),
        )
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Chat.fromMap({...doc.data(), 'id': doc.id}))
              .toList(),
        );
  }

  Stream<List<Message>> chatMessages(String chatId) {
    return _msgs(chatId)
        .orderBy('sentAt')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => Message.fromMap({...doc.data(), 'id': doc.id}))
              .toList(),
        );
  }

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
      'unreadCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  Future<void> markAsRead(String chatId, String userId) async {
    final unread = await _msgs(chatId)
        .where('receiverId', isEqualTo: userId)
        .where('status', isNotEqualTo: MessageStatus.read.name)
        .get();

    if (unread.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'status': MessageStatus.read.name});
    }
    batch.update(_chats.doc(chatId), {'unreadCount': 0});
    await batch.commit();
  }

  Future<void> deleteChat(String chatId) async {
    await _chats.doc(chatId).delete();
  }
}
