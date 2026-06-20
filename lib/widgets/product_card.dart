import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/product_model.dart';
import '../providers/cart_provider.dart';

class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product});

  final ProductModel product;

  Future<void> _openWhatsApp(BuildContext context) async {
    final phone = product.sellerPhone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro WhatsApp non disponible')),
      );
      return;
    }

    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    final fullNumber = digits.startsWith('243')
        ? digits
        : digits.startsWith('0')
        ? '243${digits.substring(1)}'
        : '243$digits';
    final message = Uri.encodeComponent(
      'Bonjour, je suis intéressé par votre article :\n'
      '${product.name}\n'
      '${product.price.toInt()} FCFA\n'
      'Est-il encore disponible ?',
    );
    final url = Uri.parse('https://wa.me/$fullNumber?text=$message');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir WhatsApp")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(context),
                    icon: const Icon(
                      Icons.chat_rounded,
                      color: Color(0xFF25D366),
                      size: 18,
                    ),
                    label: const Text(
                      'WhatsApp',
                      style: TextStyle(color: Color(0xFF25D366)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF25D366)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      ref
                          .read(cartNotifierProvider.notifier)
                          .addToCart(product);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${product.name} ajouté au panier'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text('Ajouter'),
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
