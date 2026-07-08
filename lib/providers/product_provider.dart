import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../models/product_model.dart';
import 'occasion_firestore_providers.dart';

final productNotifierProvider = FutureProvider<List<ProductModel>>((ref) async {
  final annonces = await ref.watch(activeAnnoncesStreamProvider.future);
  final firestore = ref.watch(occasionFirestoreProvider);
  final sellerIds = annonces
      .map((annonce) => annonce.userId)
      .where((sellerId) => sellerId.trim().isNotEmpty)
      .toSet();
  final sellerEntries = await Future.wait(
    sellerIds.map((sellerId) async {
      try {
        final snapshot = await firestore
            .collection('publicProfiles')
            .doc(sellerId)
            .get();
        final data = snapshot.data();
        if (data == null) return MapEntry<String, UserModel?>(sellerId, null);
        return MapEntry(
          sellerId,
          UserModel.fromMap({...data, 'id': snapshot.id}),
        );
      } catch (_) {
        return MapEntry<String, UserModel?>(sellerId, null);
      }
    }),
  );
  final sellers = <String, UserModel?>{
    for (final entry in sellerEntries) entry.key: entry.value,
  };

  return annonces.map((annonce) {
    final seller = sellers[annonce.userId];
    return ProductModel(
      id: annonce.id,
      name: annonce.title,
      description: annonce.description,
      price: annonce.price,
      imageUrl: annonce.imageUrls.isEmpty ? null : annonce.imageUrls.first,
      imageUrls: annonce.imageUrls,
      sellerId: annonce.userId,
      sellerName: seller?.name ?? 'Vendeur',
      sellerPhone: annonce.phone,
      isSellerVerified: seller?.isVerifiedSeller ?? false,
      isSellerPhoneVerified: seller?.phoneVerified ?? false,
      sellerCreatedAt: seller?.createdAt,
      category: annonce.category,
    );
  }).toList();
});
