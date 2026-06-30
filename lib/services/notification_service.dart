import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    // Firebase may already be initialized by the platform isolate.
  }
  debugPrint('Notification arrière-plan : ${message.notification?.title}');
}

class NotificationService {
  NotificationService._();

  static final _fcm = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StreamSubscription<String>? _tokenRefreshSubscription;

  static const _channel = AndroidNotificationChannel(
    'occasion_channel',
    'Notifications',
    description: 'Messages et nouveaux articles',
    importance: Importance.high,
    playSound: true,
  );

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    try {
      await _requestPermission();
      await _setupLocalNotifications(navigatorKey);

      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_showLocalNotification);
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _navigate(message, navigatorKey);
      });

      final initial = await _fcm.getInitialMessage();
      if (initial != null) {
        Future<void>.delayed(const Duration(seconds: 1), () {
          _navigate(initial, navigatorKey);
        });
      }
    } catch (error) {
      debugPrint('Notifications non initialisées : $error');
    }
  }

  static Future<void> _requestPermission() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> _setupLocalNotifications(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (details) {
        _navigateFromPayload(details.payload, navigatorKey);
      },
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _local.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: _buildPayload(message.data),
    );
  }

  static void _navigate(
    RemoteMessage message,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    _navigateFromPayload(_buildPayload(message.data), navigatorKey);
  }

  static void _navigateFromPayload(
    String? payload,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    if (payload == null) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    if (payload.startsWith('message')) {
      context.push('/chat-list');
      return;
    }

    if (payload.startsWith('status')) {
      context.go('/home');
    }
  }

  static String _buildPayload(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    final id = data['chatId'] ?? data['statusId'] ?? '';
    return '$type:$id';
  }

  static Future<void> saveToken(String userId) async {
    if (userId.isEmpty) return;

    try {
      final token = await _fcm.getToken();
      if (token == null) return;

      await _updateToken(userId, token);
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _fcm.onTokenRefresh.listen((newToken) {
        _updateToken(userId, newToken);
      });
    } catch (error) {
      debugPrint('Token FCM non sauvegardé : $error');
    }
  }

  static Future<void> _updateToken(String userId, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }

  static Future<void> clearToken(String userId) async {
    try {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      await _fcm.deleteToken();
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'fcmToken': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Token FCM non supprimé : $error');
    }
  }

  static void openChat({
    required String sellerId,
    required String sellerName,
    String? buyerId,
    String? buyerName,
  }) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;

    final extra = <String, String>{
      'sellerId': sellerId,
      'sellerName': sellerName,
    };
    if (buyerId != null) extra['buyerId'] = buyerId;
    if (buyerName != null) extra['buyerName'] = buyerName;

    context.push('/open-chat', extra: extra);
  }
}
