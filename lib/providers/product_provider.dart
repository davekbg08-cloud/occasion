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

/// Cache Riverpod par vendeur : une seule lecture Firestore par [sellerId],
/// réutilisée par tous les écrans/providers qui watchent ce même vendeur
/// (marketplace, détail d'annonce), au lieu de relire `publicProfiles` à
/// chaque reconstruction ou pour chaque provider séparé (N+1 répété).
final sellerProfileProvider = FutureProvider.autoDispose
    .family<UserModel?, String>((ref, sellerId) {
      return _fetchSellerProfile(FirebaseFirestore.instance, sellerId);
    });

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
  final sellerIds = annonces
      .map((annonce) => annonce.userId)
      .where((sellerId) => sellerId.trim().isNotEmpty)
      .toSet();
  // ref.watch(sellerProfileProvider(id).future) partage le même cache par
  // sellerId que productFromAnnonceProvider ci-dessous — un vendeur déjà
  // résolu ailleurs (ex. écran de détail déjà ouvert) ne redéclenche pas de
  // lecture Firestore.
  final sellerEntries = await Future.wait(
    sellerIds.map(
      (sellerId) async => MapEntry(
        sellerId,
        await ref.watch(sellerProfileProvider(sellerId).future),
      ),
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
          : await ref.watch(sellerProfileProvider(annonce.userId).future);
      return annonceToProductModel(annonce, seller);
    });
