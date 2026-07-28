import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/message.dart';

Message _message({MessageStatus status = MessageStatus.sent}) {
  return Message(
    id: 'msg1',
    chatId: 'chat1',
    senderId: 'buyer1',
    receiverId: 'seller1',
    content: 'Bonjour',
    status: status,
    sentAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

void main() {
  group('MessageStatus', () {
    test(
      'sent/delivered/read font un aller-retour identique via toMap/fromMap',
      () {
        for (final status in [
          MessageStatus.sent,
          MessageStatus.delivered,
          MessageStatus.read,
        ]) {
          final map = _message(status: status).toMap();
          final restored = Message.fromMap({...map, 'id': 'msg1'});
          expect(
            restored.status,
            status,
            reason: '$status doit survivre à un aller-retour Firestore',
          );
        }
      },
    );

    test(
      'sending/failed sont des états locaux : jamais requis pour parser un document Firestore réel '
      '(un document sans ces valeurs retombe sur sent, jamais une exception)',
      () {
        final restored = Message.fromMap({
          'id': 'msg1',
          'chatId': 'chat1',
          'senderId': 'buyer1',
          'receiverId': 'seller1',
          'content': 'Bonjour',
          'status': 'sent',
          'sentAt': 1000,
        });
        expect(restored.status, MessageStatus.sent);
      },
    );

    test(
      'un statut inconnu/absent retombe sur sent plutôt que de lever une exception',
      () {
        final restored = Message.fromMap({
          'id': 'msg1',
          'chatId': 'chat1',
          'senderId': 'buyer1',
          'receiverId': 'seller1',
          'content': 'Bonjour',
          'sentAt': 1000,
        });
        expect(restored.status, MessageStatus.sent);
      },
    );

    test('isRead ne vaut true que pour le statut read', () {
      expect(_message(status: MessageStatus.read).isRead, true);
      for (final status in [
        MessageStatus.sending,
        MessageStatus.sent,
        MessageStatus.delivered,
        MessageStatus.failed,
      ]) {
        expect(
          _message(status: status).isRead,
          false,
          reason: '$status ne doit jamais être considéré comme lu',
        );
      }
    });
  });
}
