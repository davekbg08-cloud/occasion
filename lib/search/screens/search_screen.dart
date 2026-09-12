import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/search_provider.dart';
import '../../annonce/presentation/widgets/annonce_card.dart';
import '../../providers/auth_provider.dart';
import '../../providers/search_alert_provider.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  Future<void> _saveSearch(BuildContext context, WidgetRef ref) async {
    final userId = ref.read(authNotifierProvider).currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connecte-toi pour enregistrer une recherche.'),
        ),
      );
      return;
    }
    final query = ref.read(searchQueryProvider);
    final filters = ref.read(searchFiltersProvider);
    try {
      await ref
          .read(searchAlertServiceProvider)
          .create(
            userId: userId,
            keyword: query,
            city: filters['city'] as String? ?? '',
            category: filters['category'] as String? ?? '',
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recherche enregistrée. Tu seras notifié des nouvelles annonces correspondantes.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Échec de l'enregistrement. Réessaie.")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final filters = ref.watch(searchFiltersProvider);
    final hasActiveSearch =
        query.trim().isNotEmpty ||
        (filters['city'] as String? ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechercher'),
        actions: [
          IconButton(
            tooltip: 'Enregistrer cette recherche',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: hasActiveSearch ? () => _saveSearch(context, ref) : null,
          ),
          IconButton(
            tooltip: 'Mes alertes de recherche',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () => context.push('/search-alerts'),
          ),
        ],
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
