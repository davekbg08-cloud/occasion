import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:occasion/models/message.dart';
import 'package:occasion/models/status.dart';
import 'package:occasion/providers/chat_provider.dart';
import 'package:occasion/services/chat_media_upload_service.dart';
import 'package:occasion/services/chat_service.dart';
import 'package:occasion/services/pending_message_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Double de `ChatService` : au-delà de l'envoi/réception de texte déjà
/// couverts ailleurs, enregistre aussi les appels à `forwardMessage` (pour
/// vérifier que le provider délègue bien au bon endpoint, jamais un simple
/// re-upload) et supporte un flux multi-chat comme
/// `chat_provider_persistence_test.dart`.
class _FakeChatService extends ChatService {
  final _messagesControllers = <String, StreamController<List<Message>>>{};
  bool shouldFailSend = false;
  int _idCounter = 0;
  final List<String> sentClientMessageIds = [];
  final List<Map<String, String?>> sentMediaCalls = [];
  final List<Map<String, String>> forwardCalls = [];

  StreamController<List<Message>> _controllerFor(String chatId) =>
      _messagesControllers.putIfAbsent(
        chatId,
        () => StreamController<List<Message>>.broadcast(),
      );

  @override
  String newClientMessageId(String chatId) => 'local-${_idCounter++}';

  @override
  Future<void> sendChatMessage({
    required String chatId,
    required String clientMessageId,
    required String content,
    String? mediaUrl,
    String? mediaType,
    int? mediaWidth,
    int? mediaHeight,
  }) async {
    sentClientMessageIds.add(clientMessageId);
    sentMediaCalls.add({
      'clientMessageId': clientMessageId,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
    });
    if (shouldFailSend) {
      throw Exception('erreur réseau simulée');
    }
  }

