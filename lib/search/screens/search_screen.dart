import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_provider.dart';
import '../../annonce/presentation/widgets/annonce_card.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechercher'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher une annonce...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                ref.read(searchQueryProvider.notifier).state = value;
              },
            ),
          ),
        ),
      ),
      body: resultsAsync.when(
        data: (annonces) {
          if (annonces.isEmpty) {
            return const Center(child: Text('Aucune annonce trouvée'));
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(searchResultsProvider.future),
            child: ListView.builder(
              itemCount: annonces.length,
              itemBuilder: (context, index) {
                return AnnonceCard(annonce: annonces[index]);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Erreur : $error')),
      ),
    );
  }
}
