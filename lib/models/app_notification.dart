import 'package:cloud_firestore/cloud_firestore.dart';

/// Type d'évènement à l'origine d'une notification, utilisé côté client
/// pour choisir une icône et pour le routage au tap.
enum AppNotificationType {
  message,
  status,
  order,
  subscription,
  report,
  system;

  static AppNotificationType fromName(String? name) {
    return AppNotificationType.values.firstWhere(
      (value) => value.name == name,
      orElse: () => AppNotificationType.system,
    );
  }
}

/// Notification persistée dans Firestore (`notifications/{id}`), créée
/// uniquement côté serveur (Cloud Functions / Admin SDK). Le client peut
/// seulement la lire, la marquer comme lue ou la supprimer.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.route,
    this.entityId,
    this.chatId,
    this.listingId,
    this.statusId,
    this.orderId,
    this.paymentIntentId,
    this.isRead = false,
    this.readAt,
    this.data = const {},
  });

  final String id;
  final String recipientId;
  final String? senderId;
  final AppNotificationType type;
  final String title;
  final String body;
  final String? route;
  final String? entityId;
  final String? chatId;
  final String? listingId;
  final String? statusId;
  final String? orderId;
  final String? paymentIntentId;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> data;

  factory AppNotification.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = snapshot.data() ?? const <String, dynamic>{};
    return AppNotification(
      id: snapshot.id,
      recipientId: map['recipientId'] as String? ?? '',
      senderId: map['senderId'] as String?,
      type: AppNotificationType.fromName(map['type'] as String?),
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      route: map['route'] as String?,
      entityId: map['entityId'] as String?,
      chatId: map['chatId'] as String?,
      listingId: map['listingId'] as String?,
      statusId: map['statusId'] as String?,
      orderId: map['orderId'] as String?,
      paymentIntentId: map['paymentIntentId'] as String?,
      isRead: map['isRead'] as bool? ?? false,
      createdAt: _readDate(map['createdAt']),
      readAt: map['readAt'] == null ? null : _readDate(map['readAt']),
      data: Map<String, dynamic>.from(
        map['data'] as Map<dynamic, dynamic>? ?? const {},
      ),
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }
}
