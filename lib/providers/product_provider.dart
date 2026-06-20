import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product_model.dart';

final productNotifierProvider = FutureProvider<List<ProductModel>>((ref) async {
  return const [
    ProductModel(
      id: 'phone-001',
      name: 'Smartphone Occasion',
      description: 'Téléphone vérifié, bon état, prêt à utiliser.',
      price: 85000,
      imageUrl: 'https://picsum.photos/id/160/600/600',
      sellerId: 'seller-demo',
      sellerName: 'Vendeur Occasion',
      sellerPhone: '0812345678',
      isSellerVerified: true,
      category: 'electronique',
    ),
    ProductModel(
      id: 'laptop-001',
      name: 'Ordinateur Portable',
      description: 'PC portable reconditionné pour travail et études.',
      price: 180000,
      imageUrl: 'https://picsum.photos/id/0/600/600',
      sellerId: 'seller-demo',
      sellerName: 'Vendeur Occasion',
      sellerPhone: '+243812345678',
      isSellerVerified: true,
      category: 'electronique',
    ),
    ProductModel(
      id: 'watch-001',
      name: 'Montre Connectée',
      description: 'Accessoire connecté avec autonomie confortable.',
      price: 35000,
      imageUrl: 'https://picsum.photos/id/119/600/600',
      sellerId: 'seller-demo',
      sellerName: 'Vendeur Occasion',
      sellerPhone: '243812345678',
      category: 'autre',
    ),
  ];
});
