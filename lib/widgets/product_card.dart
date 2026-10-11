import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../l10n/app_language.dart';
import '../models/report.dart';
import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../utils/currencies.dart';
import '../utils/loyalty_points_estimate.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'occasion_image.dart';
import 'report_block_sheet.dart';

class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product});

  final ProductModel product;

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

  void _openDetail(BuildContext context) =>
      context.push('/annonce/${product.id}');

  /// Infos qui défilent sous le prix (une ligne, l'une après l'autre) : la
  /// carte reste compacte en deux colonnes sans rien perdre.
  List<Widget> _infoLines({required bool forBuyer, required int points}) {
    return [
      if (product.isSellerVerified)
        _InfoLine(
          icon: Icons.verified,
          label: tr('Vendeur vérifié'),
          color: AppColors.primary,
        ),
      if (product.isSellerPhoneVerified)
        _InfoLine(
          icon: Icons.phone_android_outlined,
          label: tr('Téléphone vérifié'),
        ),
      _InfoLine(
        icon: Icons.shield_outlined,
        label: tr('Payez après vérification'),
      ),
      if (forBuyer && points > 0)
        _InfoLine(
          icon: Icons.card_giftcard,
          label: '+$points points',
          color: AppColors.price,
        ),
      if (product.sellerName != null)
        _InfoLine(icon: Icons.storefront_outlined, label: _sellerLine(product)),
      if (product.category != null)
        _InfoLine(icon: Icons.sell_outlined, label: product.category!),
    ];
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
    final loyaltyPoints = estimateLoyaltyPoints(
      product.price,
      product.currency,
    );
    final photos = product.imageUrls.isNotEmpty
        ? product.imageUrls
        : [?product.imageUrl];

    // Carte compacte (grille à deux colonnes) : photo carrée, titre, prix
    // et une ligne d'infos qui défile. Tapoter ouvre la fiche, où se
    // trouvent toutes les actions (contacter, panier, signaler...).
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OccasionImage.thumbnail(
                    photos.isEmpty ? null : photos.first,
                    width: double.infinity,
                    height: double.infinity,
                    semanticsLabel: product.name,
                  ),
                  if (product.saleState != 'available')
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _SaleStateBadge(saleState: product.saleState),
                    ),
                  if (photos.length > 1)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _PhotoCountBadge(count: photos.length),
                    ),
                  if (canModerate)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black45,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: tr('Signaler ou bloquer'),
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          color: Colors.white,
                          onPressed: () => showReportOrBlockSheet(
                            context,
                            currentUserId: currentUserId,
                            targetUserId: product.sellerId!,
                            targetUserName: product.sellerName ?? 'Vendeur',
                            targetType: ReportTargetType.product,
                            contentId: product.id,
                          ),
                          icon: const Icon(Icons.more_vert),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatPrice(product.price, product.currency),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.price,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      if (showBuyerActions && product.saleState != 'sold')
                        IconButton(
                          tooltip: tr('Ajouter au panier'),
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          color: AppColors.primary,
                          onPressed: () => _addToCart(context, ref),
                          icon: const Icon(Icons.add_shopping_cart),
                        ),
                    ],
                  ),
                  SizedBox(
                    height: 18,
                    child: RollingSwitcher(
                      initialDelay: Duration(
                        milliseconds: product.id.hashCode.abs() % 2500,
                      ),
                      items: _infoLines(
                        forBuyer: showBuyerActions,
                        points: loyaltyPoints,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sellerLine(ProductModel product) {
    final sellerName = product.sellerName ?? 'Vendeur';
    final createdAt = product.sellerCreatedAt;
    if (createdAt == null || createdAt.millisecondsSinceEpoch == 0) {
      return sellerName;
    }
    return '$sellerName · ${tr('depuis')} ${DateFormat('MM/yyyy').format(createdAt)}';
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }
}

class _PhotoCountBadge extends StatelessWidget {
  const _PhotoCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SaleStateBadge extends StatelessWidget {
  const _SaleStateBadge({required this.saleState});

  final String saleState;

  @override
  Widget build(BuildContext context) {
    final isSold = saleState == 'sold';
    final color = isSold ? Colors.red : Colors.orange;
    final label = isSold ? 'Vendu' : 'En négociation';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
