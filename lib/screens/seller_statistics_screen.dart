import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/seller_statistics.dart';
import '../providers/auth_provider.dart';
import '../providers/seller_statistics_provider.dart';

class SellerStatisticsScreen extends ConsumerWidget {
  const SellerStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellerId = ref.watch(authNotifierProvider).currentUser?.id ?? '';
    final statisticsAsync = ref.watch(sellerStatisticsProvider(sellerId));

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: statisticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Text('Impossible de charger les statistiques.'),
        ),
        data: (statistics) => _StatisticsContent(statistics: statistics),
      ),
    );
  }
}

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({required this.statistics});

  final SellerStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final revenueEntries = statistics.revenue.entries.toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width > 640 ? 4 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.3,
          children: [
            _StatCard(
              icon: Icons.visibility_outlined,
              label: 'Vues',
              value: '${statistics.totalViews}',
            ),
            _StatCard(
              icon: Icons.mark_unread_chat_alt_outlined,
              label: 'Messages',
              value: '${statistics.totalMessages}',
            ),
            _StatCard(
              icon: Icons.point_of_sale_outlined,
              label: 'Ventes',
              value: '${statistics.totalSales}',
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Revenu', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (revenueEntries.isEmpty)
          const Text('Aucune vente réglée pour le moment.')
        else
          Card(
            child: Column(
              children: revenueEntries
                  .map(
                    (entry) => ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(entry.key),
                      trailing: Text(
                        entry.value.toStringAsFixed(0),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
