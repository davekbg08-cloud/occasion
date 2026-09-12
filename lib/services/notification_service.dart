import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data' show Int64List;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final title = message.notification?.title ?? message.data['title'];
  debugPrint('Notification arrière-plan reçue : $title');

  // Filet de sécurité : un message avec un bloc `notification` (cas actuel
  // de tous les envois serveur : sendToUser/onNewStatus) est déjà affiché
  // automatiquement par le système à ce stade — ne RIEN afficher ici pour
  // ne jamais créer de doublon.
  //
  // Un message purement `data` (aucun envoi actuel n'en produit, mais nous
  // protège d'un futur oubli côté Cloud Functions) ne serait sinon jamais
  // visible en arrière-plan/app fermée : ce handler ne faisait que logger.
  // On l'affiche donc nous-mêmes dans ce seul cas.
  if (message.notification == null) {
    debugPrint('Message data-only en arrière-plan : secours manuel');
    await NotificationService._showBackgroundFallbackNotification(message);
  }
}

class NotificationService {
  NotificationService._();

  static final _fcm = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StreamSubscription<String>? _tokenRefreshSubscription;

  // Trois canaux distincts (au lieu d'un seul générique) : chacun avec sa
  // propre vibration explicite, l'utilisateur peut aussi les régler
  // indépendamment dans les paramètres Android. Le mapping type -> canal
  // doit rester synchronisé avec `androidChannelIdForType` côté serveur
  // (`functions/index.js`).
  static final _messagesChannel = AndroidNotificationChannel(
    'occasion_messages',
    'Messages',
    description: 'Nouveaux messages de conversation',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 250, 150, 250]),
  );

  static final _ordersChannel = AndroidNotificationChannel(
    'occasion_orders',
    'Commandes et abonnement',
    description: 'Paiements, commandes, demandes d\'abonnement',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 400, 200, 400, 200, 400]),
  );

  static final _generalChannel = AndroidNotificationChannel(
    'occasion_general',
    'Autres notifications',
    description: 'Nouveaux statuts et autres notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 250]),
  );

  static List<AndroidNotificationChannel> get _channels => [
    _messagesChannel,
    _ordersChannel,
    _generalChannel,
  ];

  /// Canal Android correspondant au `type` d'une notification — doit rester
  /// synchronisé avec `androidChannelIdForType` côté serveur.
  static AndroidNotificationChannel _channelForType(String? type) {
    switch (type) {
      case 'message':
        return _messagesChannel;
      case 'order':
      case 'subscription':
      case 'subscription_request':
        return _ordersChannel;
      default:
        return _generalChannel;
    }
  }

  static Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    try {
      await _requestPermission();
    } catch (error) {
      debugPrint('Permission notifications non accordée : $error');
    }

    try {
      await _setupLocalNotifications(navigatorKey);
    } catch (error) {
      // Sur le web, l'implémentation locale de flutter_local_notifications
      // dépend du navigateur et peut ne pas être disponible — ça ne doit
      // pas empêcher l'inscription aux flux FCM ci-dessous : la bannière
      // d'arrière-plan web est gérée par web/firebase-messaging-sw.js,
      // indépendamment de cette étape.
      debugPrint('Notifications locales non initialisées : $error');
    }

    try {
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
      debugPrint('Écoute FCM non initialisée : $error');
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
    const android = AndroidInitializationSettings(
      '@drawable/ic_stat_notification',
    );
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

    final androidImpl = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final channel in _channels) {
      await androidImpl?.createNotificationChannel(channel);
    }
  }

  /// Affiche la notification locale à partir du bloc `notification` du
  /// message FCM s'il est présent (cas normal aujourd'hui), sinon depuis
  /// `data['title']`/`data['body']` (message data-only) — ne renonce que si
  /// aucune des deux sources n'a de contenu affichable.
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final title =
        message.notification?.title ?? message.data['title'] as String?;
    final body = message.notification?.body ?? message.data['body'] as String?;
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final channel = _channelForType(message.data['type'] as String?);

    await _local.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_notification',
          enableVibration: true,
          vibrationPattern: channel.vibrationPattern,
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

  /// Filet de sécurité pour l'isolate d'arrière-plan (voir
  /// [firebaseBackgroundHandler]) : n'affiche que les messages `data`-only
  /// qui n'auraient sinon jamais été affichés par le système. Utilise sa
  /// propre instance du plugin car cet isolate ne partage pas l'état de
  /// [_local]/[init] de l'isolate principal — (re)créer les canaux ici est
  /// sans effet si déjà créés (idempotent côté Android).
  static Future<void> _showBackgroundFallbackNotification(
    RemoteMessage message,
  ) async {
    final title = message.data['title'] as String?;
    final body = message.data['body'] as String?;
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final channel = _channelForType(message.data['type'] as String?);
    final local = FlutterLocalNotificationsPlugin();

    const android = AndroidInitializationSettings(
      '@drawable/ic_stat_notification',
    );
    await local.initialize(
      settings: const InitializationSettings(android: android),
    );
    final androidImpl = local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.createNotificationChannel(channel);

    await local.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_stat_notification',
          enableVibration: true,
          vibrationPattern: channel.vibrationPattern,
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
    if (payload == null || payload.isEmpty) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    context.push(payload);
  }

  /// Résout la route de destination au tap : priorité au champ `route`
  /// (envoyé explicitement par la Cloud Function pour chaque notification),
  /// sinon déduite du `type` pour compatibilité avec d'anciens messages.
  static String _buildPayload(Map<String, dynamic> data) {
    final explicitRoute = data['route'] as String?;
    if (explicitRoute != null && explicitRoute.isNotEmpty) {
      return explicitRoute;
    }
    switch (data['type'] as String?) {
      case 'message':
        return '/chat-list';
      case 'status':
        return '/home';
      case 'order':
        return '/orders';
      case 'subscription':
        return '/subscription';
      default:
        return '/notifications';
    }
  }

  static String? _deviceId;

  /// Identifiant stable de cet appareil/installation, généré une seule fois
  /// et persisté localement (survit aux reconnexions, différent par
  /// appareil pour supporter plusieurs appareils connectés au même compte).
  static Future<String> _currentDeviceId() async {
    final cached = _deviceId;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
      id = base64UrlEncode(bytes).replaceAll('=', '');
      await prefs.setString('device_id', id);
    }
    _deviceId = id;
    return id;
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  /// Topic FCM annonçant les nouveaux statuts (voir
  /// `functions/index.js::onNewStatus`) — doit rester synchronisé avec la
  /// constante serveur `NEW_STATUS_TOPIC`. Topic global (décision produit) :
  /// tout acheteur y est abonné automatiquement, pas d'écran de préférence.
  static const _newStatusTopic = 'new_status';

  /// Clé "Web Push certificate" (VAPID) — Firebase Console > Paramètres du
  /// projet > Cloud Messaging > Configuration Web > Certificats Web Push.
  /// Obligatoire pour que `getToken()` fonctionne sur le web ; ignorée sans
  /// effet sur Android/iOS. Tant que ce placeholder n'est pas remplacé, la
  /// sauvegarde du token échoue silencieusement (voir catch ci-dessous) —
  /// aucune notification web ne peut être envoyée à cet appareil.
  static const _webVapidKey = 'REMPLACE_PAR_TA_CLE_VAPID_FIREBASE';

  static Future<void> saveToken(String userId, {bool isBuyer = false}) async {
    if (userId.isEmpty) return;

    try {
      final token = await _fcm.getToken(vapidKey: kIsWeb ? _webVapidKey : null);
      if (token == null) return;

      await _updateToken(userId, token);
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _fcm.onTokenRefresh.listen((newToken) {
        _updateToken(userId, newToken);
      });

      if (isBuyer) {
        await _fcm.subscribeToTopic(_newStatusTopic);
      }
    } catch (error) {
      debugPrint('Token FCM non sauvegardé : $error');
    }
  }

  static Future<void> _updateToken(String userId, String token) async {
    final deviceId = await _currentDeviceId();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(deviceId)
        .set({
          'token': token,
          'platform': _platformName(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Ne supprime que le jeton de CET appareil (déconnexion locale) : les
  /// autres appareils connectés au même compte continuent de recevoir les
  /// notifications.
  static Future<void> clearToken(String userId) async {
    try {
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      await _fcm.deleteToken();
      final deviceId = await _currentDeviceId();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc(deviceId)
          .delete();
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
