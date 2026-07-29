import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/chat.dart';
import 'package:occasion/models/message.dart';
import 'package:occasion/providers/chat_provider.dart';
import 'package:occasion/services/chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Double minimal : seules `userChats`/`chatMessages`/`markAsRead` sont
/// exercées par ce test (changement de compte, jamais l'envoi lui-même).
class _FakeChatService extends ChatService {
  final _chatsControllers = <String, StreamController<List<Chat>>>{};
  bool shouldFailSendOverride = false;
  int _idCounter = 0;

  StreamController<List<Chat>> _controllerFor(String userId) =>
      _chatsControllers.putIfAbsent(
        userId,
        () => StreamController<List<Chat>>.broadcast(),
      );

  void emitChats(String userId, List<Chat> chats) {
    _controllerFor(userId).add(chats);
  }

  @override
  Stream<List<Chat>> userChats(String userId) => _controllerFor(userId).stream;

  @override
  Future<void> markAsRead(String chatId) async {}

  @override
  Stream<List<Message>> chatMessages(String chatId) =>
      const Stream<List<Message>>.empty();

  @override
  String newClientMessageId(String chatId) => 'local-${_idCounter++}';

  @override
  Future<void> sendChatMessage({
    required String chatId,
    required String clientMessageId,
    required String content,
  }) async {
    if (shouldFailSendOverride) {
      throw Exception('erreur réseau simulée');
    }
  }
}

Chat _chat(String id, String buyerId, String sellerId) {
  return Chat(
    id: id,
    buyerId: buyerId,
    sellerId: sellerId,
    buyerName: 'Acheteur',
    sellerName: 'Vendeur',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatNotifier.resetForUserChange (isolation entre comptes)', () {
    test(
      'vide entièrement chats/messages/erreur en mémoire de l\'ancien compte',
      () async {
        final service = _FakeChatService();
        final notifier = ChatNotifier(service: service);

        notifier.listenChats('buyer1');
        service.emitChats('buyer1', [_chat('chat1', 'buyer1', 'seller1')]);
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state.chats, hasLength(1));

        notifier.resetForUserChange();

        expect(notifier.state.chats, isEmpty);
        expect(notifier.state.messagesByChatId, isEmpty);
        expect(notifier.state.error, isNull);
      },
    );

    test(
      'permet de réécouter le même userId après reset (le nouveau compte n\'est jamais bloqué par la garde de l\'ancien)',
      () async {
        final service = _FakeChatService();
        final notifier = ChatNotifier(service: service);

        notifier.listenChats('buyer1');
        service.emitChats('buyer1', [_chat('chat-old', 'buyer1', 'seller1')]);
        await Future<void>.delayed(Duration.zero);
        expect(notifier.state.chats, hasLength(1));

        notifier.resetForUserChange();

        // Un compte différent qui utiliserait par coïncidence le même
        // identifiant applicatif ne doit jamais hériter de l'ancien flux :
        // un nouvel appel à listenChats doit re-souscrire, pas être ignoré
        // par la garde `_listeningUserId == userId`.
        notifier.listenChats('buyer1');
        service.emitChats('buyer1', [_chat('chat-new', 'buyer1', 'seller1')]);
        await Future<void>.delayed(Duration.zero);

        expect(notifier.state.chats.single.id, 'chat-new');
      },
    );

    test(
      'la boîte d\'envoi locale d\'un utilisateur reste intacte après le reset d\'un autre compte (isolation par clé de stockage)',
      () async {
        final service = _FakeChatService();
        final notifierBuyer = ChatNotifier(service: service);

        // buyer1 a un message en échec non confirmé.
        service.shouldFailSendOverride = true;
        notifierBuyer.listenMessages('chat1', 'buyer1');
        await notifierBuyer.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
        );

        notifierBuyer.resetForUserChange();

        // Un nouveau ChatNotifier pour seller1 (ex. connexion d'un autre
        // compte) ouvre le même chatId : la réconciliation locale ne doit
        // jamais réinjecter le message en échec de buyer1 dans l'état de
        // seller1 — la boîte d'envoi locale est scindée par userId, jamais
        // lue pour un autre utilisateur que celui demandé.
        final notifierSeller = ChatNotifier(service: service);
        notifierSeller.listenMessages('chat1', 'seller1');
        await Future<void>.delayed(Duration.zero);

        expect(notifierSeller.state.messagesByChatId['chat1'] ?? const [], isEmpty);
      },
    );
  });
}
