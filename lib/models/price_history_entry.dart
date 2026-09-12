class PriceHistoryEntry {
  const PriceHistoryEntry({
    required this.oldPrice,
    required this.newPrice,
    required this.currency,
    required this.changedAt,
  });

  final double oldPrice;
  final double newPrice;
  final String currency;
  final DateTime? changedAt;

  factory PriceHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PriceHistoryEntry(
      oldPrice: _toDouble(json['oldPrice']),
      newPrice: _toDouble(json['newPrice']),
      currency: json['currency'] as String? ?? 'FC',
      changedAt: _toDateTime(json['changedAt']),
    );
  }

  bool get isDecrease => newPrice < oldPrice;

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return 0;
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
