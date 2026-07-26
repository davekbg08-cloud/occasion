import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/gift_redemption.dart';
import '../providers/auth_provider.dart';
import '../providers/loyalty_points_provider.dart';

class SellerGiftRedemptionsScreen extends ConsumerWidget {
  const SellerGiftRedemptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellerId = ref.watch(authNotifierProvider).currentUser?.id ?? '';
    final redemptionsAsync = ref.watch(sellerGiftRedemptionsProvider(sellerId));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/profile'),
          ),
          title: const Text('Demandes d\'échange'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'En attente'),
              Tab(text: 'Envoyés'),
              Tab(text: 'Refusés'),
            ],
          ),
        ),
        body: redemptionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              const Center(child: Text('Impossible de charger les demandes.')),
          data: (redemptions) => TabBarView(
            children: [
              _RedemptionsTab(
                redemptions: redemptions
                    .where((r) => r.status == GiftRedemptionStatus.pending)
                    .toList(),
                showActions: true,
              ),
              _RedemptionsTab(
                redemptions: redemptions
                    .where((r) => r.status == GiftRedemptionStatus.fulfilled)
                    .toList(),
                showActions: false,
              ),
              _RedemptionsTab(
                redemptions: redemptions
                    .where((r) => r.status == GiftRedemptionStatus.rejected)
                    .toList(),
                showActions: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RedemptionsTab extends ConsumerStatefulWidget {
  const _RedemptionsTab({required this.redemptions, required this.showActions});

  final List<GiftRedemption> redemptions;
  final bool showActions;

  @override
  ConsumerState<_RedemptionsTab> createState() => _RedemptionsTabState();
}

class _RedemptionsTabState extends ConsumerState<_RedemptionsTab> {
  final Set<String> _processing = {};

  Future<void> _respond(String redemptionId, bool approve) async {
    setState(() => _processing.add(redemptionId));
    try {
      await ref
          .read(loyaltyServiceProvider)
          .respondToGiftRedemption(
            redemptionId: redemptionId,
            approve: approve,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Cadeau marqué envoyé.' : 'Demande refusée.'),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Échec. Réessaie.')),
      );
    } finally {
      if (mounted) setState(() => _processing.remove(redemptionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.redemptions.isEmpty) {
      return const Center(child: Text('Aucune demande.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: widget.redemptions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final redemption = widget.redemptions[index];
        final isBusy = _processing.contains(redemption.id);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  redemption.itemTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('${redemption.pointsCost} points'),
                if (widget.showActions) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isBusy
                              ? null
                              : () => _respond(redemption.id, false),
                          child: const Text('Refuser'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: isBusy
                              ? null
                              : () => _respond(redemption.id, true),
                          child: isBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Cadeau envoyé'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
