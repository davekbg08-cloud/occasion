import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';

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
      return ref.watch(notificationRepositoryProvider).forUser(userId);
    });

final unreadNotificationsCountProvider = Provider.autoDispose
    .family<int, String>((ref, userId) {
      final notifications = ref
          .watch(notificationsProvider(userId))
          .valueOrNull;
      if (notifications == null) return 0;
      return notifications.where((n) => !n.isRead).length;
    });
