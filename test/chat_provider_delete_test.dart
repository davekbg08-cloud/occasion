import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/chat.dart';
import 'package:occasion/models/message.dart';
import 'package:occasion/providers/chat_provider.dart';
import 'package:occasion/services/chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Double minimal : seules les trois suppressions (conversation entière,
/// "pour moi", message individuel) sont exercées par ce test.
class _FakeChatService extends ChatService {
  bool shouldFailDeleteChat = false;
  bool shouldFailDeleteChatForMe = false;
  bool shouldFailDeleteMessage = false;

  final List<String> deleteChatCalls = [];
  final List<String> deleteChatForMeCalls = [];
  final List<Map<String, Object?>> deleteMessageCalls = [];

  @override
  Stream<List<Chat>> userChats(String userId) =>
      const Stream<List<Chat>>.empty();

  @override
  Stream<List<Message>> chatMessages(String chatId) =>
      const Stream<List<Message>>.empty();

  @override
  Future<void> deleteChat(String chatId) async {
    deleteChatCalls.add(chatId);
    if (shouldFailDeleteChat) {
      throw Exception('erreur réseau simulée');
    }
  }

  @override
  Future<void> deleteChatForMe(String chatId) async {
    deleteChatForMeCalls.add(chatId);
    if (shouldFailDeleteChatForMe) {
      throw Exception('erreur réseau simulée');
    }
  }

  @override
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
    required bool forEveryone,
  }) async {
    deleteMessageCalls.add({
      'chatId': chatId,
      'messageId': messageId,
      'forEveryone': forEveryone,
    });
    if (shouldFailDeleteMessage) {
      throw Exception('erreur réseau simulée');
    }
  }
}

Chat _chat(String id) {
  return Chat(
    id: id,
    buyerId: 'buyer1',
    sellerId: 'seller1',
    buyerName: 'Acheteur',
    sellerName: 'Vendeur',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group(
    'ChatNotifier.deleteChat (suppression définitive, deux participants)',
    () {
      test('succès : retire le chat de state.chats', () async {
        final service = _FakeChatService();
        final notifier = ChatNotifier(service: service);
        notifier.state = notifier.state.copyWith(chats: [_chat('chat1')]);

        await notifier.deleteChat('chat1');

        expect(service.deleteChatCalls, ['chat1']);
        expect(notifier.state.chats, isEmpty);
      });

      test('échec réseau : garde le chat et pose state.error', () async {
        final service = _FakeChatService()..shouldFailDeleteChat = true;
        final notifier = ChatNotifier(service: service);
        notifier.state = notifier.state.copyWith(chats: [_chat('chat1')]);

        await notifier.deleteChat('chat1');

        expect(notifier.state.chats, hasLength(1));
        expect(notifier.state.error, isNotNull);
      });
    },
  );

  group('ChatNotifier.deleteChatForMe ("Supprimer pour moi")', () {
    test('succès : retire le chat de MA liste', () async {
      final service = _FakeChatService();
      final notifier = ChatNotifier(service: service);
      notifier.state = notifier.state.copyWith(chats: [_chat('chat1')]);

      await notifier.deleteChatForMe('chat1');

      expect(service.deleteChatForMeCalls, ['chat1']);
      expect(notifier.state.chats, isEmpty);
    });

    test('échec réseau : garde le chat et pose state.error', () async {
      final service = _FakeChatService()..shouldFailDeleteChatForMe = true;
      final notifier = ChatNotifier(service: service);
      notifier.state = notifier.state.copyWith(chats: [_chat('chat1')]);

      await notifier.deleteChatForMe('chat1');

      expect(notifier.state.chats, hasLength(1));
      expect(notifier.state.error, isNotNull);
    });
  });

  group('ChatNotifier.deleteMessage', () {
    test(
      'transmet chatId/messageId/forEveryone tels quels au service',
      () async {
        final service = _FakeChatService();
        final notifier = ChatNotifier(service: service);

        await notifier.deleteMessage(
          chatId: 'chat1',
          messageId: 'msg1',
          forEveryone: true,
        );

        expect(service.deleteMessageCalls, [
          {'chatId': 'chat1', 'messageId': 'msg1', 'forEveryone': true},
        ]);
      },
    );

    test('échec réseau : ne pose JAMAIS state.error (réservé aux échecs '
        "d'envoi) — l'appelant reçoit l'exception directement", () async {
      final service = _FakeChatService()..shouldFailDeleteMessage = true;
      final notifier = ChatNotifier(service: service);

      await expectLater(
        notifier.deleteMessage(
          chatId: 'chat1',
          messageId: 'msg1',
          forEveryone: false,
        ),
        throwsException,
      );
      expect(notifier.state.error, isNull);
    });
  });
}
