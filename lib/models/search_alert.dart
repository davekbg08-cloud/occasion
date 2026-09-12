class SearchAlert {
  const SearchAlert({
    required this.id,
    required this.userId,
    this.keyword = '',
    this.city = '',
    this.category = '',
    this.createdAt,
  });

  final String id;
  final String userId;
  final String keyword;
  final String city;
  final String category;
  final DateTime? createdAt;

  /// Libellé lisible pour l'écran de gestion des alertes.
  String get label {
    final parts = [
      if (keyword.trim().isNotEmpty) '"${keyword.trim()}"',
      if (city.trim().isNotEmpty) city.trim(),
      if (category.trim().isNotEmpty) category.trim(),
    ];
    return parts.isEmpty ? 'Toutes les nouvelles annonces' : parts.join(' · ');
  }

  factory SearchAlert.fromJson(Map<String, dynamic> json) {
    return SearchAlert(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      keyword: json['keyword'] as String? ?? '',
      city: json['city'] as String? ?? '',
      category: json['category'] as String? ?? '',
      createdAt: _toDateTime(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      if (city.trim().isNotEmpty) 'city': city.trim(),
      if (category.trim().isNotEmpty) 'category': category.trim(),
    };
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return value.toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}