  @override
  Future<void> forwardMessage({
    required String sourceChatId,
    required String sourceMessageId,
    required String targetChatId,
    required String clientMessageId,
  }) async {
    forwardCalls.add({
      'sourceChatId': sourceChatId,
      'sourceMessageId': sourceMessageId,
      'targetChatId': targetChatId,
      'clientMessageId': clientMessageId,
    });
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

/// Double de `ChatMediaUploadService` : ne touche jamais Firebase Storage.
/// [shouldFail] simule un échec d'upload (réseau coupé en plein transfert),
/// pour vérifier que RIEN n'est persisté dans ce cas (voir le commentaire
/// de `PendingChatMessage` sur l'ordre upload-puis-persistance).
class _FakeMediaUploadService extends ChatMediaUploadService {
  bool shouldFail = false;
  final List<String> uploadedForClientMessageIds = [];

  @override
  Future<ChatMediaUploadResult> upload({
    required String chatId,
    required String clientMessageId,
    required XFile mediaFile,
    required StatusType type,
    void Function(double progress)? onProgress,
  }) async {
    uploadedForClientMessageIds.add(clientMessageId);
    if (shouldFail) {
      throw Exception('upload impossible');
    }
    onProgress?.call(1.0);
    return ChatMediaUploadResult(
      url: 'https://example.com/chatMedia/$chatId/$clientMessageId.jpg',
      type: type,
      width: 800,
      height: 600,
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatNotifier.sendMediaMessage', () {
    late _FakeChatService service;
    late _FakeMediaUploadService mediaUpload;
    late ChatNotifier notifier;

    setUp(() {
      service = _FakeChatService();
      mediaUpload = _FakeMediaUploadService();
      notifier = ChatNotifier(
        service: service,
        mediaUploadService: mediaUpload,
      );
      notifier.listenMessages('chat1', 'buyer1');
    });

    test(
      'upload réussi : bulle optimiste avec mediaUrl, envoyée avec les bons champs média',
      () async {
        await notifier.sendMediaMessage(
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          mediaFile: XFile('photo.jpg'),
          mediaKind: StatusType.image,
          caption: 'Regarde',
        );

        final messages = notifier.state.messagesByChatId['chat1'] ?? const [];
        expect(messages, hasLength(1));
        expect(messages.single.hasMedia, isTrue);
        expect(messages.single.mediaType, StatusType.image);
        expect(messages.single.content, 'Regarde');

        expect(service.sentMediaCalls, hasLength(1));
        expect(service.sentMediaCalls.single['mediaUrl'], isNotNull);
        expect(service.sentMediaCalls.single['mediaType'], 'image');
      },
    );

    test(
      'échec d\'upload : aucune bulle affichée, aucune entrée persistée, jamais d\'appel réseau '
      '(rien n\'a été promis tant que l\'upload n\'a pas abouti)',
      () async {
        mediaUpload.shouldFail = true;

        await expectLater(
          notifier.sendMediaMessage(
            chatId: 'chat1',
            senderId: 'buyer1',
            receiverId: 'seller1',
            mediaFile: XFile('photo.jpg'),
            mediaKind: StatusType.image,
          ),
          throwsException,
        );

        expect(notifier.state.messagesByChatId['chat1'] ?? const [], isEmpty);
        expect(service.sentMediaCalls, isEmpty);
        final pending = await PendingMessageStore().load('buyer1');
        expect(pending, isEmpty);
      },
    );
  });

  group('ChatNotifier.forwardMessage', () {
    late _FakeChatService service;
    late ChatNotifier notifier;

    setUp(() {
      service = _FakeChatService();
      notifier = ChatNotifier(service: service);
      notifier.listenMessages('chat2', 'buyer1');
    });

    test(
      'transfère texte+média vers la conversation cible via ChatService.forwardMessage '
      '(jamais un nouvel appel sendChatMessage/upload)',
      () async {
        final source = Message(
          id: 'srcMsg1',
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Regarde ce produit',
          sentAt: DateTime.now(),
          mediaUrl: 'https://example.com/chatMedia/chat1/srcMsg1.jpg',
          mediaType: StatusType.image,
        );

        await notifier.forwardMessage(
          source: source,
          targetChatId: 'chat2',
          senderId: 'buyer1',
          receiverId: 'seller2',
        );

        expect(service.forwardCalls, hasLength(1));
        final call = service.forwardCalls.single;
        expect(call['sourceChatId'], 'chat1');
        expect(call['sourceMessageId'], 'srcMsg1');
        expect(call['targetChatId'], 'chat2');

        final messages = notifier.state.messagesByChatId['chat2'] ?? const [];
        expect(messages, hasLength(1));
        expect(messages.single.isForwarded, isTrue);
        expect(messages.single.forwardedFromChatId, 'chat1');
        expect(messages.single.forwardedFromMessageId, 'srcMsg1');
        expect(messages.single.hasMedia, isTrue);
      },
    );

    test(
      'un transfert en échec peut être retenté avec le même clientMessageId '
      '(jamais de doublon, même mécanisme que retryMessage pour le texte)',
      () async {
        service.shouldFailSend = true;
        final source = Message(
          id: 'srcMsg1',
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
          sentAt: DateTime.now(),
        );

        await notifier.forwardMessage(
          source: source,
          targetChatId: 'chat2',
          senderId: 'buyer1',
          receiverId: 'seller2',
        );

        final failedId = service.forwardCalls.single['clientMessageId'];
        expect(
          notifier.state.messagesByChatId['chat2']!.single.status,
          MessageStatus.failed,
        );

        service.shouldFailSend = false;
        await notifier.retryMessage('chat2', failedId!);

        expect(service.forwardCalls, hasLength(2));
        expect(service.forwardCalls[1]['clientMessageId'], failedId);
      },
    );
  });

  group(
    'Régression : retryMessage ne perd jamais les champs média/transfert',
    () {
      // Avant le correctif, le fallback `PendingChatMessage` reconstruit dans
      // `retryMessage`/`retryAllPending` à partir du seul `Message` local
      // omettait mediaUrl/mediaType/forwardedFromChatId — un retry aurait
      // silencieusement renvoyé un message texte vide à la place de la
      // photo/vidéo/transfert d'origine.
      test(
        'un message photo en échec renvoie la même mediaUrl au retry, jamais '
        'un message vide',
        () async {
          final service = _FakeChatService()..shouldFailSend = true;
          final mediaUpload = _FakeMediaUploadService();
          final notifier = ChatNotifier(
            service: service,
            mediaUploadService: mediaUpload,
          );
          notifier.listenMessages('chat1', 'buyer1');

          await notifier.sendMediaMessage(
            chatId: 'chat1',
            senderId: 'buyer1',
            receiverId: 'seller1',
            mediaFile: XFile('photo.jpg'),
            mediaKind: StatusType.image,
          );

          final failedId = service.sentMediaCalls.single['clientMessageId']!;
          expect(
            notifier.state.messagesByChatId['chat1']!.single.status,
            MessageStatus.failed,
          );
          final originalMediaUrl = service.sentMediaCalls.single['mediaUrl'];
          expect(originalMediaUrl, isNotNull);

          service.shouldFailSend = false;
          await notifier.retryMessage('chat1', failedId);

          expect(service.sentMediaCalls, hasLength(2));
          expect(service.sentMediaCalls[1]['clientMessageId'], failedId);
          expect(service.sentMediaCalls[1]['mediaUrl'], originalMediaUrl);
        },
      );

      test('un message transféré en échec renvoie via forwardMessage au retry, '
          'jamais via sendChatMessage (ne perd pas sa provenance)', () async {
        final service = _FakeChatService()..shouldFailSend = true;
        final notifier = ChatNotifier(service: service);
        notifier.listenMessages('chat2', 'buyer1');

        final source = Message(
          id: 'srcMsg1',
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
          sentAt: DateTime.now(),
        );
        await notifier.forwardMessage(
          source: source,
          targetChatId: 'chat2',
          senderId: 'buyer1',
          receiverId: 'seller2',
        );
        final failedId = service.forwardCalls.single['clientMessageId']!;

        service.shouldFailSend = false;
        await notifier.retryMessage('chat2', failedId);

        expect(
          service.forwardCalls,
          hasLength(2),
          reason:
              'le retry doit repasser par forwardMessage, jamais par '
              'sendChatMessage (qui perdrait forwardedFromChatId/Id)',
        );
        expect(
          service.sentClientMessageIds.where((id) => id == failedId).length,
          2,
          reason: 'même clientMessageId aux deux tentatives',
        );
      });
    },
  );
}
