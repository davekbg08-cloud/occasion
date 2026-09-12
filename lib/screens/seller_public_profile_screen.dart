import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/review.dart';
import '../providers/product_provider.dart';
import '../providers/review_provider.dart';

class SellerPublicProfileScreen extends ConsumerWidget {
  const SellerPublicProfileScreen({super.key, required this.sellerId});

  final String sellerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellerAsync = ref.watch(sellerProfileProvider(sellerId));
    final reviewsAsync = ref.watch(reviewsForUserProvider(sellerId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('Profil du vendeur'),
      ),
      body: sellerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(
          child: Text('Impossible de charger ce profil pour le moment.'),
        ),
        data: (seller) {
          if (seller == null) {
            return const Center(child: Text('Vendeur introuvable.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: seller.profileImageUrl == null
                    ? null
                    : NetworkImage(seller.profileImageUrl!),
                child: seller.profileImageUrl == null
                    ? const Icon(Icons.person, size: 36)
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    seller.name.isEmpty ? 'Vendeur' : seller.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (seller.isVerifiedSeller) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified, color: Colors.blue, size: 20),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatChip(
                    icon: Icons.star,
                    label: seller.ratingCount == 0
                        ? 'Pas encore d\'avis'
                        : '${seller.averageRating.toStringAsFixed(1)} (${seller.ratingCount})',
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    icon: Icons.shopping_bag_outlined,
                    label: '${seller.totalSales} vente(s)',
                    color: Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Avis récents',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              reviewsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => const Text(
                  "Impossible de charger les avis pour le moment.",
                ),
                data: (reviews) {
                  if (reviews.isEmpty) {
                    return const Text('Aucun avis pour le moment.');
                  }
                  return Column(
                    children: reviews
                        .map((r) => _ReviewTile(review: r))
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ...List.generate(
                  5,
                  (index) => Icon(
                    index < review.rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  ),
                ),
                const Spacer(),
                if (review.createdAt != null)
                  Text(
                    DateFormat('dd/MM/yyyy').format(review.createdAt!),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
              ],
            ),
            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(review.comment),
            ],
          ],
        ),
      ),
    );
  }
}
