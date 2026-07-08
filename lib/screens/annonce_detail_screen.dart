import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../annonce/providers/annonce_provider.dart';
import '../models/report.dart';
import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../widgets/fullscreen_image_viewer.dart';
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
    final cartCurrency = cart.isEmpty ? product.currency : cart.first.product.currency;
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

  @override
  Widget build(BuildContext context) {
    final annonceAsync = ref.watch(annonceByIdProvider(widget.annonceId));
    final currentUser = ref.watch(authNotifierProvider).currentUser;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('Annonce'),
      ),
      body: annonceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Impossible de charger cette annonce.')),
        data: (annonce) {
          if (annonce == null) {
            return const Center(child: Text('Cette annonce est introuvable.'));
          }

          final product = ProductModel(
            id: annonce.id,
            name: annonce.title,
            description: annonce.description,
            price: annonce.price,
            currency: annonce.currency,
            imageUrl: annonce.imageUrls.isEmpty ? null : annonce.imageUrls.first,
            imageUrls: annonce.imageUrls,
            sellerId: annonce.userId,
            sellerName: 'Vendeur',
            sellerPhone: annonce.phone,
            category: annonce.category,
          );

          final showBuyerActions =
              currentUser == null || currentUser.isBuyer;
          final canModerate = currentUser != null &&
              currentUser.id != annonce.userId;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: annonce.imageUrls.isEmpty
                      ? null
                      : () => FullscreenImageViewer.open(
                            context,
                            imageUrls: annonce.imageUrls,
                          ),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: annonce.imageUrls.isEmpty
                        ? Container(
                            color: Colors.grey[850],
                            child: const Center(
                              child: Icon(Icons.image_outlined, size: 64),
                            ),
                          )
                        : Image.network(
                            annonce.imageUrls.first,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              annonce.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          if (canModerate)
                            IconButton(
                              tooltip: 'Signaler ou bloquer',
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
                      const SizedBox(height: 8),
                      Text(
                        '${annonce.price.toInt()} ${annonce.currency}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(annonce.description),
                      const SizedBox(height: 12),
                      if (annonce.location != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 16),
                            const SizedBox(width: 4),
                            Text(annonce.location!),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(annonce.category),
                      ),
                      if (showBuyerActions) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _contactSeller(product),
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text('Contacter'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _addToCart(product),
                                icon: const Icon(
                                  Icons.shopping_cart_outlined,
                                ),
                                label: const Text('Ajouter'),
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
        },
      ),
    );
  }
}
