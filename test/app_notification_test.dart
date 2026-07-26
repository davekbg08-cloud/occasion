import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/app_notification.dart';

void main() {
  group('AppNotification.fromFirestore', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('lit tous les champs et déduit le type', () async {
      final ref = firestore.collection('notifications').doc('n1');
      await ref.set({
        'recipientId': 'buyer1',
        'senderId': 'seller1',
        'type': 'message',
        'title': '💬 Vendeur',
        'body': 'Bonjour, toujours dispo ?',
        'route': '/chat-list',
        'chatId': 'chat1',
        'isRead': false,
        'createdAt': DateTime(2026, 1, 1),
        'data': {'chatId': 'chat1'},
      });

      final snapshot = await ref.get();
      final notification = AppNotification.fromFirestore(snapshot);

      expect(notification.id, 'n1');
      expect(notification.recipientId, 'buyer1');
      expect(notification.senderId, 'seller1');
      expect(notification.type, AppNotificationType.message);
      expect(notification.title, '💬 Vendeur');
      expect(notification.route, '/chat-list');
      expect(notification.chatId, 'chat1');
      expect(notification.isRead, isFalse);
      expect(notification.readAt, isNull);
      expect(notification.data['chatId'], 'chat1');
    });

    test('type inconnu ou absent retombe sur system', () async {
      final ref = firestore.collection('notifications').doc('n2');
      await ref.set({
        'recipientId': 'buyer1',
        'title': 'Titre',
        'body': 'Corps',
        'isRead': true,
        'createdAt': DateTime(2026, 1, 1),
        'readAt': DateTime(2026, 1, 2),
      });

      final snapshot = await ref.get();
      final notification = AppNotification.fromFirestore(snapshot);

      expect(notification.type, AppNotificationType.system);
      expect(notification.isRead, isTrue);
      expect(notification.readAt, isNotNull);
    });
  });
}
