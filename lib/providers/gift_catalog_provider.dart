import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift_catalog_item.dart';

class GiftCatalogRepository {
  GiftCatalogRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _ref =>
      _db.collection('giftCatalogItems');

  /// Tous les articles d'un vendeur (actifs et inactifs), pour son propre
  /// écran de gestion.
  Stream<List<GiftCatalogItem>> ownedByCatalog(String sellerId) {
    return _ref
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(GiftCatalogItem.fromFirestore).toList(),
        );
  }

  /// Articles actifs d'un vendeur, pour l'écran d'échange côté acheteur.
  Stream<List<GiftCatalogItem>> activeByCatalog(String sellerId) {
    return _ref
        .where('sellerId', isEqualTo: sellerId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(GiftCatalogItem.fromFirestore).toList(),
        );
  }

  Future<void> createItem(GiftCatalogItem item) {
    return _ref.add({
      ...item.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateItem(GiftCatalogItem item) {
    return _ref.doc(item.id).update({
      ...item.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteItem(String itemId) {
    return _ref.doc(itemId).delete();
  }
}

final giftCatalogRepositoryProvider = Provider<GiftCatalogRepository>((ref) {
  return GiftCatalogRepository();
});

final sellerGiftCatalogProvider = StreamProvider.autoDispose
    .family<List<GiftCatalogItem>, String>((ref, sellerId) {
      if (sellerId.isEmpty) {
        return Stream<List<GiftCatalogItem>>.value(const []);
      }
      return ref.watch(giftCatalogRepositoryProvider).ownedByCatalog(sellerId);
    });

final activeGiftCatalogProvider = StreamProvider.autoDispose
    .family<List<GiftCatalogItem>, String>((ref, sellerId) {
      if (sellerId.isEmpty) {
        return Stream<List<GiftCatalogItem>>.value(const []);
      }
      return ref.watch(giftCatalogRepositoryProvider).activeByCatalog(sellerId);
    });
