import 'package:cloud_firestore/cloud_firestore.dart';

/// Agrégat serveur `sellerStatistics/{sellerId}`, calculé uniquement par
/// des Cloud Functions (jamais par le client). Tous les champs sont absents
/// tant qu'aucun évènement correspondant ne s'est produit — traités comme 0.
class SellerStatistics {
  const SellerStatistics({
    this.totalViews = 0,
    this.totalMessages = 0,
    this.totalSales = 0,
    this.revenue = const {},
    this.updatedAt,
  });

  final int totalViews;
  final int totalMessages;
  final int totalSales;
  final Map<String, num> revenue;
  final DateTime? updatedAt;

  factory SellerStatistics.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = snapshot.data() ?? const <String, dynamic>{};
    final revenueMap = map['revenue'] as Map<dynamic, dynamic>? ?? const {};
    final updatedAt = map['updatedAt'];
    return SellerStatistics(
      totalViews: (map['totalViews'] as num?)?.toInt() ?? 0,
      totalMessages: (map['totalMessages'] as num?)?.toInt() ?? 0,
      totalSales: (map['totalSales'] as num?)?.toInt() ?? 0,
      revenue: revenueMap.map(
        (key, value) => MapEntry(key.toString(), value as num? ?? 0),
      ),
      updatedAt: _readOptionalDate(updatedAt),
    );
  }
}

DateTime? _readOptionalDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
