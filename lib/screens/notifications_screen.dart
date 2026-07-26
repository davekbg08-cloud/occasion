import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authNotifierProvider).currentUser?.id ?? '';
    final notificationsAsync = ref.watch(notificationsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          notificationsAsync.maybeWhen(
            data: (notifications) {
              final unreadIds = notifications
                  .where((n) => !n.isRead)
                  .map((n) => n.id)
                  .toList();
              return IconButton(
                tooltip: 'Tout marquer comme lu',
                icon: const Icon(Icons.done_all),
                onPressed: unreadIds.isEmpty
                    ? null
                    : () => ref
                          .read(notificationRepositoryProvider)
                          .markAllAsRead(unreadIds),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Text('Impossible de charger les notifications.'),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(child: Text('Aucune notification'));
          }
          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return Dismissible(
                key: ValueKey(notification.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => ref
                    .read(notificationRepositoryProvider)
                    .delete(notification.id),
                child: ListTile(
                  leading: Icon(
                    _iconFor(notification.type),
                    color: notification.isRead ? Colors.grey : Colors.blue,
                  ),
                  title: Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${notification.body}\n${_formatDate(notification.createdAt)}',
                  ),
                  isThreeLine: true,
                  onTap: () => _openNotification(context, ref, notification),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openNotification(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) {
    if (!notification.isRead) {
      ref.read(notificationRepositoryProvider).markAsRead(notification.id);
    }
    final route = notification.route;
    if (route != null && route.isNotEmpty) {
      context.push(route);
    }
  }

  IconData _iconFor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.message:
        return Icons.chat_bubble_outline;
      case AppNotificationType.status:
        return Icons.auto_awesome_outlined;
      case AppNotificationType.order:
        return Icons.shopping_bag_outlined;
      case AppNotificationType.subscription:
        return Icons.workspace_premium_outlined;
      case AppNotificationType.report:
        return Icons.flag_outlined;
      case AppNotificationType.system:
        return Icons.notifications_none;
    }
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
