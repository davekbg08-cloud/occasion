// Import conditionnel : sur le web charge l'implémentation réelle (API
// Notification du navigateur), ailleurs un stub sans effet (Android/iOS
// passent par `flutter_local_notifications`, voir `notification_service.dart`).
// Même pattern que `video_compression_service.dart`.
import 'web_push_display_stub.dart'
    if (dart.library.js_interop) 'web_push_display_web.dart';

/// Affiche une notification système au premier plan sur le web — seule
/// plateforme où `flutter_local_notifications` n'a aucune implémentation
/// (vérifié : le package ne fournit aucun dossier `web/`). [route] est la
/// route déjà résolue côté serveur (`data['route']`), utilisée pour
/// naviguer si l'utilisateur clique la bannière.
void showWebPushNotification({
  required String title,
  required String body,
  String? route,
  List<int>? vibrationPatternMs,
}) => showWebPushNotificationImpl(
  title: title,
  body: body,
  route: route,
  vibrationPatternMs: vibrationPatternMs,
);

/// Demande la permission d'affichage de notifications navigateur.
Future<bool> requestWebNotificationPermission() =>
    requestWebNotificationPermissionImpl();
