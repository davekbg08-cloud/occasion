import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/message.dart';
import 'package:occasion/models/status.dart';

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

  group('Message — média et transfert', () {
    test(
      'un message sans média a hasMedia=false et toMap() n\'expose aucun champ media*',
      () {
        final message = _message();
        expect(message.hasMedia, isFalse);
        expect(message.isForwarded, isFalse);
        final map = message.toMap();
        expect(map.containsKey('mediaUrl'), isFalse);
        expect(map.containsKey('mediaType'), isFalse);
        expect(map.containsKey('mediaWidth'), isFalse);
        expect(map.containsKey('mediaHeight'), isFalse);
        expect(map.containsKey('forwardedFromChatId'), isFalse);
        expect(map.containsKey('forwardedFromMessageId'), isFalse);
      },
    );

    test(
      'une photo fait un aller-retour identique via toMap/fromMap (URL, dimensions)',
      () {
        final message = Message(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Regarde ça',
          sentAt: DateTime.fromMillisecondsSinceEpoch(1000),
          mediaUrl:
              'https://firebasestorage.googleapis.com/v0/b/x/o/chatMedia%2Fchat1%2Fmsg1.jpg?alt=media',
          mediaType: StatusType.image,
          mediaWidth: 800,
          mediaHeight: 600,
        );

        expect(message.hasMedia, isTrue);
        final restored = Message.fromMap({...message.toMap(), 'id': 'msg1'});
        expect(restored.mediaUrl, message.mediaUrl);
        expect(restored.mediaType, StatusType.image);
        expect(restored.mediaWidth, 800);
        expect(restored.mediaHeight, 600);
      },
    );

    test('une vidéo fait un aller-retour identique (mediaType video)', () {
      final message = Message(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'buyer1',
        receiverId: 'seller1',
        content: '',
        sentAt: DateTime.fromMillisecondsSinceEpoch(1000),
        mediaUrl:
            'https://firebasestorage.googleapis.com/v0/b/x/o/chatMedia%2Fchat1%2Fmsg1.mp4?alt=media',
        mediaType: StatusType.video,
      );

      final restored = Message.fromMap({...message.toMap(), 'id': 'msg1'});
      expect(restored.mediaType, StatusType.video);
      expect(restored.hasMedia, isTrue);
    });

    test(
      'un message transféré fait un aller-retour identique et isForwarded=true',
      () {
        final message = Message(
          id: 'msg2',
          chatId: 'chat2',
          senderId: 'buyer1',
          receiverId: 'seller2',
          content: 'Bonjour',
          sentAt: DateTime.fromMillisecondsSinceEpoch(2000),
          forwardedFromChatId: 'chat1',
          forwardedFromMessageId: 'msg1',
        );

        expect(message.isForwarded, isTrue);
        final restored = Message.fromMap({...message.toMap(), 'id': 'msg2'});
        expect(restored.forwardedFromChatId, 'chat1');
        expect(restored.forwardedFromMessageId, 'msg1');
        expect(restored.isForwarded, isTrue);
      },
    );

    test('copyWith préserve tous les champs média/transfert', () {
      final message = Message(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'buyer1',
        receiverId: 'seller1',
        content: 'Photo',
        status: MessageStatus.sending,
        sentAt: DateTime.fromMillisecondsSinceEpoch(1000),
        mediaUrl: 'https://example.com/photo.jpg',
        mediaType: StatusType.image,
        mediaWidth: 100,
        mediaHeight: 200,
        forwardedFromChatId: 'chatX',
        forwardedFromMessageId: 'msgX',
      );

      final updated = message.copyWith(status: MessageStatus.sent);

      expect(updated.mediaUrl, message.mediaUrl);
      expect(updated.mediaType, message.mediaType);
      expect(updated.mediaWidth, message.mediaWidth);
      expect(updated.mediaHeight, message.mediaHeight);
      expect(updated.forwardedFromChatId, message.forwardedFromChatId);
      expect(updated.forwardedFromMessageId, message.forwardedFromMessageId);
    });
  });
}
