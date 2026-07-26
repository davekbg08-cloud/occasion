import 'package:cloud_firestore/cloud_firestore.dart';

/// Solde de points de fidélité d'un acheteur chez un vendeur donné
/// (`loyaltyPoints/{buyerId}_{sellerId}`), calculé uniquement par des Cloud
/// Functions. Les points gagnés chez un vendeur ne sont échangeables que
/// contre le catalogue de ce même vendeur.
class BuyerLoyaltyPoints {
  const BuyerLoyaltyPoints({
    required this.buyerId,
    required this.sellerId,
    this.balance = 0,
    this.lifetimeEarned = 0,
    this.lifetimeRedeemed = 0,
    this.updatedAt,
  });

  final String buyerId;
  final String sellerId;
  final int balance;
  final int lifetimeEarned;
  final int lifetimeRedeemed;
  final DateTime? updatedAt;

  factory BuyerLoyaltyPoints.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = snapshot.data() ?? const <String, dynamic>{};
    final updatedAt = map['updatedAt'];
    return BuyerLoyaltyPoints(
      buyerId: map['buyerId'] as String? ?? '',
      sellerId: map['sellerId'] as String? ?? '',
      balance: (map['balance'] as num?)?.toInt() ?? 0,
      lifetimeEarned: (map['lifetimeEarned'] as num?)?.toInt() ?? 0,
      lifetimeRedeemed: (map['lifetimeRedeemed'] as num?)?.toInt() ?? 0,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }
}
