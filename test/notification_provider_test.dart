import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/app_notification.dart';
import 'package:occasion/providers/notification_provider.dart';

void main() {
  group('notificationsProvider / unreadNotificationsCountProvider', () {
    test('régression : les notifications de type message sont exclues de la '
        'cloche (déjà suivies par le badge fiable de l\'onglet Messages, ne '
        'plus les compter en double comme "non lues" indéfiniment)', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('notifications').add({
        'recipientId': 'buyer1',
        'type': 'message',
        'title': 'Nouveau message',
        'body': 'Bonjour !',
        'isRead': false,
        'createdAt': DateTime(2026, 1, 1),
      });
      await firestore.collection('notifications').add({
        'recipientId': 'buyer1',
        'type': 'order',
        'title': 'Commande confirmée',
        'body': '...',
        'isRead': false,
        'createdAt': DateTime(2026, 1, 2),
      });

      final container = ProviderContainer(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(
            NotificationRepository(firestore: firestore),
          ),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        notificationsProvider('buyer1'),
        (previous, next) {},
      );
      addTearDown(subscription.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final list = container.read(notificationsProvider('buyer1')).valueOrNull;
      expect(list, isNotNull);
      expect(list!.length, 1);
      expect(list.single.type, AppNotificationType.order);

      expect(container.read(unreadNotificationsCountProvider('buyer1')), 1);
    });
  });
}
