import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

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
      body: Column(
        children: [
          const _NotificationPermissionBanner(),
          Expanded(
            child: notificationsAsync.when(
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
                          color: notification.isRead
                              ? Colors.grey
                              : AppColors.primary,
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
                        onTap: () =>
                            _openNotification(context, ref, notification),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
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

/// Avertit quand la permission de notification est bloquée au niveau OS
/// (voir `NotificationService.isPermissionDenied`) : sans jeton FCM,
/// `sendToUser` (Cloud Function) ne peut plus jamais pousser de
/// notification système — cet écran (in-app) reste alors le SEUL endroit
/// où l'utilisateur voit ses notifications, sans jamais comprendre pourquoi
/// aucune bannière n'apparaît en dehors de l'app. Se réévalue à l'ouverture
/// de cet écran ET à chaque retour au premier plan de l'app (via
/// `WidgetsBindingObserver`) — sans ce second déclencheur, revenir des
/// réglages système après avoir réactivé la permission laisserait la
/// bannière affichée jusqu'à quitter puis rouvrir cet écran.
class _NotificationPermissionBanner extends StatefulWidget {
  const _NotificationPermissionBanner();

  @override
  State<_NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<_NotificationPermissionBanner>
    with WidgetsBindingObserver {
  bool _dismissed = false;
  late Future<bool> _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = NotificationService.isPermissionDenied();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _future = NotificationService.isPermissionDenied());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return FutureBuilder<bool>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        return MaterialBanner(
          backgroundColor: Colors.orange[100],
          leading: const Icon(Icons.notifications_off_outlined),
          content: const Text(
            "Les notifications sont désactivées pour Occasion : vous ne "
            'recevrez plus aucune alerte en dehors de l\'application. '
            'Activez-les dans les réglages du téléphone.',
          ),
          actions: [
            TextButton(
              onPressed: () => setState(() => _dismissed = true),
              child: const Text('Plus tard'),
            ),
            TextButton(
              onPressed: NotificationService.openSystemSettings,
              child: const Text('Ouvrir les réglages'),
            ),
          ],
        );
      },
    );
  }
}
