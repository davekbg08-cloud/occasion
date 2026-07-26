import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gift_catalog_item.dart';
import '../models/gift_redemption.dart';
import '../models/loyalty_points.dart';
import '../providers/auth_provider.dart';
import '../providers/gift_catalog_provider.dart';
import '../providers/loyalty_points_provider.dart';

class LoyaltyPointsScreen extends ConsumerWidget {
  const LoyaltyPointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buyerId = ref.watch(authNotifierProvider).currentUser?.id ?? '';
    final pointsAsync = ref.watch(buyerLoyaltyPointsProvider(buyerId));
    final redemptionsAsync = ref.watch(buyerGiftRedemptionsProvider(buyerId));

    return Scaffold(
      appBar: AppBar(title: const Text('Mes points de fidélité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Vos soldes par vendeur',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          pointsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                const Text('Impossible de charger vos points.'),
            data: (points) {
              if (points.isEmpty) {
                return const Text(
                  'Vous n\'avez pas encore de points de fidélité. '
                  'Achetez chez un vendeur pour commencer à en gagner.',
                );
              }
              return Column(
                children: points
                    .map((p) => _SellerPointsCard(points: p))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Historique de vos demandes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          redemptionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                const Text('Impossible de charger l\'historique.'),
            data: (redemptions) {
              if (redemptions.isEmpty) {
                return const Text('Aucune demande d\'échange pour le moment.');
              }
              return Column(
                children: redemptions
                    .map((r) => _RedemptionTile(redemption: r))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SellerPointsCard extends ConsumerWidget {
  const _SellerPointsCard({required this.points});

  final BuyerLoyaltyPoints points;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellerName = ref.watch(sellerDisplayNameProvider(points.sellerId));
    final catalogAsync = ref.watch(activeGiftCatalogProvider(points.sellerId));

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.stars_outlined, color: Colors.amber),
        title: Text(sellerName.value ?? 'Vendeur'),
        subtitle: Text('${points.balance} points'),
        children: [
          catalogAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Catalogue indisponible.'),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Ce vendeur n\'a pas encore de cadeaux.'),
                );
              }
              return Column(
                children: items
                    .map(
                      (item) => _GiftItemTile(
                        item: item,
                        buyerBalance: points.balance,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GiftItemTile extends ConsumerStatefulWidget {
  const _GiftItemTile({required this.item, required this.buyerBalance});

  final GiftCatalogItem item;
  final int buyerBalance;

  @override
  ConsumerState<_GiftItemTile> createState() => _GiftItemTileState();
}

class _GiftItemTileState extends ConsumerState<_GiftItemTile> {
  bool _isSubmitting = false;

  Future<void> _redeem() async {
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(loyaltyServiceProvider)
          .requestGiftRedemption(widget.item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande d\'échange envoyée.')),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Impossible d\'envoyer la demande.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAfford = widget.buyerBalance >= widget.item.pointsCost;
    return ListTile(
      title: Text(widget.item.title),
      subtitle: Text('${widget.item.pointsCost} points'),
      trailing: FilledButton(
        onPressed: (!canAfford || _isSubmitting) ? null : _redeem,
        child: _isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Échanger'),
      ),
    );
  }
}

class _RedemptionTile extends StatelessWidget {
  const _RedemptionTile({required this.redemption});

  final GiftRedemption redemption;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(redemption.status)),
      title: Text(redemption.itemTitle),
      subtitle: Text(
        '${redemption.pointsCost} points · ${_labelFor(redemption.status)}',
      ),
    );
  }

  IconData _iconFor(GiftRedemptionStatus status) {
    switch (status) {
      case GiftRedemptionStatus.pending:
        return Icons.hourglass_top_outlined;
      case GiftRedemptionStatus.fulfilled:
        return Icons.check_circle_outline;
      case GiftRedemptionStatus.rejected:
        return Icons.cancel_outlined;
    }
  }

  String _labelFor(GiftRedemptionStatus status) {
    switch (status) {
      case GiftRedemptionStatus.pending:
        return 'En attente';
      case GiftRedemptionStatus.fulfilled:
        return 'Envoyé';
      case GiftRedemptionStatus.rejected:
        return 'Refusé (points remboursés)';
    }
  }
}
