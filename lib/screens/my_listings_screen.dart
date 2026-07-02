import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../annonce/providers/annonce_provider.dart';
import '../models/annonce.dart';
import '../providers/auth_provider.dart';

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).currentUser;
    if (user == null || !user.isSeller) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/auth');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final annoncesAsync = ref.watch(sellerAnnoncesProvider(user.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes annonces'),
        actions: [
          IconButton(
            tooltip: 'Publier une annonce',
            onPressed: () => context.push('/publish-product'),
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      body: annoncesAsync.when(
        data: (annonces) {
          if (annonces.isEmpty) {
            return _EmptyListings(
              onPublish: () => context.push('/publish-product'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(sellerAnnoncesProvider(user.id));
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: annonces.length,
              itemBuilder: (context, index) {
                return _ListingCard(
                  annonce: annonces[index],
                  sellerId: user.id,
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Impossible de charger vos annonces pour le moment.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _ListingCard extends ConsumerWidget {
  const _ListingCard({required this.annonce, required this.sellerId});

  final Annonce annonce;
  final String sellerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = annonce.createdAt == null
        ? 'Date inconnue'
        : DateFormat('dd/MM/yyyy').format(annonce.createdAt!);
    final isOnline = annonce.status == 'active' || annonce.status == 'actif';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 78,
                    height: 78,
                    child: annonce.imageUrls.isEmpty
                        ? Container(
                            color: Colors.grey[850],
                            child: const Icon(Icons.image_outlined),
                          )
                        : Image.network(
                            annonce.imageUrls.first,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              annonce.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          _StatusChip(status: annonce.status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${annonce.price.toStringAsFixed(0)} ${annonce.currency}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_conditionLabel(annonce.condition)} • $date',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.visibility_outlined,
                  label: '${annonce.views} vues',
                ),
                _InfoPill(
                  icon: Icons.mark_unread_chat_alt_outlined,
                  label: '${annonce.messagesCount} messages',
                ),
                _InfoPill(
                  icon: Icons.category_outlined,
                  label: annonce.category,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/publish-product', extra: annonce),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleStatus(context, ref, isOnline),
                    icon: Icon(
                      isOnline
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      size: 18,
                    ),
                    label: Text(isOnline ? 'Désactiver' : 'Activer'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Supprimer',
                  onPressed: () => _confirmDelete(context, ref),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStatus(
    BuildContext context,
    WidgetRef ref,
    bool isOnline,
  ) async {
    final nextStatus = isOnline ? 'pending' : 'active';
    try {
      await ref
          .read(annonceRepositoryProvider)
          .updateAnnonceStatus(annonce, nextStatus);
      ref.invalidate(sellerAnnoncesProvider(sellerId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOnline ? 'Annonce désactivée.' : 'Annonce activée.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible de modifier le statut de l'annonce."),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette annonce ?'),
        content: const Text('Cette action retirera l’annonce de la vente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(annonceRepositoryProvider).deleteAnnonce(annonce.id);
      ref.invalidate(sellerAnnoncesProvider(sellerId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Annonce supprimée.')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible de supprimer l'annonce.")),
      );
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' || 'actif' => Colors.green,
      'expired' || 'expiree' || 'expirée' => Colors.orange,
      'rejected' || 'refusee' || 'refusée' => Colors.red,
      _ => Colors.blueGrey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.grey[300]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: Colors.grey[300], fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyListings extends StatelessWidget {
  const _EmptyListings({required this.onPublish});

  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Aucune annonce',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos annonces publiées apparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onPublish,
              icon: const Icon(Icons.add),
              label: const Text('Publier une annonce'),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) {
  return switch (status) {
    'active' || 'actif' => 'En ligne',
    'expired' || 'expiree' || 'expirée' => 'Expirée',
    'rejected' || 'refusee' || 'refusée' => 'Refusée',
    _ => 'En attente',
  };
}

String _conditionLabel(String condition) {
  return switch (condition) {
    'neuf' => 'Neuf',
    'bon_etat' => 'Bon état',
    'a_reparer' => 'À réparer',
    'occasion' => 'Occasion',
    _ => condition.isEmpty ? 'État non renseigné' : condition,
  };
}
