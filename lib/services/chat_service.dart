import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/chat.dart';
import '../models/message.dart';

class ChatService {
  ChatService([this._firestore, this._functionsOverride]);

  final FirebaseFirestore? _firestore;
  // Résolu paresseusement (pas dans l'initializer list), même pattern que
  // StatusService : évite de toucher FirebaseFunctions.instance tant que
  // markAsRead n'est pas réellement appelé.
  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

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

  /// Génère un identifiant de message stable, localement (aucun appel
  /// réseau, aucune nouvelle dépendance — réutilise l'id auto généré par
  /// le SDK Firestore côté client). Doit être généré UNE SEULE FOIS par
  /// message ; un retry doit toujours réutiliser le même id (jamais en
  /// générer un nouveau), c'est ce qui rend [sendChatMessage] idempotent.
  String newClientMessageId(String chatId) => _msgs(chatId).doc().id;

  /// Délègue entièrement à la Cloud Function callable `sendChatMessage` :
  /// le client ne choisit plus jamais `senderId`/`receiverId`/`status`
  /// (dérivés côté serveur de `request.auth.uid` et des participants du
  /// chat), et `clientMessageId` sert directement d'id de document — un
  /// retry sur le même id ne crée jamais de doublon (voir
  /// `functions/index.js::sendChatMessage`).
  Future<void> sendChatMessage({
    required String chatId,
    required String clientMessageId,
    required String content,
  }) async {
    await _functions.httpsCallable('sendChatMessage').call(<String, dynamic>{
      'chatId': chatId,
      'clientMessageId': clientMessageId,
      'content': content,
    });
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

  /// Un appel en cours par [chatId] (verrou local) : évite deux appels
  /// concurrents identiques à `markChatAsRead` (par ex. ouverture/fermeture
  /// rapide de la même conversation), en partageant le même `Future`.
  final Map<String, Future<void>> _markAsReadInFlight = {};

  /// Délègue entièrement à la Cloud Function callable `markChatAsRead`
  /// (Admin SDK) : le client n'écrit plus jamais directement ni le statut
  /// des messages ni `buyerUnreadCount`/`sellerUnreadCount` (les règles
  /// Firestore l'interdisent désormais totalement, y compris pour les
  /// diminuer). Le serveur détermine l'utilisateur via l'authentification
  /// de la requête, pas un paramètre transmis par le client. L'appelant
  /// (voir `ChatNotifier.listenMessages`) attend cette réponse puis se
  /// resynchronise avec les streams Firestore existants (`userChats`,
  /// `chatMessages`) — aucune erreur réseau ici ne doit fermer la
  /// conversation, elle reste catchable par l'appelant.
  Future<void> markAsRead(String chatId) {
    final inFlight = _markAsReadInFlight[chatId];
    if (inFlight != null) return inFlight;

    final future = _functions
        .httpsCallable('markChatAsRead')
        .call(<String, dynamic>{'chatId': chatId})
        .then((_) {})
        .whenComplete(() => _markAsReadInFlight.remove(chatId));
    _markAsReadInFlight[chatId] = future;
    return future;
  }

  Future<void> deleteChat(String chatId) async {
    await _chats.doc(chatId).delete();
  }
}
