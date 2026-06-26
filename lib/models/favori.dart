class Favori {
  const Favori({
    required this.id,
    required this.userId,
    required this.annonceId,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String annonceId;
  final DateTime createdAt;

  factory Favori.fromJson(Map<String, dynamic> json) {
    return Favori(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      annonceId: json['annonceId'] as String? ?? '',
      createdAt: _toDateTime(json['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'annonceId': annonceId,
      'createdAt': createdAt,
    };
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
