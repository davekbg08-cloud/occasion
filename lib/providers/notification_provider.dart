import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationsProvider =
    StateNotifierProvider<NotificationNotifier, List<AppNotification>>((ref) {
  return NotificationNotifier();
});

class AppNotification {
  const AppNotification({
    required this.message,
    required this.createdAt,
    this.isRead = false,
  });

  final String message;
  final DateTime createdAt;
  final bool isRead;

  AppNotification copyWith({
    String? message,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return AppNotification(
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }
}

class NotificationNotifier extends StateNotifier<List<AppNotification>> {
  NotificationNotifier() : super(const []);

  void addNotification(String message) {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) return;

    state = [
      AppNotification(message: trimmedMessage, createdAt: DateTime.now()),
      ...state,
    ];
  }

  void markAsRead(int index) {
    if (index < 0 || index >= state.length) return;

    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index) state[i].copyWith(isRead: true) else state[i],
    ];
  }

  void clearNotifications() {
    state = const [];
  }
}
