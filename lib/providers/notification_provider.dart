import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import 'chat_provider.dart';

class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _ref =>
      _db.collection('notifications');

  Stream<List<AppNotification>> forUser(String userId, {int limit = 50}) {
    return _ref
        .where('recipientId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(AppNotification.fromFirestore).toList(),
        );
  }

  /// Notifications plus anciennes que [before] (lecture ponctuelle, pas un
  /// flux temps réel) — permet de paginer au-delà de la limite fixe de
  /// [forUser] sans devoir l'augmenter.
  Future<List<AppNotification>> fetchOlderNotifications({
    required String userId,
    required DateTime before,
    int limit = 50,
  }) async {
    final snapshot = await _ref
        .where('recipientId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .startAfter([before])
        .limit(limit)
        .get();
    return snapshot.docs.map(AppNotification.fromFirestore).toList();
  }

  Future<void> markAsRead(String notificationId) {
    return _ref.doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllAsRead(List<String> unreadIds) async {
    if (unreadIds.isEmpty) return;
    final batch = _db.batch();
    for (final id in unreadIds) {
      batch.update(_ref.doc(id), {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> delete(String notificationId) {
    return _ref.doc(notificationId).delete();
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository();
});

final notificationsProvider = StreamProvider.autoDispose
    .family<List<AppNotification>, String>((ref, userId) {
      if (userId.isEmpty) return Stream<List<AppNotification>>.value(const []);
      // Les messages ont déjà leur propre badge fiable (onglet Messages,
      // basé sur chat.unreadCountFor) qui se remet à zéro à la lecture de
      // la conversation — jamais via cet écran. Les exclure ici évite de
      // les faire réapparaître indéfiniment comme "non lus" dans la
      // cloche alors qu'ils l'ont déjà été ailleurs.
      return ref
          .watch(notificationRepositoryProvider)
          .forUser(userId)
          .map(
            (list) => list
                .where((n) => n.type != AppNotificationType.message)
                .toList(),
          );
    });

final unreadNotificationsCountProvider = Provider.autoDispose
    .family<int, String>((ref, userId) {
      final notifications = ref
          .watch(notificationsProvider(userId))
          .valueOrNull;
      if (notifications == null) return 0;
      return notifications.where((n) => !n.isRead).length;
    });

/// Total affiché sur le badge d'icône de l'app (comme WhatsApp) : messages
/// non lus (déjà exclus de [unreadNotificationsCountProvider] depuis le
/// correctif de la cloche, donc jamais comptés deux fois) + notifications
/// non lues (commandes, abonnements, alertes de recherche, statuts...).
final appBadgeTotalProvider = Provider.autoDispose.family<int, String>((
  ref,
  userId,
) {
  final unreadMessages = ref.watch(
    chatNotifierProvider.select(
      (state) => state.chats.fold<int>(
        0,
        (total, chat) => total + chat.unreadCountFor(userId),
      ),
    ),
  );
  final unreadNotifications = ref.watch(
    unreadNotificationsCountProvider(userId),
  );
  return unreadMessages + unreadNotifications;
});
