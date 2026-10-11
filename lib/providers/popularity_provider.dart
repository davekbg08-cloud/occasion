import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Barème des points de popularité (doit rester aligné sur
/// `POPULARITY_LIKES_PER_POINT`/`POPULARITY_MAX_POINTS_PER_DAY` dans
/// functions/index.js) : 1 point tous les 5 j'aime reçus sur ses statuts,
/// au plus 5 points par jour.
const popularityLikesPerPoint = 5;
const popularityMaxPointsPerDay = 5;

/// Points de popularité d'un vendeur, publics (`publicProfiles`), écrits
/// uniquement par la Cloud Function toggleStatusLike.
final sellerPopularityPointsProvider = StreamProvider.autoDispose
    .family<int, String>((ref, sellerId) {
      if (sellerId.isEmpty) return Stream.value(0);
      return FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(sellerId)
          .snapshots()
          .map(
            (snap) => (snap.data()?['popularityPoints'] as num?)?.toInt() ?? 0,
          );
    });
