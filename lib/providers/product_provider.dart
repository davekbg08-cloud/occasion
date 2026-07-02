import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product_model.dart';
import 'occasion_firestore_providers.dart';

final productNotifierProvider = FutureProvider<List<ProductModel>>((ref) async {
  final annonces = await ref.watch(activeAnnoncesStreamProvider.future);
  return annonces.map((annonce) {
    return ProductModel(
      id: annonce.id,
      name: annonce.title,
      description: annonce.description,
      price: annonce.price,
      imageUrl: annonce.imageUrls.isEmpty ? null : annonce.imageUrls.first,
      sellerId: annonce.userId,
      sellerName: 'Vendeur',
      sellerPhone: annonce.phone,
      category: annonce.category,
    );
  }).toList();
});
