class Subscription {
  Subscription({
    required this.id,
    required this.userId,
    required this.planId,
    required this.planName,
    required this.price,
    required this.startDate,
    required this.expiryDate,
    required this.isActive,
    this.paymentMethod = 'Mobile Money',
    this.transactionId,
  });

  final String id;
  final String userId;
  final String planId;
  final String planName;
  final double price;
  final DateTime startDate;
  final DateTime expiryDate;
  final bool isActive;
  final String paymentMethod;
  final String? transactionId;

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  factory Subscription.fromMap(Map<String, dynamic> map, {String? id}) {
    return Subscription(
      id: id ?? map['id'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      planId: map['planId'] as String? ?? 'seller_monthly',
      planName: map['planName'] as String? ?? 'Vendeur Mensuel',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      startDate: _toDate(map['startDate']),
      expiryDate: _toDate(map['expiryDate']),
      isActive: map['isActive'] as bool? ?? false,
      paymentMethod: map['paymentMethod'] as String? ?? 'Mobile Money',
      transactionId: map['transactionId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'planId': planId,
      'planName': planName,
      'price': price,
      'startDate': startDate,
      'expiryDate': expiryDate,
      'isActive': isActive,
      'paymentMethod': paymentMethod,
      'transactionId': transactionId,
    };
  }

  static DateTime _toDate(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    try {
      final dynamic dynamicValue = value;
      final converted = dynamicValue?.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Fallback below.
    }
    return DateTime.now();
  }
}
