import 'product.dart';

class ProductModel extends Product {
  const ProductModel({
    required super.id,
    required super.name,
    required super.description,
    required super.price,
    this.imageUrl,
    this.imageUrls = const <String>[],
    this.sellerId,
    this.sellerName,
    this.sellerPhone,
    this.isSellerVerified = false,
    this.isSellerPhoneVerified = false,
    this.sellerCreatedAt,
    this.category,
  });

  final String? imageUrl;
  final List<String> imageUrls;
  final String? sellerId;
  final String? sellerName;
  final String? sellerPhone;
  final bool isSellerVerified;
  final bool isSellerPhoneVerified;
  final DateTime? sellerCreatedAt;
  final String? category;

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      imageUrl: map['imageUrl'] as String?,
      imageUrls:
          (map['imageUrls'] as List<dynamic>? ??
                  map['images'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((e) => e.toString())
              .toList(),
      sellerId: map['sellerId'] as String?,
      sellerName: map['sellerName'] as String?,
      sellerPhone: map['sellerPhone'] as String?,
      isSellerVerified: map['isSellerVerified'] as bool? ?? false,
      isSellerPhoneVerified: map['isSellerPhoneVerified'] as bool? ?? false,
      sellerCreatedAt: _toDateTime(map['sellerCreatedAt']),
      category: map['category'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'imageUrl': imageUrl,
    'imageUrls': imageUrls,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'sellerPhone': sellerPhone,
    'isSellerVerified': isSellerVerified,
    'isSellerPhoneVerified': isSellerPhoneVerified,
    'sellerCreatedAt': sellerCreatedAt?.millisecondsSinceEpoch,
    'category': category,
  };

  ProductModel copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    List<String>? imageUrls,
    String? sellerId,
    String? sellerName,
    String? sellerPhone,
    bool? isSellerVerified,
    bool? isSellerPhoneVerified,
    DateTime? sellerCreatedAt,
    String? category,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerPhone: sellerPhone ?? this.sellerPhone,
      isSellerVerified: isSellerVerified ?? this.isSellerVerified,
      isSellerPhoneVerified:
          isSellerPhoneVerified ?? this.isSellerPhoneVerified,
      sellerCreatedAt: sellerCreatedAt ?? this.sellerCreatedAt,
      category: category ?? this.category,
    );
  }

  static DateTime? _toDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    try {
      final dynamic dynamicValue = value;
      final converted = dynamicValue?.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Keep product decoding tolerant.
    }
    return null;
  }
}
