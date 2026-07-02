import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../annonce/providers/annonce_provider.dart';
import '../models/annonce.dart';
import '../providers/auth_provider.dart';

class SellerDashboardScreen extends ConsumerWidget {
  const SellerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).currentUser;
    if (user == null || !user.isSeller) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final annoncesAsync = ref.watch(sellerAnnoncesProvider(user.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Tableau de bord vendeur')),
      body: annoncesAsync.when(
        data: (annonces) => _DashboardContent(
          annonces: annonces,
          onRefresh: () async {
            ref.invalidate(sellerAnnoncesProvider(user.id));
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _DashboardError(),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.annonces, required this.onRefresh});

  final List<Annonce> annonces;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final active = annonces.where((annonce) => annonce.isActive).length;
    final pending = annonces.length - active;
    final views = annonces.fold<int>(0, (sum, annonce) => sum + annonce.views);
    final messages = annonces.fold<int>(
      0,
      (sum, annonce) => sum + annonce.messagesCount,
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
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
              _MetricCard(
                icon: Icons.inventory_2_outlined,
                label: 'Annonces',
                value: '${annonces.length}',
              ),
              _MetricCard(
                icon: Icons.public,
                label: 'En ligne',
                value: '$active',
              ),
              _MetricCard(
                icon: Icons.visibility_outlined,
                label: 'Vues',
                value: '$views',
              ),
              _MetricCard(
                icon: Icons.mark_unread_chat_alt_outlined,
                label: 'Messages',
                value: '$messages',
              ),
              _MetricCard(
                icon: Icons.pending_actions_outlined,
                label: 'En attente',
                value: '$pending',
              ),
              const _MetricCard(
                icon: Icons.query_stats,
                label: 'Statistiques',
                value: '--',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Gestion vendeur',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _DashboardAction(
            icon: Icons.list_alt_outlined,
            title: 'Mes annonces',
            route: '/my-listings',
          ),
          _DashboardAction(
            icon: Icons.add_box_outlined,
            title: 'Publier une annonce',
            route: '/publish-product',
          ),
          _DashboardAction(
            icon: Icons.chat_bubble_outline,
            title: 'Messages acheteurs',
            route: '/seller-messages',
          ),
          _DashboardAction(
            icon: Icons.bar_chart_outlined,
            title: 'Statistiques',
            route: '/seller-statistics',
          ),
          _DashboardAction(
            icon: Icons.card_membership_outlined,
            title: 'Abonnement vendeur',
            route: '/subscription',
          ),
          _DashboardAction(
            icon: Icons.storefront_outlined,
            title: 'Profil vendeur',
            route: '/profile',
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.blue),
            const Spacer(),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }
}

class _DashboardAction extends StatelessWidget {
  const _DashboardAction({
    required this.icon,
    required this.title,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => context.push(route),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "Impossible de charger le tableau de bord vendeur.",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
