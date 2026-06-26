import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreBootstrap {
  FirestoreBootstrap._();

  static bool _configured = false;

  static void configure(FirebaseFirestore firestore) {
    if (_configured) return;
    firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    _configured = true;
  }
}
