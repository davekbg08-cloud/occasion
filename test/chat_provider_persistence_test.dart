import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/message.dart';
import 'package:occasion/providers/chat_provider.dart';
import 'package:occasion/services/chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simule la fermeture complète de l'application : chaque test qui a
/// besoin de vérifier la survie d'un message après redémarrage crée un
/// PREMIER `ChatNotifier`, y déclenche un envoi, puis l'abandonne et crée
/// un SECOND `ChatNotifier` indépendant (rien n'est partagé en mémoire
/// entre les deux, exactement comme un nouveau process Flutter) — seule
/// la vraie persistance disque (`SharedPreferences`, mockée ici mais
/// jamais réinitialisée entre les deux instances) peut faire survivre
/// l'état.
class _FakeChatService extends ChatService {
  final _messagesControllers = <String, StreamController<List<Message>>>{};
  bool shouldFailSend = false;
  int _idCounter = 0;
  final List<String> sentClientMessageIds = [];

  StreamController<List<Message>> _controllerFor(String chatId) =>
      _messagesControllers.putIfAbsent(
        chatId,
        () => StreamController<List<Message>>.broadcast(),
      );

  void emitMessages(String chatId, List<Message> messages) {
    _controllerFor(chatId).add(messages);
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
      _controllerFor(chatId).stream;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Persistance de la boîte d\'envoi à travers un redémarrage complet', () {
    test(
      'un message failed est toujours visible, avec son texte, après reconstruction du provider',
      () async {
        final service = _FakeChatService()..shouldFailSend = true;
        final firstSession = ChatNotifier(service: service);
        firstSession.listenMessages('chat1', 'buyer1');
        await firstSession.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Message important',
        );
        expect(
          firstSession.state.messagesByChatId['chat1']!.single.status,
          MessageStatus.failed,
        );

        // "Fermeture complète de l'application" : nouvelle instance, rien
        // en mémoire n'est réutilisé.
        final secondSession = ChatNotifier(service: service);
        secondSession.listenMessages('chat1', 'buyer1');
        await Future<void>.delayed(Duration.zero);

        final restored =
            secondSession.state.messagesByChatId['chat1'] ?? const [];
        expect(restored, hasLength(1));
        expect(restored.single.status, MessageStatus.failed);
        expect(restored.single.content, 'Message important');
      },
    );

    test(
      'un message failed restauré peut être réessayé avec le même clientMessageId (jamais de nouvel id)',
      () async {
        final service = _FakeChatService()..shouldFailSend = true;
        final firstSession = ChatNotifier(service: service);
        firstSession.listenMessages('chat1', 'buyer1');
        await firstSession.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
        );
        final originalId = service.sentClientMessageIds.single;

        final secondSession = ChatNotifier(service: service);
        secondSession.listenMessages('chat1', 'buyer1');
        await Future<void>.delayed(Duration.zero);

        service.shouldFailSend = false;
        final restoredId =
            secondSession.state.messagesByChatId['chat1']!.single.id;
        expect(restoredId, originalId);
        await secondSession.retryMessage('chat1', restoredId);

        expect(service.sentClientMessageIds, [originalId, originalId]);
      },
    );

    test(
      'un message dont l\'envoi a réussi côté serveur mais dont la réponse a été perdue est reconnu confirmé, sans doublon, dès la réouverture',
      () async {
        final service = _FakeChatService()..shouldFailSend = true;
        final firstSession = ChatNotifier(service: service);
        firstSession.listenMessages('chat1', 'buyer1');
        await firstSession.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
        );
        final clientMessageId = service.sentClientMessageIds.single;

        // Le serveur a en réalité bien créé le message (voir sendChatMessage
        // : idempotent), seule la réponse callable a été perdue côté client
        // — simulé ici en faisant apparaître le document dans le flux
        // Firestore avant même la réouverture.
        final secondSession = ChatNotifier(service: service);
        secondSession.listenMessages('chat1', 'buyer1');
        await Future<void>.delayed(Duration.zero);
        service.emitMessages('chat1', [
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

        final messages =
            secondSession.state.messagesByChatId['chat1'] ?? const [];
        expect(
          messages,
          hasLength(1),
          reason:
              'jamais de doublon entre la bulle restaurée et le document réel',
        );
        expect(messages.single.status, MessageStatus.sent);
      },
    );

    test(
      'plusieurs messages en attente, dans plusieurs chats différents, survivent tous indépendamment',
      () async {
        final service = _FakeChatService()..shouldFailSend = true;
        final firstSession = ChatNotifier(service: service);
        firstSession.listenMessages('chat1', 'buyer1');
        await firstSession.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Premier chat, premier message',
        );
        await firstSession.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Premier chat, deuxième message',
        );
        firstSession.listenMessages('chat2', 'buyer1');
        await firstSession.sendMessage(
          chatId: 'chat2',
          senderId: 'buyer1',
          receiverId: 'seller2',
          content: 'Deuxième chat',
        );

        final secondSession = ChatNotifier(service: service);
        secondSession.listenMessages('chat1', 'buyer1');
        secondSession.listenMessages('chat2', 'buyer1');
        await Future<void>.delayed(Duration.zero);

        final chat1Messages =
            secondSession.state.messagesByChatId['chat1'] ?? const [];
        final chat2Messages =
            secondSession.state.messagesByChatId['chat2'] ?? const [];
        expect(chat1Messages, hasLength(2));
        expect(chat2Messages, hasLength(1));
        expect(
          chat1Messages.map((m) => m.content).toList(),
          ['Premier chat, premier message', 'Premier chat, deuxième message'],
          reason:
              'l\'ordre chronologique des messages restaurés doit être conservé',
        );
      },
    );
  });
}
