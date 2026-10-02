import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/chat.dart';
import 'package:occasion/models/message.dart';
import 'package:occasion/models/pending_chat_message.dart';
import 'package:occasion/providers/chat_provider.dart';
import 'package:occasion/services/chat_service.dart';
import 'package:occasion/services/pending_message_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chaque appel à `chatMessages`/`userChats` crée un NOUVEAU flux (comme un
/// nouveau listener Firestore), pour vérifier le réabonnement après erreur.
class _FakeChatService extends ChatService {
  final messageStreams = <StreamController<List<Message>>>[];
  final chatStreams = <StreamController<List<Chat>>>[];
  final sent = <String>[];

  /// Erreurs à lever, dans l'ordre, aux prochains envois (puis succès).
  final sendErrors = <Object>[];
  Completer<void>? sendGate;
  int _ids = 0;

  @override
  String newClientMessageId(String chatId) => 'm${_ids++}';

  @override
  Stream<List<Message>> chatMessages(String chatId) {
    final controller = StreamController<List<Message>>();
    messageStreams.add(controller);
    return controller.stream;
  }

  @override
  Stream<List<Chat>> userChats(String userId) {
    final controller = StreamController<List<Chat>>();
    chatStreams.add(controller);
    return controller.stream;
  }

  @override
  Future<void> markAsRead(String chatId) async {}

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
    sent.add(clientMessageId);
    final gate = sendGate;
    if (gate != null) await gate.future;
    if (sendErrors.isNotEmpty) throw sendErrors.removeAt(0);
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

PendingChatMessage pending(String chatId, String id, {int attempts = 1}) =>
    PendingChatMessage(
      clientMessageId: id,
      chatId: chatId,
      senderId: 'me',
      receiverId: 'other',
      content: 'Bonjour',
      localCreatedAt: DateTime(2026, 10, 2),
      state: PendingMessageState.failed,
      attemptCount: attempts,
    );

void main() {
  late _FakeChatService service;
  late PendingMessageStore store;
  late StreamController<bool> connectivity;
  late ChatNotifier notifier;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakeChatService();
    store = PendingMessageStore();
    connectivity = StreamController<bool>.broadcast();
    notifier = ChatNotifier(
      service: service,
      pendingStore: store,
      connectivity: connectivity.stream,
      retryDelay: (_) => Duration.zero,
    );
  });

  tearDown(() {
    notifier.dispose();
    connectivity.close();
  });

  test('un flux de messages en erreur est rouvert automatiquement '
      '(la conversation ne reste jamais figée)', () async {
    notifier.listenMessages('chat1', 'me');
    await settle();
    expect(service.messageStreams, hasLength(1));

    service.messageStreams.first.addError(Exception('UNAVAILABLE'));
    await settle();

    expect(service.messageStreams, hasLength(2), reason: 'réabonné');
    service.messageStreams.last.add([
      Message(
        id: 'srv1',
        chatId: 'chat1',
        senderId: 'other',
        receiverId: 'me',
        content: 'Toujours là',
        sentAt: DateTime(2026, 10, 2),
      ),
    ]);
    await settle();
    expect(notifier.state.messages.single.content, 'Toujours là');
  });

  test(
    'la liste des conversations en erreur est rouverte automatiquement',
    () async {
      notifier.listenChats('me');
      await settle();
      service.chatStreams.first.addError(Exception('permission-denied'));
      await settle();
      expect(service.chatStreams, hasLength(2));
    },
  );

  test('un échec transitoire (réseau) est renvoyé automatiquement, '
      'avec le même identifiant', () async {
    notifier.listenMessages('chat1', 'me');
    service.sendErrors.add(
      FirebaseFunctionsException(code: 'unavailable', message: 'hors ligne'),
    );

    await notifier.sendMessage(
      chatId: 'chat1',
      senderId: 'me',
      receiverId: 'other',
      content: 'Salut',
    );
    await settle();

    expect(service.sent, ['m0', 'm0']);
    expect(await store.load('me'), isEmpty, reason: 'confirmé au 2e essai');
  });

  test('un refus définitif (droits) n’est jamais renvoyé en boucle', () async {
    notifier.listenMessages('chat1', 'me');
    service.sendErrors.add(
      FirebaseFunctionsException(code: 'permission-denied', message: 'non'),
    );

    await notifier.sendMessage(
      chatId: 'chat1',
      senderId: 'me',
      receiverId: 'other',
      content: 'Salut',
    );
    await settle();

    expect(service.sent, ['m0']);
    expect(notifier.state.messages.single.status, MessageStatus.failed);
  });

  test('au retour du réseau, les messages en attente de TOUTES les '
      'conversations repartent (pas seulement celle ouverte)', () async {
    await store.upsert('me', pending('chatA', 'a1'));
    await store.upsert('me', pending('chatB', 'b1'));
    await store.upsert('me', pending('chatC', 'c1', attempts: 5));

    notifier.listenChats('me'); // déclenche déjà un premier vidage
    await settle();
    expect(service.sent..sort(), ['a1', 'b1'], reason: 'plafond respecté');

    service.sent.clear();
    connectivity.add(true);
    await settle();
    expect(service.sent, isEmpty, reason: 'déjà confirmés, rien à renvoyer');
  });

  test('deux déclencheurs simultanés n’envoient jamais deux fois le même '
      'message', () async {
    await store.upsert('me', pending('chatA', 'a1'));
    notifier.listenChats('me');
    service.sendGate = Completer<void>();
    await settle();

    connectivity.add(true);
    connectivity.add(true);
    await settle();
    service.sendGate!.complete();
    await settle();

    expect(service.sent, ['a1']);
  });

  test('une boîte d’envoi corrompue ne bloque plus jamais l’envoi', () async {
    SharedPreferences.setMockInitialValues({
      'pending_messages_v1_me': '{pas du json',
    });
    final corrupted = PendingMessageStore();

    expect(await corrupted.load('me'), isEmpty);
    await corrupted.upsert('me', pending('chatA', 'a1'));
    expect((await corrupted.load('me')).single.clientMessageId, 'a1');
  });
}
