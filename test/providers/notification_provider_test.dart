import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/providers/notification_provider.dart';

void main() {
  test('NotificationNotifier adds and clears notifications', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(notificationsProvider.notifier);

    notifier.addNotification('Nouveau message reçu');

    var notifications = container.read(notificationsProvider);
    expect(notifications.length, 1);
    expect(notifications.first.message, 'Nouveau message reçu');
    expect(notifications.first.isRead, isFalse);

    notifier.markAsRead(0);
    notifications = container.read(notificationsProvider);
    expect(notifications.first.isRead, isTrue);

    notifier.clearNotifications();
    expect(container.read(notificationsProvider), isEmpty);
  });
}
