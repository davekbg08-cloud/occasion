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
      userId:
          json['utilisateurId'] as String? ?? json['userId'] as String? ?? '',
      annonceId: json['annonceId'] as String? ?? '',
      createdAt:
          _toDateTime(json['dateAjout'] ?? json['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'utilisateurId': userId,
      'annonceId': annonceId,
      'dateAjout': createdAt,
    };
  }

  void validate() {
    final errors = <String>[];
    if (userId.trim().isEmpty) errors.add('utilisateurId obligatoire');
    if (annonceId.trim().isEmpty) errors.add('annonceId obligatoire');
    if (errors.isNotEmpty) {
      throw ArgumentError(errors.join(', '));
    }
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
