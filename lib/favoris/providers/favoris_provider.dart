import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/favori.dart';

final favorisProvider =
    StateNotifierProvider.family<FavorisNotifier, List<Favori>, String>((
      ref,
      userId,
    ) {
      final notifier = FavorisNotifier(userId: userId);
      notifier.loadFavoris();
      return notifier;
    });

class FavorisNotifier extends StateNotifier<List<Favori>> {
  FavorisNotifier({required this.userId, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      super(const []);

  final String userId;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _favorisRef =>
      _firestore.collection('favoris');

  Future<void> loadFavoris() async {
    if (userId.trim().isEmpty) return;
    final snapshot = await _favorisRef
        .where('utilisateurId', isEqualTo: userId)
        .get();
    state = snapshot.docs
        .map((doc) => Favori.fromJson({...doc.data(), 'id': doc.id}))
        .toList();
  }

  Future<void> toggleFavori(String annonceId) async {
    if (userId.trim().isEmpty) {
      throw Exception('Utilisateur non connecté.');
    }

    final existing = state
        .where((favori) => favori.annonceId == annonceId)
        .toList();
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

    // RÉGRESSION : `{...favori.toJson(), 'createdAt': ...}` ajoutait un
    // CINQUIÈME champ ('createdAt', en plus de 'dateAjout' déjà présent
    // dans toJson()) — `validFavori()` (firestore.rules) exige EXACTEMENT
    // les clés ['id', 'utilisateurId', 'annonceId', 'dateAjout'] via
    // `hasOnly()`, donc CHAQUE ajout aux favoris était rejeté en silence
    // (PERMISSION_DENIED jamais remonté à l'écran, voir toggleFavori dans
    // annonce_card.dart : Future non attendu par l'IconButton). N'écrit
    // que les champs attendus par la règle, avec l'horodatage serveur
    // directement sur 'dateAjout' (jamais l'heure locale du téléphone).
    await docRef.set({
      'id': favori.id,
      'utilisateurId': favori.userId,
      'annonceId': favori.annonceId,
      'dateAjout': FieldValue.serverTimestamp(),
    });
    state = [...state, favori];
  }

  bool isFavorite(String annonceId) {
    return state.any((favori) => favori.annonceId == annonceId);
  }
}
