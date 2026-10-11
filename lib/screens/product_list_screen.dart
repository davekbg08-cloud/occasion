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

/// Grille responsive : 1 colonne sous 600px, 2 colonnes entre 600 et 999px,
/// 3 colonnes à partir de 1000px (largeur max, contenu centré). Utilise
/// [MasonryGridView] plutôt qu'un `GridView` à ratio fixe car la hauteur des
/// cartes varie (badges vendeur optionnels, description sur 1 ou 2 lignes) —
/// un ratio fixe couperait ou laisserait déborder certaines cartes.
class _ResponsiveProductGrid extends StatelessWidget {
  const _ResponsiveProductGrid({required this.products});

  final List<ProductModel> products;

  static const _maxContentWidth = 1400.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 1000 ? 3 : (width >= 600 ? 2 : 1);
    final bottomSafePadding =
        MediaQuery.paddingOf(context).bottom + kBottomNavigationBarHeight;

    final grid = MasonryGridView.count(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomSafePadding),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      itemCount: products.length,
      itemBuilder: (context, index) => AppearOnce(
        key: ValueKey(products[index].id),
        order: index,
        child: ProductCard(product: products[index]),
      ),
    );

    if (crossAxisCount == 1) return grid;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: grid,
      ),
    );
  }
}

/// Squelette de la liste pendant le premier chargement : la forme des
/// cartes est déjà là, au lieu d'une roue au milieu d'un écran vide.
class _ProductListSkeleton extends StatelessWidget {
  const _ProductListSkeleton();

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(16));
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, _) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonPulse(height: 220, borderRadius: radius),
          SizedBox(height: 12),
          SkeletonPulse(width: 90, height: 18, borderRadius: radius),
          SizedBox(height: 8),
          SkeletonPulse(width: 200, height: 16, borderRadius: radius),
        ],
      ),
    );
  }
}
