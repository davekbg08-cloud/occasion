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
          StatusStrip(blockedIds: blockedIds),
          Expanded(child: _productsBody(ref, productsAsync, blockedIds)),
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

/// Barre de recherche de l'accueil : le texte d'aide fait défiler des
/// titres d'annonces réelles (glissement vers le haut). Tapoter la barre
/// ouvre la recherche ; le bouton loupe cherche directement le titre
/// affiché.
class _HomeSearchBar extends ConsumerStatefulWidget {
  const _HomeSearchBar({required this.suggestions});

  final Iterable<String> suggestions;

  @override
  ConsumerState<_HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends ConsumerState<_HomeSearchBar> {
  static const _fallback = ['téléphone', 'chaussures', 'ordinateur'];

  int _shown = 0;

  List<String> get _hints {
    final seen = <String>{};
    final hints = <String>[];
    for (final name in widget.suggestions) {
      final trimmed = name.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
      hints.add(trimmed);
      if (hints.length == 8) break;
    }
    return hints.isEmpty ? _fallback : hints;
  }

  Future<void> _openSearch(String query) async {
    ref.read(searchQueryProvider.notifier).state = query;
    await context.push('/search');
    if (!mounted) return;
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final hints = _hints;
    final shown = hints[_shown.clamp(0, hints.length - 1)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: AppColors.surface,
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.price, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openSearch(''),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(
                  Icons.search,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    label: tr('Rechercher une annonce...'),
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
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Material(
                    color: AppColors.price,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => _openSearch(shown),
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
