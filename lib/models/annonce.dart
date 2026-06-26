class Annonce {
  const Annonce({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.currency = 'USD',
    required this.category,
    required this.userId,
    this.imageUrls = const <String>[],
    this.location,
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.views = 0,
    this.favoritesCount = 0,
  });

  final String id;
  final String title;
  final String description;
  final double price;
  final String currency;
  final String category;
  final String userId;
  final List<String> imageUrls;
  final String? location;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isActive;
  final int views;
  final int favoritesCount;

  factory Annonce.fromJson(Map<String, dynamic> json) {
    return Annonce(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: _toDouble(json['price']),
      currency: json['currency'] as String? ?? 'USD',
      category: json['category'] as String? ?? 'Divers',
      userId: json['userId'] as String? ?? '',
      imageUrls: (json['imageUrls'] as List<dynamic>? ?? const <dynamic>[]).map((item) => item.toString()).toList(),
      location: json['location'] as String?,
      createdAt: _toDateTime(json['createdAt']),
      updatedAt: _toDateTime(json['updatedAt']),
      isActive: json['isActive'] as bool? ?? true,
      views: _toInt(json['views']),
      favoritesCount: _toInt(json['favoritesCount']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
      'currency': currency,
      'category': category,
      'userId': userId,
      'imageUrls': imageUrls,
      'location': location,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isActive': isActive,
      'views': views,
      'favoritesCount': favoritesCount,
    };
  }

  Annonce copyWith({
    String? id,
    String? title,
    String? description,
    double? price,
    String? currency,
    String? category,
    String? userId,
    List<String>? imageUrls,
    String? location,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    int? views,
    int? favoritesCount,
  }) {
    return Annonce(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      userId: userId ?? this.userId,
      imageUrls: imageUrls ?? this.imageUrls,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      views: views ?? this.views,
      favoritesCount: favoritesCount ?? this.favoritesCount,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    try {
      return value.toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}
