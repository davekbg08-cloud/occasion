import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  void _addToCart(BuildContext context, WidgetRef ref) {
    ref.read(cartNotifierProvider.notifier).addToCart(product);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} ajouté au panier'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authNotifierProvider).currentUser;
    final currentUserId = currentUser?.id;
    final canModerate =
        currentUserId != null &&
        product.sellerId != null &&
        currentUserId != product.sellerId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: product.imageUrl == null
                      ? null
                      : NetworkImage(product.imageUrl!),
                  child: product.imageUrl == null
                      ? const Icon(Icons.image_outlined)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
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
                        '${product.price.toInt()} FCFA',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 14,
                        ),
                      ),
                      if (product.sellerName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          product.sellerName!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
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
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openPrivateMessage(context, ref),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Contacter'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
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
                      _addToCart(context, ref);
                      context.push('/cart');
                    },
                    icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                    label: const Text('Acheter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
