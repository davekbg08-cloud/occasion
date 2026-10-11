import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_language.dart';
import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/moderation_provider.dart';
import '../providers/product_provider.dart';
import '../search/providers/search_provider.dart';
import '../search/screens/search_screen.dart'
    show CityFilterField, saveCurrentSearch, setCityFilter;
import '../theme/app_theme.dart';
import '../widgets/occasion_logo.dart';
import '../widgets/product_card.dart';
import '../widgets/status_strip.dart';
import '../theme/motion.dart';

class ProductListScreen extends ConsumerWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productNotifierProvider);
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    final isBuyer = currentUser?.isBuyer == true;

    final blockedIds = currentUser == null
        ? const <String>{}
        : ref
              .watch(blockedUserIdsProvider(currentUser.id))
              .maybeWhen(data: (ids) => ids, orElse: () => const <String>{});
    final searching = ref.watch(homeSearchActiveProvider);
    final cartCount = ref.watch(
      cartNotifierProvider.select(
        (items) => items.fold(0, (sum, item) => sum + item.quantity),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OccasionEmblem(size: 32),
            SizedBox(width: 10),
            Text('Occasion'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('Notifications'),
            icon: const Icon(Icons.notifications_outlined, size: 28),
            onPressed: () => context.push('/notifications'),
          ),
          if (isBuyer)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined, size: 28),
                  onPressed: () => context.push('/cart'),
                ),
                if (cartCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Center(
                        child: Text(
                          cartCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          _HomeSearchBar(
            suggestions: productsAsync.maybeWhen(
              data: (products) => products.map((p) => p.name),
              orElse: () => const <String>[],
            ),
          ),
          if (searching)
            Expanded(child: _HomeSearchResults(blockedIds: blockedIds))
          else ...[
            StatusStrip(blockedIds: blockedIds),
            Expanded(child: _productsBody(ref, productsAsync, blockedIds)),
          ],
        ],
      ),
    );
  }

  Widget _productsBody(
    WidgetRef ref,
    AsyncValue<List<ProductModel>> productsAsync,
    Set<String> blockedIds,
  ) {
    return productsAsync.when(
      data: (products) {
        final visibleProducts = products
            .where(
              (product) =>
                  product.sellerId == null ||
                  !blockedIds.contains(product.sellerId),
            )
            .toList();

        if (visibleProducts.isEmpty) {
          return Center(child: Text(tr('Aucun contenu pour le moment.')));
        }

        return RefreshIndicator(
          onRefresh: () => ref.refresh(productNotifierProvider.future),
          child: _ResponsiveProductGrid(products: visibleProducts),
        );
      },
      loading: () => const _ProductListSkeleton(),
      error: (error, stack) => Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            tr('Impossible de charger les produits pour le moment.'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Grille responsive : 2 colonnes sur téléphone, 3 entre 600 et 999px,
/// 4 à partir de 1000px (largeur max, contenu centré). Utilise
/// [MasonryGridView] plutôt qu'un `GridView` à ratio fixe car la hauteur des
/// cartes varie (titre sur 1 ou 2 lignes) — un ratio fixe couperait ou
/// laisserait déborder certaines cartes.
class _ResponsiveProductGrid extends StatelessWidget {
  const _ResponsiveProductGrid({required this.products});

  final List<ProductModel> products;

  static const _maxContentWidth = 1400.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 1000 ? 4 : (width >= 600 ? 3 : 2);
    final bottomSafePadding =
        MediaQuery.paddingOf(context).bottom + kBottomNavigationBarHeight;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: MasonryGridView.count(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomSafePadding),
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: products.length,
          itemBuilder: (context, index) => AppearOnce(
            key: ValueKey(products[index].id),
            order: index,
            child: ProductCard(product: products[index]),
          ),
        ),
      ),
    );
  }
}

/// Mode recherche de l'accueil : la barre du haut est la recherche (plus
/// d'onglet « Chercher » séparé) ; les résultats remplacent les statuts et
/// la grille tant qu'il est actif.
final homeSearchActiveProvider = StateProvider<bool>((ref) => false);

/// Titres d'annonces réelles proposés dans la barre (défilement) et en
/// suggestions, sans doublons.
List<String> homeSearchSuggestions(Iterable<String> names, {int max = 8}) {
  final seen = <String>{};
  final hints = <String>[];
  for (final name in names) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
    hints.add(trimmed);
    if (hints.length == max) break;
  }
  return hints.isEmpty
      ? const ['téléphone', 'chaussures', 'ordinateur']
      : hints;
}

/// Barre de recherche de l'accueil. Tant qu'elle est vide, le texte d'aide
/// fait défiler des titres d'annonces réelles (glissement vers le haut) ;
/// on tape directement dedans, les résultats s'affichent dessous. La loupe
/// orange lance la recherche (le titre affiché si rien n'est tapé), la
/// flèche retour quitte la recherche.
class _HomeSearchBar extends ConsumerStatefulWidget {
  const _HomeSearchBar({required this.suggestions});

  final Iterable<String> suggestions;

