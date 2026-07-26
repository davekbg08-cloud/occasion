import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/annonce_repository.dart';
import '../../shared/models/annonce.dart';

final annonceRepositoryProvider = Provider<AnnonceRepository>((ref) {
  return AnnonceRepositoryImpl();
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchFiltersProvider = StateProvider<Map<String, dynamic>>((ref) => {});

/// Flux temps réel des annonces publiées et actives (marketplace), source
/// unique désormais pour tout écran qui liste les annonces en direct
/// (remplace l'ancienne pile `AnnoncesCrudRepository`/`activeAnnoncesStreamProvider`).
final activeAnnoncesProvider = StreamProvider.autoDispose<List<Annonce>>((ref) {
  final repo = ref.watch(annonceRepositoryProvider);
  return repo.watchActiveAnnonces();
});

final sellerAnnoncesProvider = FutureProvider.autoDispose
    .family<List<Annonce>, String>((ref, sellerId) async {
      final repo = ref.watch(annonceRepositoryProvider);
      return repo.getSellerAnnonces(sellerId);
    });

final annonceByIdProvider = FutureProvider.autoDispose.family<Annonce?, String>(
  (ref, id) async {
    final repo = ref.watch(annonceRepositoryProvider);
    return repo.getAnnonceById(id);
  },
);

final createAnnonceProvider =
    StateNotifierProvider<CreateAnnonceNotifier, AsyncValue<Annonce?>>((ref) {
      final repo = ref.watch(annonceRepositoryProvider);
      return CreateAnnonceNotifier(repo);
    });

class CreateAnnonceNotifier extends StateNotifier<AsyncValue<Annonce?>> {
  CreateAnnonceNotifier(this._repository) : super(const AsyncValue.data(null));

  final AnnonceRepository _repository;

  Future<void> create(Annonce annonce, List<XFile> images) async {
    state = const AsyncValue.loading();
    try {
      final result = await _repository.createAnnonce(annonce, images);
      state = AsyncValue.data(result);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> update(
    Annonce annonce, {
    List<XFile> newImages = const [],
  }) async {
    state = const AsyncValue.loading();
    try {
      final result = await _repository.updateAnnonce(
        annonce,
        newImages: newImages,
      );
      state = AsyncValue.data(result);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}
