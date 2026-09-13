import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../services/referral_service.dart';

final referralServiceProvider = Provider<ReferralService>(
  (ref) => ReferralService(),
);

/// Déclenche la génération du code de parrainage côté serveur pour les
/// comptes qui n'en ont pas encore (voir `ReferralService`/
/// `ensureReferralCode`). `ReferralScreen` observe ce provider uniquement
/// tant qu'il affiche l'état "code manquant" — une fois le code écrit,
/// `currentUserDocProvider` s'actualise tout seul et cette famille est
/// disposée (`autoDispose`), jamais rappelée pour rien.
final ensureReferralCodeProvider = FutureProvider.autoDispose
    .family<void, String>((ref, userId) {
      return ref.read(referralServiceProvider).ensureReferralCode();
    });

/// Flux en direct du document `users/{uid}` de l'utilisateur courant,
/// nécessaire ici car les champs de parrainage (`referralCode`,
/// `referralCount`, `referralRewardPoints`) sont écrits par les Cloud
/// Functions `onUserCreated`/`onReferredUserFirstOrder` (voir
/// `functions/index.js`), donc jamais présents dans l'état local
/// d'`AuthNotifier` juste après l'inscription — l'écran de parrainage doit
/// se mettre à jour tout seul dès qu'un filleul s'inscrit ou fait son
/// premier achat, sans exiger une reconnexion.
final currentUserDocProvider = StreamProvider.autoDispose
    .family<UserModel?, String>((ref, userId) {
      if (userId.isEmpty) {
        return Stream<UserModel?>.value(null);
      }
      return FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots()
          .map((snapshot) {
            final data = snapshot.data();
            if (data == null) return null;
            return UserModel.fromMap({...data, 'id': snapshot.id});
          });
    });