  @override
  ConsumerState<_HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends ConsumerState<_HomeSearchBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) _setActive(true);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setActive(bool active) {
    final notifier = ref.read(homeSearchActiveProvider.notifier);
    if (notifier.state != active) notifier.state = active;
  }

  void _setQuery(String query) {
    _debounce?.cancel();
    ref.read(searchQueryProvider.notifier).state = query.trim();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    // Pas une requête par touche : on attend une courte pause de frappe.
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _setQuery(value),
    );
  }

  /// Recherche [text], ou le titre affiché dans la barre si rien n'est tapé.
  void _submit([String? text]) {
    final hints = homeSearchSuggestions(widget.suggestions);
    var query = (text ?? _controller.text).trim();
    if (query.isEmpty) query = hints[_shown.clamp(0, hints.length - 1)];
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _setQuery(query);
    _setActive(true);
    _focus.unfocus();
    setState(() {});
  }

  void _exit() {
    _controller.clear();
    _setQuery('');
    setCityFilter(ref, '');
    _setActive(false);
    _focus.unfocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Une suggestion touchée sous la barre remplit le champ.
    ref.listen<String?>(_pickedSuggestionProvider, (previous, next) {
      if (next == null) return;
      ref.read(_pickedSuggestionProvider.notifier).state = null;
      _submit(next);
    });
    final active = ref.watch(homeSearchActiveProvider);
    final hints = homeSearchSuggestions(widget.suggestions);
    final empty = _controller.text.isEmpty;
    return PopScope(
      canPop: !active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _exit();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Material(
          color: AppColors.surface,
          shape: const StadiumBorder(
            side: BorderSide(color: AppColors.price, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                if (active)
                  IconButton(
                    tooltip: tr('Retour'),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _exit,
                  )
                else ...[
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      if (empty)
                        IgnorePointer(
                          child: ExcludeSemantics(
                            child: RollingSwitcher(
                              key: ValueKey(hints.length),
                              onChanged: (index) => _shown = index,
                              items: [
                                for (final hint in hints)
                                  Text(
                                    hint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 15,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Semantics(
                        label: tr('Rechercher une annonce...'),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          textInputAction: TextInputAction.search,
                          onChanged: _onChanged,
                          onSubmitted: (_) => _submit(),
                          style: const TextStyle(fontSize: 15),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!empty)
                  IconButton(
                    tooltip: tr('Effacer'),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      _controller.clear();
                      _setQuery('');
                      _focus.requestFocus();
                      setState(() {});
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Material(
                    color: AppColors.price,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => _submit(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Center(
                          widthFactor: 1,
                          child: Icon(
                            Icons.search,
                            color: Colors.white,
                            semanticLabel: tr('Rechercher'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Suggestion touchée dans les résultats, transmise à la barre.
final _pickedSuggestionProvider = StateProvider<String?>((ref) => null);

/// Résultats de la recherche de l'accueil : filtre ville, enregistrer la
/// recherche (alerte), mes alertes, puis la même grille que l'accueil.
class _HomeSearchResults extends ConsumerWidget {
  const _HomeSearchResults({required this.blockedIds});

  final Set<String> blockedIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final city = ref.watch(searchFiltersProvider)['city'] as String? ?? '';
    final idle = query.trim().isEmpty && city.trim().isEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: CityFilterField(
                  dense: true,
                  onChanged: (value) => setCityFilter(ref, value),
                ),
              ),
              IconButton(
                tooltip: tr('Enregistrer cette recherche'),
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: () => saveCurrentSearch(context, ref),
              ),
              IconButton(
                tooltip: tr('Mes alertes de recherche'),
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: () => context.push('/search-alerts'),
              ),
            ],
          ),
        ),
        Expanded(
          child: idle
              ? _SearchSuggestions(
                  suggestions: homeSearchSuggestions(
                    ref
                            .watch(productNotifierProvider)
                            .valueOrNull
                            ?.map((p) => p.name) ??
                        const <String>[],
                  ),
                )
              : ref
                    .watch(searchProductsProvider)
                    .when(
                      data: (products) {
                        final visible = products
                            .where(
                              (p) =>
                                  p.sellerId == null ||
                                  !blockedIds.contains(p.sellerId),
                            )
                            .toList();
                        if (visible.isEmpty) {
                          return Center(
                            child: Text(tr('Aucune annonce trouvée')),
                          );
                        }
                        return RefreshIndicator(
                          onRefresh: () =>
                              ref.refresh(searchResultsProvider.future),
                          child: _ResponsiveProductGrid(products: visible),
                        );
                      },
                      loading: () => const _ProductListSkeleton(),
                      error: (error, stackTrace) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            tr(
                              'Impossible de charger les annonces pour le moment.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _SearchSuggestions extends ConsumerWidget {
  const _SearchSuggestions({required this.suggestions});

  final List<String> suggestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          tr('Suggestions'),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in suggestions)
              ActionChip(
                avatar: const Icon(Icons.search, size: 16),
                label: Text(suggestion),
                onPressed: () =>
                    ref.read(_pickedSuggestionProvider.notifier).state =
                        suggestion,
              ),
          ],
        ),
      ],
    );
  }
}

/// Squelette de la grille pendant le premier chargement : la forme des
/// cartes est déjà là, au lieu d'une roue au milieu d'un écran vide.
class _ProductListSkeleton extends StatelessWidget {
  const _ProductListSkeleton();

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(12));
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.68,
      ),
      itemBuilder: (context, _) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: SkeletonPulse(borderRadius: radius),
          ),
          SizedBox(height: 10),
          SkeletonPulse(height: 14, borderRadius: radius),
          SizedBox(height: 8),
          SkeletonPulse(width: 80, height: 18, borderRadius: radius),
        ],
      ),
    );
  }
}
