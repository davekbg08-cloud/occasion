import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift_redemption.dart';
import '../models/loyalty_points.dart';
import '../services/loyalty_service.dart';

final loyaltyServiceProvider = Provider<LoyaltyService>((ref) {
  return LoyaltyService();
});

final sellerDisplayNameProvider = FutureProvider.autoDispose
    .family<String, String>((ref, sellerId) async {
      if (sellerId.isEmpty) return 'Vendeur';
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('publicProfiles')
            .doc(sellerId)
            .get();
        return snapshot.data()?['name'] as String? ?? 'Vendeur';
      } catch (_) {
        return 'Vendeur';
      }
    });

/// Soldes de points d'un acheteur, un par vendeur chez qui il a déjà gagné
/// des points.
final buyerLoyaltyPointsProvider = StreamProvider.autoDispose
    .family<List<BuyerLoyaltyPoints>, String>((ref, buyerId) {
      if (buyerId.isEmpty) {
        return Stream<List<BuyerLoyaltyPoints>>.value(const []);
      }
      return FirebaseFirestore.instance
          .collection('loyaltyPoints')
          .where('buyerId', isEqualTo: buyerId)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(BuyerLoyaltyPoints.fromFirestore)
                .where((points) => points.balance > 0)
                .toList(),
          );
    });

/// Historique des demandes d'échange d'un acheteur.
final buyerGiftRedemptionsProvider = StreamProvider.autoDispose
    .family<List<GiftRedemption>, String>((ref, buyerId) {
      if (buyerId.isEmpty) {
        return Stream<List<GiftRedemption>>.value(const []);
      }
      return FirebaseFirestore.instance
          .collection('giftRedemptions')
          .where('buyerId', isEqualTo: buyerId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(GiftRedemption.fromFirestore).toList(),
          );
    });

/// Demandes d'échange reçues par un vendeur pour son propre catalogue.
final sellerGiftRedemptionsProvider = StreamProvider.autoDispose
    .family<List<GiftRedemption>, String>((ref, sellerId) {
      if (sellerId.isEmpty) {
        return Stream<List<GiftRedemption>>.value(const []);
      }
      return FirebaseFirestore.instance
          .collection('giftRedemptions')
          .where('sellerId', isEqualTo: sellerId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(GiftRedemption.fromFirestore).toList(),
          );
    });
