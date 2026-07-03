import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/moderation_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/occasion_logo.dart';
import '../widgets/product_card.dart';

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
            OccasionLogo(size: 34),
            SizedBox(width: 8),
            Text('Nos Produits'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 28),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline, size: 28),
            onPressed: () => context.push('/profile'),
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
      body: productsAsync.when(
        data: (products) {
          final visibleProducts = products
              .where(
                (product) =>
                    product.sellerId == null ||
                    !blockedIds.contains(product.sellerId),
              )
              .toList();

          if (visibleProducts.isEmpty) {
            return const Center(child: Text('Aucun contenu pour le moment.'));
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(productNotifierProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: visibleProducts.length,
              itemBuilder: (context, index) {
                return ProductCard(product: visibleProducts[index]);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Impossible de charger les produits pour le moment.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
