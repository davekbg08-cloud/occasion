import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/review.dart';
import '../services/review_service.dart';

final reviewServiceProvider = Provider<ReviewService>((ref) => ReviewService());

/// Avis récents reçus par un utilisateur (vendeur ou acheteur), triés du
/// plus récent au plus ancien, plafonnés à 30 (pas de pagination : suffisant
/// pour un profil, comme les autres flux "récents" de l'app).
final reviewsForUserProvider = StreamProvider.autoDispose
    .family<List<Review>, String>((ref, userId) {
      return FirebaseFirestore.instance
          .collection('reviews')
          .where('revieweeId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => Review.fromJson({...doc.data(), 'id': doc.id}))
                .toList(),
          );
    });
