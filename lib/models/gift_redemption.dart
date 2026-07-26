import 'package:cloud_firestore/cloud_firestore.dart';

enum GiftRedemptionStatus {
  pending,
  fulfilled,
  rejected;

  static GiftRedemptionStatus fromName(String? name) {
    return GiftRedemptionStatus.values.firstWhere(
      (value) => value.name == name,
      orElse: () => GiftRedemptionStatus.pending,
    );
  }
}

/// Demande d'échange de points contre un article du catalogue d'un vendeur
/// (`giftRedemptions/{id}`). Créée et modifiée uniquement par des Cloud
/// Functions (jamais d'écriture client directe) : le débit/remboursement de
/// points doit être atomique avec le changement de statut.
class GiftRedemption {
  const GiftRedemption({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    required this.itemId,
    required this.itemTitle,
    required this.pointsCost,
    this.status = GiftRedemptionStatus.pending,
    this.createdAt,
    this.updatedAt,
    this.reviewedBy,
  });

  final String id;
  final String buyerId;
  final String sellerId;
  final String itemId;
  final String itemTitle;
  final int pointsCost;
  final GiftRedemptionStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? reviewedBy;

  factory GiftRedemption.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = snapshot.data() ?? const <String, dynamic>{};
    return GiftRedemption(
      id: snapshot.id,
      buyerId: map['buyerId'] as String? ?? '',
      sellerId: map['sellerId'] as String? ?? '',
      itemId: map['itemId'] as String? ?? '',
      itemTitle: map['itemTitle'] as String? ?? '',
      pointsCost: (map['pointsCost'] as num?)?.toInt() ?? 0,
      status: GiftRedemptionStatus.fromName(map['status'] as String?),
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
      reviewedBy: map['reviewedBy'] as String?,
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
