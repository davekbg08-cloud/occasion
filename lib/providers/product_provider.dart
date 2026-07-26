import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annonce/providers/annonce_provider.dart';
import '../models/annonce.dart';
import '../models/user.dart';
import '../models/product_model.dart';

Future<UserModel?> _fetchSellerProfile(
  FirebaseFirestore firestore,
  String sellerId,
) async {
  try {
    final snapshot = await firestore
        .collection('publicProfiles')
        .doc(sellerId)
        .get();
    final data = snapshot.data();
    if (data == null) return null;
    return UserModel.fromMap({...data, 'id': snapshot.id});
  } catch (_) {
    return null;
  }
}

/// Conversion pure Annonce -> ProductModel (vue affichée par les widgets de
/// listing existants). Fonction unique réutilisée par la liste marketplace
/// et le détail d'annonce, pour ne plus dupliquer/désynchroniser cette
/// logique (l'ancienne copie du détail d'annonce oubliait l'enrichissement
/// vendeur, ce qui masquait les badges "vérifié").
ProductModel annonceToProductModel(Annonce annonce, UserModel? seller) {
  return ProductModel(
    id: annonce.id,
    name: annonce.title,
    description: annonce.description,
    price: annonce.price,
    currency: annonce.currency,
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
}

/// Liste des produits affichés sur le marketplace, source unique désormais
/// `activeAnnoncesProvider` (Pile A / `AnnonceRepositoryImpl`).
final productNotifierProvider = FutureProvider<List<ProductModel>>((ref) async {
  final annonces = await ref.watch(activeAnnoncesProvider.future);
  final firestore = FirebaseFirestore.instance;
  final sellerIds = annonces
      .map((annonce) => annonce.userId)
      .where((sellerId) => sellerId.trim().isNotEmpty)
      .toSet();
  final sellerEntries = await Future.wait(
    sellerIds.map(
      (sellerId) async =>
          MapEntry(sellerId, await _fetchSellerProfile(firestore, sellerId)),
    ),
  );
  final sellers = <String, UserModel?>{
    for (final entry in sellerEntries) entry.key: entry.value,
  };

  return annonces
      .map((annonce) => annonceToProductModel(annonce, sellers[annonce.userId]))
      .toList();
});

/// Version détail (une seule annonce) de la même conversion, utilisée par
/// l'écran de détail d'annonce pour afficher les vraies infos vendeur.
final productFromAnnonceProvider = FutureProvider.autoDispose
    .family<ProductModel, Annonce>((ref, annonce) async {
      final seller = annonce.userId.trim().isEmpty
          ? null
          : await _fetchSellerProfile(
              FirebaseFirestore.instance,
              annonce.userId,
            );
      return annonceToProductModel(annonce, seller);
    });
