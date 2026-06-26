import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Tout effacer',
            icon: const Icon(Icons.clear_all),
            onPressed: notifications.isEmpty
                ? null
                : () => ref
                    .read(notificationsProvider.notifier)
                    .clearNotifications(),
          ),
        ],
      ),
      body: notifications.isEmpty
          ? const Center(child: Text('Aucune notification'))
          : ListView.separated(
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return ListTile(
                  leading: Icon(
                    notification.isRead
                        ? Icons.notifications_none
                        : Icons.notifications_active,
                  ),
                  title: Text(notification.message),
                  subtitle: Text(_formatDate(notification.createdAt)),
                  onTap: () => ref
                      .read(notificationsProvider.notifier)
                      .markAsRead(index),
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return 'Il y a quelques instants';
    if (difference.inMinutes < 60) return 'Il y a ${difference.inMinutes} min';
    if (difference.inHours < 24) return 'Il y a ${difference.inHours} h';

    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }
}
