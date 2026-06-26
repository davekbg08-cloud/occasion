import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../annonce/providers/annonce_provider.dart';
import '../../shared/models/annonce.dart';

export '../../annonce/providers/annonce_provider.dart'
    show searchQueryProvider, searchFiltersProvider;

final searchResultsProvider = FutureProvider.autoDispose<List<Annonce>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final filters = ref.watch(searchFiltersProvider);
  final repo = ref.watch(annonceRepositoryProvider);

  return repo.getAnnonces(
    search: query.trim().isEmpty ? null : query.trim(),
    category: filters['category'] as String?,
  );
});
