import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/message.dart';
import 'package:occasion/models/pending_chat_message.dart';
import 'package:occasion/providers/chat_provider.dart';
import 'package:occasion/services/chat_service.dart';
import 'package:occasion/services/pending_message_store.dart';
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

  /// Si non-null, `sendChatMessage` reste en attente jusqu'à ce que ce
  /// completer soit résolu — simule un appel réseau réellement en vol
  /// (jamais résolu instantanément), pour tester la protection
  /// `_inFlightDispatchIds` contre un double envoi du même message.
  Completer<void>? sendGate;

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
    final gate = sendGate;
    if (gate != null) {
      await gate.future;
    }
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

        // _loadPendingForChat déclenche désormais lui-même un retry
        // automatique borné dès la réouverture (voir le test dédié
        // ci-dessus) : le réseau échoue encore ici (shouldFailSend est
        // encore true à ce stade), donc cette tentative automatique
        // échoue aussi et compte comme un deuxième envoi avec le MÊME id
        // — c'est le comportement attendu, pas une régression.
        expect(service.sentClientMessageIds, [originalId, originalId]);

        service.shouldFailSend = false;
        final restoredId =
            secondSession.state.messagesByChatId['chat1']!.single.id;
        expect(restoredId, originalId);
        await secondSession.retryMessage('chat1', restoredId);

        expect(
          service.sentClientMessageIds,
          [originalId, originalId, originalId],
          reason:
              'le retry manuel réutilise toujours le même id, même après un '
              'retry automatique préalable ayant échoué',
        );
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

    test(
      'application tuée EN PLEIN ENVOI (état sending, pas failed) : le message est automatiquement relancé à la réouverture, jamais bloqué indéfiniment, MÊME sans attendre entre listenMessages et retryAllPending',
      () async {
        // Simule l'état disque laissé par une session précédente tuée
        // juste après que _dispatchSend ait écrit `sending` mais avant que
        // l'appel réseau n'ait eu le temps de réussir ou d'échouer — donc
        // AUCUNE trace d'un appel réseau réellement en cours dans cette
        // nouvelle session (contrairement à un message activement envoyé
        // maintenant, protégé par `_inFlightDispatchIds`).
        final store = PendingMessageStore();
        await store.upsert(
          'buyer1',
          PendingChatMessage(
            clientMessageId: 'local-killed-mid-send',
            chatId: 'chat1',
            senderId: 'buyer1',
            receiverId: 'seller1',
            content: 'Message interrompu',
            localCreatedAt: DateTime.now(),
            state: PendingMessageState.sending,
            attemptCount: 1,
          ),
        );

        final service = _FakeChatService();
        final notifier = ChatNotifier(service: service, pendingStore: store);

        // Reproduit EXACTEMENT l'ordre réel de chat_screen.dart::initState :
        // listenMessages (qui déclenche _loadPendingForChat en
        // `unawaited`, donc non terminé à ce point) immédiatement suivi de
        // retryAllPending, SANS aucun délai entre les deux appels — un
        // délai artificiel ici masquerait la course que ce test doit
        // détecter (voir _loadPendingForChat, qui doit désormais relancer
        // lui-même retryAllPending une fois la restauration terminée).
        notifier.listenMessages('chat1', 'buyer1');
        await notifier.retryAllPending('chat1');

        // Stabilisation APRÈS les deux appels seulement (légitime : laisse
        // le temps aux chaînes `unawaited` internes de se terminer avant
        // d'affirmer l'état final), jamais entre les deux appels testés.
        await Future<void>.delayed(Duration.zero);

        expect(
          service.sentClientMessageIds,
          contains('local-killed-mid-send'),
          reason:
              'le message restauré doit être relancé avec le MÊME clientMessageId, '
              'même quand retryAllPending est appelé sans attendre _loadPendingForChat',
        );
        final afterRetry = notifier.state.messagesByChatId['chat1'] ?? const [];
        expect(afterRetry.single.status, MessageStatus.sending);
      },
    );

    test(
      'un message sending qui atteint le plafond de retry auto bascule en failed (bouton Réessayer redevient disponible)',
      () async {
        final store = PendingMessageStore();
        await store.upsert(
          'buyer1',
          PendingChatMessage(
            clientMessageId: 'local-capped',
            chatId: 'chat1',
            senderId: 'buyer1',
            receiverId: 'seller1',
            content: 'Message bloqué',
            localCreatedAt: DateTime.now(),
            state: PendingMessageState.sending,
            attemptCount: ChatNotifier.maxAutoRetryAttempts,
          ),
        );

        final service = _FakeChatService();
        final notifier = ChatNotifier(service: service, pendingStore: store);

        notifier.listenMessages('chat1', 'buyer1');
        await notifier.retryAllPending('chat1');
        await Future<void>.delayed(Duration.zero);

        expect(
          service.sentClientMessageIds,
          isEmpty,
          reason: 'le plafond doit bloquer tout nouvel envoi automatique',
        );
        final afterCap = notifier.state.messagesByChatId['chat1'] ?? const [];
        expect(
          afterCap.single.status,
          MessageStatus.failed,
          reason:
              'sans cette bascule, le message resterait sending indéfiniment, '
              'sans jamais afficher le bouton Réessayer',
        );
        final persisted = await store.load('buyer1');
        expect(persisted.single.state, PendingMessageState.failed);
      },
    );

    test(
      'un message activement en cours d\'envoi DANS CETTE SESSION n\'est jamais relancé en double par retryAllPending',
      () async {
        final service = _FakeChatService()..sendGate = Completer<void>();
        final notifier = ChatNotifier(service: service);
        notifier.listenMessages('chat1', 'buyer1');

        // Envoi lancé mais délibérément jamais résolu tant que le gate
        // n'est pas libéré : simule un appel réseau lent, réellement en
        // vol au moment où retryAllPending est appelé.
        final sendFuture = notifier.sendMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'En cours',
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.sentClientMessageIds, hasLength(1));

        await notifier.retryAllPending('chat1');

        expect(
          service.sentClientMessageIds,
          hasLength(1),
          reason:
              'un envoi réellement en vol dans cette session ne doit jamais être relancé en double',
        );

        service.sendGate!.complete();
        await sendFuture;
      },
    );
  });
}
