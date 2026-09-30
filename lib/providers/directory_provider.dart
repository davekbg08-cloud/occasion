import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';

/// Répertoire de tous les profils publics (acheteurs ET vendeurs), pour
/// démarrer une conversation avec n'importe qui — sans jamais exposer de
/// numéro de téléphone : `publicProfiles` ne contient que nom, photo, rôle
/// et statut de vérification (voir `match /publicProfiles/{userId}` dans
/// firestore.rules pour la forme exacte de ce document). Flux temps réel :
/// un changement de nom/photo/statut de vérification se reflète tout seul.
final directoryProvider = StreamProvider.autoDispose<List<UserModel>>((ref) {
  return FirebaseFirestore.instance
      .collection('publicProfiles')
      .orderBy('name')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => UserModel.fromMap({...doc.data(), 'id': doc.id}))
            .toList(),
      );
});

/// Filtre pur (aucun accès réseau) appliqué à la liste brute du
/// répertoire : jamais soi-même, jamais un utilisateur bloqué, et une
/// recherche insensible à la casse/aux accents basiques sur le nom.
/// Extrait séparément du provider pour être testable sans émulateur
/// Firestore.
List<UserModel> filterDirectory(
  List<UserModel> all, {
  required String selfId,
  required Set<String> blockedUserIds,
  String query = '',
}) {
  final normalizedQuery = query.trim().toLowerCase();
  return all.where((user) {
    if (user.id == selfId) return false;
    if (blockedUserIds.contains(user.id)) return false;
    if (normalizedQuery.isEmpty) return true;
    return user.name.toLowerCase().contains(normalizedQuery);
  }).toList();
}
