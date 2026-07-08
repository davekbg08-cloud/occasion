class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.currency = 'USD',
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final String currency;
}
