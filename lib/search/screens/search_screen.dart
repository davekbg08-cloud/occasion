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
          preferredSize: const Size.fromHeight(112),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Rechercher une annonce...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    ref.read(searchQueryProvider.notifier).state = value;
                  },
                ),
                const SizedBox(height: 8),
                _CityFilterField(
                  onChanged: (value) {
                    ref.read(searchFiltersProvider.notifier).update((state) {
                      final next = {...state};
                      if (value.trim().isEmpty) {
                        next.remove('city');
                      } else {
                        next['city'] = value.trim();
                      }
                      return next;
                    });
                  },
                ),
              ],
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
        error: (error, stackTrace) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Impossible de charger les annonces pour le moment.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _CityFilterField extends StatefulWidget {
  const _CityFilterField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_CityFilterField> createState() => _CityFilterFieldState();
}

class _CityFilterFieldState extends State<_CityFilterField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: 'Filtrer par ville/quartier...',
        prefixIcon: const Icon(Icons.place_outlined),
        border: const OutlineInputBorder(),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Retirer le filtre ville',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
      onChanged: (value) {
        widget.onChanged(value);
        setState(() {});
      },
    );
  }
}
