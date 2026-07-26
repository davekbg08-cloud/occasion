import 'package:cloud_firestore/cloud_firestore.dart';

/// Article du catalogue de cadeaux d'un vendeur (`giftCatalogItems/{id}`),
/// échangeable contre des points de fidélité gagnés chez ce même vendeur.
class GiftCatalogItem {
  const GiftCatalogItem({
    required this.id,
    required this.sellerId,
    required this.title,
    this.description = '',
    this.imageUrl,
    this.pointsCost = 0,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String sellerId;
  final String title;
  final String description;
  final String? imageUrl;
  final int pointsCost;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory GiftCatalogItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = snapshot.data() ?? const <String, dynamic>{};
    return GiftCatalogItem(
      id: snapshot.id,
      sellerId: map['sellerId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      imageUrl: map['imageUrl'] as String?,
      pointsCost: (map['pointsCost'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] as bool? ?? true,
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'sellerId': sellerId,
    'title': title,
    'description': description,
    // Omis si absent plutôt qu'écrit comme `null` : les règles Firestore
    // valident un champ optionnel présent comme devant être une string,
    // `null` échouerait cette validation.
    if (imageUrl != null) 'imageUrl': imageUrl,
    'pointsCost': pointsCost,
    'isActive': isActive,
  };

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
