import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Seule définition d'un administrateur, partout (règles Firestore
/// `isAdmin()`, Cloud Functions `assertIsAdmin`, app) : l'existence du
/// document `admins/{uid}`, lisible uniquement par son propriétaire et
/// jamais écrit par un client. Pas de rôle `admin` dans `users`, pas de
/// claim d'authentification.
class AdminService {
  AdminService({this.firestore});

  /// Remplaçable en test ; `FirebaseFirestore.instance` sinon.
  final FirebaseFirestore? firestore;

  Future<bool> isAdmin(String uid) async {
    try {
      final snap = await (firestore ?? FirebaseFirestore.instance)
          .collection('admins')
          .doc(uid)
          .get();
      return snap.exists;
    } catch (error, stackTrace) {
      developer.log(
        'Vérification admin impossible',
        name: 'AdminService.isAdmin',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
