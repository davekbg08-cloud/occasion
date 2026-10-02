import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Résultat de [initializeFirebaseApp] : [configMismatch] est non nul quand
/// l'app native [DEFAULT] (Android, créée depuis google-services.json) ne
/// correspond pas à `DefaultFirebaseOptions` — à remonter à Crashlytics une
/// fois celui-ci prêt, pour que l'incohérence reste visible.
class FirebaseInitResult {
  const FirebaseInitResult(this.app, {this.configMismatch, this.stackTrace});

  final FirebaseApp app;
  final FirebaseException? configMismatch;
  final StackTrace? stackTrace;
}

/// `[core/duplicate-app]` sur [DEFAULT] signifie que l'app native existe
/// déjà mais avec d'autres options (cas des versions 1.4.0+16 à 1.5.4+21,
/// bloquées au démarrage pour tous les utilisateurs Android) : on réutilise
/// l'app native plutôt que d'empêcher l'ouverture de l'app.
Future<FirebaseInitResult> initializeFirebaseApp({
  FirebaseOptions? options,
}) async {
  try {
    final app = await Firebase.initializeApp(
      options: options ?? DefaultFirebaseOptions.currentPlatform,
    );
    return FirebaseInitResult(app);
  } on FirebaseException catch (e, st) {
    if (e.plugin != 'core' || e.code != 'duplicate-app') rethrow;
    return FirebaseInitResult(
      Firebase.app(),
      configMismatch: e,
      stackTrace: st,
    );
  }
}
