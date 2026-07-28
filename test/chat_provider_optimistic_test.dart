import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/message.dart';
import 'package:occasion/providers/chat_provider.dart';
import 'package:occasion/services/chat_service.dart';

/// Double de test de `ChatService` : ne recouvre que les méthodes
/// effectivement appelées par `ChatNotifier` dans ce test
/// (`chatMessages`/`sendChatMessage`/`newClientMessageId`/`markAsRead`),
/// ne touche donc jamais Firestore/Functions réels. `chatMessages` est
/// piloté manuellement via [emitMessages] pour simuler l'arrivée d'un
/// instantané du flux réel.
class _FakeChatService extends ChatService {
  final _messagesController = StreamController<List<Message>>.broadcast();
  bool shouldFailSend = false;
  int _idCounter = 0;
  final List<String> sentClientMessageIds = [];

  void emitMessages(List<Message> messages) {
    _messagesController.add(messages);
  }

  @override
  String newClientMessageId(String chatId) => 'local-${_idCounter++}';

  @override
  Future<void> sendChatMessage({
    required String chatId,
    required String clientMessageId,
    required String content,
  }) async {
    sentClientMessageIds.add(clientMessageId);
    if (shouldFailSend) {
      throw Exception('erreur réseau simulée');
    }
  }

  @override
  Future<void> markAsRead(String chatId) async {}

  @override
  Stream<List<Message>> chatMessages(String chatId) =>
      _messagesController.stream;
}

void main() {
  group('ChatNotifier.sendMessage (envoi optimiste)', () {
    late _FakeChatService service;
    late ChatNotifier notifier;

    setUp(() {
      service = _FakeChatService();
      notifier = ChatNotifier(service: service);
      notifier.listenMessages('chat1', 'buyer1');
    });

    test(
      'insère une bulle locale sending avant même la résolution du futur',
      () async {
        final future = notifier.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
        );

        // La bulle locale doit être visible IMMÉDIATEMENT, sans attendre la
        // fin de l'appel réseau simulé.
        final messages = notifier.state.messagesByChatId['chat1'] ?? const [];
        expect(messages.length, 1);
        expect(messages.first.status, MessageStatus.sending);
        expect(messages.first.content, 'Bonjour');

        await future;
      },
    );

    test(
      'un instantané Firestore portant le même id remplace la bulle locale (jamais de doublon)',
      () async {
        await notifier.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
        );
        final clientMessageId = service.sentClientMessageIds.single;

        // Le flux Firestore délivre le document réel avec le même id.
        service.emitMessages([
          Message(
            id: clientMessageId,
            chatId: 'chat1',
            senderId: 'buyer1',
            receiverId: 'seller1',
            content: 'Bonjour',
            status: MessageStatus.sent,
            sentAt: DateTime.now(),
          ),
        ]);
        await Future<void>.delayed(Duration.zero);

        final messages = notifier.state.messagesByChatId['chat1'] ?? const [];
        expect(
          messages.length,
          1,
          reason:
              'aucun doublon : la bulle locale est remplacée, pas ajoutée en plus',
        );
        expect(messages.single.status, MessageStatus.sent);
      },
    );

    test(
      'une erreur d\'envoi fait passer la bulle locale à failed (jamais dans state.error)',
      () async {
        service.shouldFailSend = true;

        await notifier.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
        );

        final messages = notifier.state.messagesByChatId['chat1'] ?? const [];
        expect(messages.single.status, MessageStatus.failed);
        expect(
          notifier.state.error,
          isNull,
          reason:
              'un échec par message ne doit jamais déclencher l\'erreur globale d\'écran',
        );
      },
    );

    test(
      'retryMessage réutilise le même clientMessageId (jamais de nouvel id, jamais de doublon)',
      () async {
        service.shouldFailSend = true;
        await notifier.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
        );
        final failedId = service.sentClientMessageIds.single;

        service.shouldFailSend = false;
        await notifier.retryMessage('chat1', failedId);

        expect(
          service.sentClientMessageIds,
          [failedId, failedId],
          reason:
              'le retry doit réutiliser le même id, jamais en générer un nouveau',
        );
        final messages = notifier.state.messagesByChatId['chat1'] ?? const [];
        expect(messages.length, 1);
        expect(messages.single.status, MessageStatus.sending);
      },
    );
  });
}
