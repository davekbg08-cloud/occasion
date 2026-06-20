class Subscription {
  Subscription({
    required this.id,
    required this.planName,
    required this.price,
    required this.startDate,
    required this.expiryDate,
    required this.isActive,
    this.paymentMethod = 'Mobile Money',
  });

  final String id;
  final String planName;
  final double price;
  final DateTime startDate;
  final DateTime expiryDate;
  final bool isActive;
  final String paymentMethod;

  bool get isExpired => DateTime.now().isAfter(expiryDate);
}
