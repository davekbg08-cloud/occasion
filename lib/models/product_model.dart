import 'product.dart';

class ProductModel extends Product {
  const ProductModel({
    required super.id,
    required super.name,
    required super.description,
    required super.price,
    this.imageUrl,
    this.sellerId,
    this.sellerName,
    this.sellerPhone,
    this.isSellerVerified = false,
    this.category,
  });

  final String? imageUrl;
  final String? sellerId;
  final String? sellerName;
  final String? sellerPhone;
  final bool isSellerVerified;
  final String? category;

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      imageUrl: map['imageUrl'] as String?,
      sellerId: map['sellerId'] as String?,
      sellerName: map['sellerName'] as String?,
      sellerPhone: map['sellerPhone'] as String?,
      isSellerVerified: map['isSellerVerified'] as bool? ?? false,
      category: map['category'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'imageUrl': imageUrl,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'sellerPhone': sellerPhone,
    'isSellerVerified': isSellerVerified,
    'category': category,
  };

  ProductModel copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    String? sellerId,
    String? sellerName,
    String? sellerPhone,
    bool? isSellerVerified,
    String? category,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerPhone: sellerPhone ?? this.sellerPhone,
      isSellerVerified: isSellerVerified ?? this.isSellerVerified,
      category: category ?? this.category,
    );
  }
}
