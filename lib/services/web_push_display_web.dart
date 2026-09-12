// `flutter_local_notifications` n'a aucune implémentation web (vérifié :
// aucun dossier `web/` dans le package) — sans ce fichier, une notification
// FCM reçue pendant que l'onglet PWA est au premier plan ne s'affiche nulle
// part. Utilise directement l'API `Notification` du navigateur (via
// `package:web`, déjà présent en dépendance transitive de firebase_*) pour
// la bannière, et `navigator.vibrate` pour la vibration (mobile Chrome
// uniquement — ignoré silencieusement ailleurs, aucun matériel sur
// desktop). Le son proprement dit n'a pas d'option dédiée dans l'API
// Notification standard ; la plupart des navigateurs desktop jouent déjà un
// son système par défaut à l'affichage.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

void showWebPushNotificationImpl({
  required String title,
  required String body,
  String? route,
  List<int>? vibrationPatternMs,
}) {
  if (web.Notification.permission == 'granted') {
    try {
      final options = web.NotificationOptions(
        body: body,
        icon: '/occasion/icons/Icon-192.png',
        badge: '/occasion/icons/Icon-192.png',
        tag: (route == null || route.isEmpty) ? 'occasion' : route,
      );
      final notification = web.Notification(title, options);
      notification.onclick = ((web.Event event) {
        web.window.focus();
        if (route != null && route.isNotEmpty) {
          web.window.location.hash = route;
        }
        notification.close();
      }).toJS;
    } catch (_) {
      // Navigateur sans support de l'API Notification (ou permission
      // révoquée entre-temps) : jamais bloquant pour le reste de l'app.
    }
  }

  final pattern = vibrationPatternMs;
  if (pattern != null && pattern.isNotEmpty) {
    try {
      web.window.navigator.vibrate(pattern.map((ms) => ms.toJS).toList().toJS);
    } catch (_) {
      // Vibration non supportée (desktop, Safari...) : ignoré.
    }
  }
}

/// Demande la permission d'affichage de notifications navigateur —
/// nécessaire une seule fois par origine, idéalement déclenchée par un
/// geste utilisateur explicite plutôt qu'au chargement de la page (les
/// navigateurs bloquent/ignorent souvent une demande automatique).
Future<bool> requestWebNotificationPermissionImpl() async {
  try {
    if (web.Notification.permission == 'granted') return true;
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart == 'granted';
  } catch (_) {
    return false;
  }
}
