import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/report.dart';
import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import 'report_block_sheet.dart';

class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product});

  final ProductModel product;

  void _openPrivateMessage(BuildContext context, WidgetRef ref) {
    final currentUser = ref.read(authNotifierProvider).currentUser;
    if (currentUser == null) {
      context.push('/auth');
      return;
    }

    final sellerId = product.sellerId;
    if (sellerId == null || sellerId.isEmpty || sellerId == currentUser.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversation indisponible.')),
      );
      return;
    }

    context.push(
      '/open-chat',
      extra: {
        'sellerId': sellerId,
        'sellerName': product.sellerName ?? 'Vendeur',
        'buyerId': currentUser.id,
        'buyerName': currentUser.name,
        'listingId': product.id,
        'listingTitle': product.name,
      },
    );
  }

  bool _addToCart(BuildContext context, WidgetRef ref) {
    final added = ref.read(cartNotifierProvider.notifier).addToCart(product);
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ton panier contient déjà des articles en ${_cartCurrency(ref)}. '
            'Vide-le d\'abord pour ajouter un article en ${product.currency}.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} ajouté au panier'),
        duration: const Duration(seconds: 2),
      ),
    );
    return true;
  }

  String _cartCurrency(WidgetRef ref) {
    final cart = ref.read(cartNotifierProvider);
    return cart.isEmpty ? product.currency : cart.first.product.currency;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    final currentUserId = currentUser?.id;
    final showBuyerActions = currentUser == null || currentUser.isBuyer;
    final canModerate =
        currentUserId != null &&
        product.sellerId != null &&
        currentUserId != product.sellerId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProductImage(
            imageUrl: product.imageUrl,
            annonceId: product.id,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (product.isSellerVerified)
                      const Tooltip(
                        message: 'Vendeur vérifié',
                        child: Icon(
                          Icons.verified,
                          color: Colors.blue,
                          size: 16,
                        ),
                      ),
                    if (canModerate)
                      IconButton(
                        tooltip: 'Signaler ou bloquer',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => showReportOrBlockSheet(
                          context,
                          currentUserId: currentUserId,
                          targetUserId: product.sellerId!,
                          targetUserName: product.sellerName ?? 'Vendeur',
                          targetType: ReportTargetType.product,
                          contentId: product.id,
                        ),
                        icon: const Icon(Icons.more_vert, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  product.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  '${product.price.toInt()} ${product.currency}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
                if (product.sellerName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _sellerLine(product),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (product.isSellerPhoneVerified)
                      const _TrustChip(
                        icon: Icons.phone_android_outlined,
                        label: 'Téléphone vérifié',
                      ),
                    if (product.isSellerVerified)
                      const _TrustChip(
                        icon: Icons.verified_user_outlined,
                        label: 'Vendeur vérifié',
                      ),
                    const _TrustChip(
                      icon: Icons.shield_outlined,
                      label: 'Payez après vérification',
                    ),
                  ],
                ),
                if (product.category != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      product.category!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                  ),
                ],
                if (showBuyerActions) ...[
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _openPrivateMessage(context, ref),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                              ),
                              label: const Text('Contacter'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _addToCart(context, ref),
                              icon: const Icon(
                                Icons.shopping_cart_outlined,
                                size: 18,
                              ),
                              label: const Text('Ajouter'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            if (_addToCart(context, ref)) {
                              context.push('/cart');
                            }
                          },
                          icon: const Icon(
                            Icons.shopping_bag_outlined,
                            size: 18,
                          ),
                          label: const Text('Acheter'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sellerLine(ProductModel product) {
    final sellerName = product.sellerName ?? 'Vendeur';
    final createdAt = product.sellerCreatedAt;
    if (createdAt == null || createdAt.millisecondsSinceEpoch == 0) {
      return sellerName;
    }
    return '$sellerName - inscrit depuis ${DateFormat('MM/yyyy').format(createdAt)}';
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl, required this.annonceId});

  final String? imageUrl;
  final String annonceId;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return GestureDetector(
      onTap: () => context.push('/annonce/$annonceId'),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: url == null || url.isEmpty
            ? Container(
                color: Colors.grey[300],
                child: const Center(
                  child: Icon(Icons.image_outlined, size: 48),
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Colors.grey[300],
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[300],
                  child: const Center(
                    child: Icon(Icons.broken_image_outlined, size: 48),
                  ),
                ),
              ),
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
