class Review {
  const Review({
    required this.id,
    required this.orderId,
    required this.sellerId,
    required this.reviewerId,
    required this.revieweeId,
    required this.direction,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String sellerId;
  final String reviewerId;
  final String revieweeId;

  /// `buyer_to_seller` ou `seller_to_buyer`.
  final String direction;
  final int rating;
  final String comment;
  final DateTime? createdAt;

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String? ?? '',
      orderId: json['orderId'] as String? ?? '',
      sellerId: json['sellerId'] as String? ?? '',
      reviewerId: json['reviewerId'] as String? ?? '',
      revieweeId: json['revieweeId'] as String? ?? '',
      direction: json['direction'] as String? ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? '',
      createdAt: _toDateTime(json['createdAt']),
    );
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
