import 'package:cloud_firestore/cloud_firestore.dart';

class AppUpdateService {
  AppUpdateService([this._firestore]);

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// `versionCode` Android minimal encore autorisé (voir `buildNumber` dans
  /// pubspec.yaml, ex. `1.5.0+17` -> 17) — document modifié uniquement
  /// depuis la console Firebase (`appConfig/androidVersion`, voir
  /// `firestore.rules` : `write: false` côté client, par conception, même
  /// principe que `appConfig/payments`). `null` tant qu'aucun seuil n'a
  /// été configuré, ou si le document/champ est absent — jamais bloquant
  /// par défaut.
  Stream<int?> minAndroidVersionCode() {
    return _db
        .collection('appConfig')
        .doc('androidVersion')
        .snapshots()
        .map((snap) => (snap.data()?['minVersionCode'] as num?)?.toInt());
  }
}
