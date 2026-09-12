/// Implémentation par défaut (Android/iOS/desktop non-web) : jamais appelée
/// en pratique, ces plateformes passent par `flutter_local_notifications`
/// (voir `notification_service.dart`) — présente uniquement pour que
/// l'import conditionnel compile sur toutes les cibles.
void showWebPushNotificationImpl({
  required String title,
  required String body,
  String? route,
  List<int>? vibrationPatternMs,
}) {}

Future<bool> requestWebNotificationPermissionImpl() async => false;
