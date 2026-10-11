import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Une personne qui a ouvert l'annonce (liste « Vues de l'annonce », visible
/// du seul vendeur — voir la règle `annonces/{id}/viewers` dans
/// firestore.rules). Nom et photo lus dans `publicProfiles`, donc toujours
/// à jour ; un compte supprimé n'apparaît plus.
class AnnonceViewer {
  const AnnonceViewer({
    required this.uid,
    required this.name,
    this.profileImageUrl,
    this.viewedAt,
    this.visits = 1,
  });

  final String uid;
  final String name;
  final String? profileImageUrl;
  final DateTime? viewedAt;
  final int visits;
}

const annonceViewersLimit = 300;

/// Assemble la liste à partir des documents `viewers` (id = uid du
/// visiteur, plus récent en premier) et des profils publics trouvés.
List<AnnonceViewer> buildAnnonceViewers(
  List<({String uid, DateTime? viewedAt, int visits})> views,
  Map<String, Map<String, dynamic>> profiles,
) {
  final viewers = <AnnonceViewer>[];
  for (final view in views) {
    final profile = profiles[view.uid];
    if (profile == null || profile['isDeleted'] == true) continue;
    final name = (profile['name'] as String?)?.trim() ?? '';
    final photo = (profile['profileImageUrl'] as String?)?.trim();
    viewers.add(
      AnnonceViewer(
        uid: view.uid,
        name: name.isEmpty ? 'Utilisateur' : name,
        profileImageUrl: (photo == null || photo.isEmpty) ? null : photo,
        viewedAt: view.viewedAt,
        visits: view.visits < 1 ? 1 : view.visits,
      ),
    );
  }
  return viewers;
}

final annonceViewersProvider = StreamProvider.autoDispose
    .family<List<AnnonceViewer>, String>((ref, annonceId) {
      final db = FirebaseFirestore.instance;
      final profileCache = <String, Map<String, dynamic>?>{};

      Future<Map<String, Map<String, dynamic>>> profilesFor(
        Iterable<String> uids,
      ) async {
        final missing = uids.where((uid) => !profileCache.containsKey(uid));
        final ids = missing.toList();
        for (var i = 0; i < ids.length; i += 30) {
          final chunk = ids.sublist(
            i,
            i + 30 > ids.length ? ids.length : i + 30,
          );
          final snap = await db
              .collection('publicProfiles')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final uid in chunk) {
            profileCache[uid] = null;
          }
          for (final doc in snap.docs) {
            profileCache[doc.id] = doc.data();
          }
        }
        return {
          for (final uid in uids)
            if (profileCache[uid] != null) uid: profileCache[uid]!,
        };
      }

      return db
          .collection('annonces')
          .doc(annonceId)
          .collection('viewers')
          .orderBy('viewedAt', descending: true)
          .limit(annonceViewersLimit)
          .snapshots()
          .asyncMap((snap) async {
            final views = [
              for (final doc in snap.docs)
                (
                  uid: doc.id,
                  viewedAt: (doc.data()['viewedAt'] as Timestamp?)?.toDate(),
                  visits: (doc.data()['visits'] as num?)?.toInt() ?? 1,
                ),
            ];
            final profiles = await profilesFor(views.map((v) => v.uid));
            return buildAnnonceViewers(views, profiles);
          });
    });
