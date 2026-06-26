import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/favori.dart';

final favorisProvider =
    StateNotifierProvider.family<FavorisNotifier, List<Favori>, String>((ref, userId) {
  final notifier = FavorisNotifier(userId: userId);
  notifier.loadFavoris();
  return notifier;
});

class FavorisNotifier extends StateNotifier<List<Favori>> {
  FavorisNotifier({required this.userId}) : super(const []);

  final String userId;
  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _favorisRef =>
      _firestore.collection('favoris');

  Future<void> loadFavoris() async {
    if (userId.trim().isEmpty) return;
    final snapshot = await _favorisRef.where('userId', isEqualTo: userId).get();
    state = snapshot.docs
        .map((doc) => Favori.fromJson({...doc.data(), 'id': doc.id}))
        .toList();
  }

  Future<void> toggleFavori(String annonceId) async {
    if (userId.trim().isEmpty) {
      throw Exception('Utilisateur non connecté.');
    }

    final existing = state.where((favori) => favori.annonceId == annonceId).toList();
    if (existing.isNotEmpty) {
      await _favorisRef.doc(existing.first.id).delete();
      state = state.where((favori) => favori.annonceId != annonceId).toList();
      return;
    }

    final docRef = _favorisRef.doc();
    final favori = Favori(
      id: docRef.id,
      userId: userId,
      annonceId: annonceId,
      createdAt: DateTime.now(),
    );

    await docRef.set({
      ...favori.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    state = [...state, favori];
  }

  bool isFavorite(String annonceId) {
    return state.any((favori) => favori.annonceId == annonceId);
  }
}
