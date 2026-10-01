import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_update_service.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});

final minAndroidVersionCodeProvider = StreamProvider<int?>((ref) {
  return ref.watch(appUpdateServiceProvider).minAndroidVersionCode();
});

/// `versionCode` de l'APK/AAB réellement installé sur cet appareil — lu
/// une seule fois (ne change jamais pendant que l'app tourne).
final installedVersionCodeProvider = FutureProvider<int>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber) ?? 0;
});

/// `true` uniquement quand un seuil est configuré ET que la version
/// installée est strictement en-dessous. Tant que l'un des deux flux n'a
/// pas encore répondu (démarrage de l'app, coupure réseau), reste `false`
/// — jamais de faux écran de blocage pendant le chargement.
final forceUpdateRequiredProvider = Provider<bool>((ref) {
  final min = ref.watch(minAndroidVersionCodeProvider).valueOrNull;
  final installed = ref.watch(installedVersionCodeProvider).valueOrNull;
  if (min == null || installed == null) return false;
  return installed < min;
});
