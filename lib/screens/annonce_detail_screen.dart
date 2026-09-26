import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../annonce/providers/annonce_provider.dart';
import '../l10n/app_language.dart';
import '../models/annonce.dart';
import '../models/report.dart';
import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import '../theme/app_theme.dart';
import '../utils/currencies.dart';
import '../utils/loyalty_points_estimate.dart';
import '../widgets/photo_carousel.dart';
import '../widgets/report_block_sheet.dart';

class AnnonceDetailScreen extends ConsumerStatefulWidget {
  const AnnonceDetailScreen({super.key, required this.annonceId});

  final String annonceId;

  @override
  ConsumerState<AnnonceDetailScreen> createState() =>
      _AnnonceDetailScreenState();
}

class _AnnonceDetailScreenState extends ConsumerState<AnnonceDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Best-effort : ne bloque jamais l'affichage si l'incrément échoue.
    ref
        .read(annonceRepositoryProvider)
        .incrementViews(widget.annonceId)
        .catchError((_) {});
  }

  void _addToCart(ProductModel product) {
    final added = ref.read(cartNotifierProvider.notifier).addToCart(product);
    final cart = ref.read(cartNotifierProvider);
    final cartCurrency = cart.isEmpty
        ? product.currency
        : cart.first.product.currency;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? '${product.name} ajouté au panier'
              : 'Ton panier contient déjà des articles en $cartCurrency. '
                    'Vide-le d\'abord pour ajouter un article en ${product.currency}.',
        ),
      ),
    );
  }

  void _contactSeller(ProductModel product) {
    final currentUser = ref.read(authNotifierProvider).currentUser;
    if (currentUser == null) {
      context.push('/auth');
      return;
    }
    final sellerId = product.sellerId;
    if (sellerId == null || sellerId.isEmpty || sellerId == currentUser.id) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Conversation indisponible.'))));
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

  @override
  Widget build(BuildContext context) {
    final annonceAsync = ref.watch(annonceByIdProvider(widget.annonceId));
    final currentUser = ref.watch(authNotifierProvider).currentUser;

    final loadedAnnonce = annonceAsync.valueOrNull;
    final showStickyActions =
        loadedAnnonce != null && (currentUser == null || currentUser.isBuyer);

    return Scaffold(
      bottomNavigationBar: showStickyActions
          ? _DetailActions(
              annonce: loadedAnnonce,
              onContact: _contactSeller,
              onAddToCart: _addToCart,
            )
          : null,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Text(tr('Annonce')),
      ),
      body: annonceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(tr('Impossible de charger cette annonce.'))),
        data: (annonce) {
          if (annonce == null) {
            return Center(child: Text(tr('Cette annonce est introuvable.')));
          }

          final productAsync = ref.watch(productFromAnnonceProvider(annonce));

          final showBuyerActions = currentUser == null || currentUser.isBuyer;
          final canModerate =
              currentUser != null && currentUser.id != annonce.userId;
          final loyaltyPoints = estimateLoyaltyPoints(
            annonce.price,
            annonce.currency,
          );

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhotoCarousel(imageUrls: annonce.imageUrls),
                if (annonce.saleState != 'available')
                  _SaleStateBanner(saleState: annonce.saleState),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatPrice(annonce.price, annonce.currency),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.price,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              annonce.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          if (canModerate)
                            IconButton(
                              tooltip: tr('Signaler ou bloquer'),
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => showReportOrBlockSheet(
                                context,
                                currentUserId: currentUser.id,
                                targetUserId: annonce.userId,
                                targetUserName: 'Vendeur',
                                targetType: ReportTargetType.product,
                                contentId: annonce.id,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (annonce.location != null &&
                              annonce.location!.trim().isNotEmpty)
                            _InfoPill(
                              icon: Icons.place_outlined,
                              label: annonce.location!,
                            ),
                          if (annonce.category.trim().isNotEmpty)
                            _InfoPill(
                              icon: Icons.sell_outlined,
                              label: annonce.category,
                            ),
                          if (showBuyerActions && loyaltyPoints > 0)
                            _InfoPill(
                              icon: Icons.card_giftcard,
                              label: '+$loyaltyPoints points',
                              highlighted: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        tr('Description'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        annonce.description,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      productAsync.maybeWhen(
                        data: (product) => product.sellerId == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: _SellerCard(product: product),
                              ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                      _PriceHistorySection(annonceId: annonce.id),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.primary : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

/// Carte vendeur : met la personne en avant pour inspirer confiance.
class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final name = (product.sellerName ?? 'Vendeur').trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final since = product.sellerCreatedAt;
    final details = <String>[
      if (product.isSellerVerified) 'Vendeur vérifié',
      if (product.isSellerPhoneVerified) 'Téléphone vérifié',
      if (since != null && since.millisecondsSinceEpoch > 0)
        'Membre depuis ${DateFormat('MM/yyyy').format(since)}',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.push('/seller/${product.sellerId}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (product.isSellerVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            color: AppColors.primary,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details.join(' · '),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                tr('Boutique'),
                style: TextStyle(color: AppColors.primary, fontSize: 13),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Actions fixées en bas de l'écran : toujours à portée de pouce, même en
/// lisant une longue description.
class _DetailActions extends ConsumerWidget {
  const _DetailActions({
    required this.annonce,
    required this.onContact,
    required this.onAddToCart,
  });

  final Annonce annonce;
  final void Function(ProductModel product) onContact;
  final void Function(ProductModel product) onAddToCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productFromAnnonceProvider(annonce));
    final product = productAsync.valueOrNull;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: product == null ? null : () => onContact(product),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(tr('Contacter')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: product == null ? null : () => onAddToCart(product),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: Text(tr('Au panier')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceHistorySection extends ConsumerWidget {
  const _PriceHistorySection({required this.annonceId});

  final String annonceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(priceHistoryProvider(annonceId));

    return historyAsync.maybeWhen(
      data: (entries) {
        if (entries.length < 2) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(tr('Historique des prix')),
            children: entries
                .map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      entry.isDecrease
                          ? Icons.trending_down
                          : Icons.trending_up,
                      color: entry.isDecrease ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      '${entry.oldPrice.toInt()} → ${entry.newPrice.toInt()} ${entry.currency}',
                    ),
                    subtitle: entry.changedAt == null
                        ? null
                        : Text(
                            DateFormat('dd/MM/yyyy').format(entry.changedAt!),
                          ),
                  ),
                )
                .toList(),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _SaleStateBanner extends StatelessWidget {
  const _SaleStateBanner({required this.saleState});

  final String saleState;

  @override
  Widget build(BuildContext context) {
    final isSold = saleState == 'sold';
    final color = isSold ? Colors.red : Colors.orange;
    final label = isSold ? 'Cette annonce est vendue' : 'En négociation';

    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
