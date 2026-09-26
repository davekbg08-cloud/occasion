import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/status.dart';
import '../providers/auth_provider.dart';
import '../providers/status_provider.dart';
import 'occasion_image.dart';

/// Bandeau horizontal des statuts (façon « stories ») affiché en haut de
/// l'accueil. Remplace l'ancien onglet « Feed » : un appui ouvre le fil
/// plein écran existant (`/statuts`) directement sur le statut du vendeur
/// dont la bulle a été touchée, sans rien retirer de la fonction.
class StatusStrip extends ConsumerStatefulWidget {
  const StatusStrip({super.key, this.blockedIds = const {}});

  /// Vendeurs bloqués par l'utilisateur courant — mêmes ids que ceux déjà
  /// exclus du fil plein écran (`status_feed_screen.dart`) : sans ce
  /// filtre ici, une bulle « stories » pouvait afficher un vendeur bloqué
  /// que le fil lui-même masque une fois ouvert.
  final Set<String> blockedIds;

  @override
  ConsumerState<StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends ConsumerState<StatusStrip> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(statusNotifierProvider.notifier).loadFeed();
      final userId = ref.read(authNotifierProvider).currentUser?.id;
      if (userId != null) {
        ref.read(statusNotifierProvider.notifier).loadViewedStatuses(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ref.watch(
      statusNotifierProvider.select((state) => state.statuses),
    );
    final viewedIds = ref.watch(
      statusNotifierProvider.select((state) => state.viewedIds),
    );
    final isSeller =
        ref.watch(authNotifierProvider).currentUser?.isSeller ?? false;

    // Un seul cercle par vendeur, dans l'ordre du fil — coloré tant qu'au
    // moins un de SES statuts (pas seulement le premier retenu ici) n'a
    // pas encore été vu.
    final seen = <String>{};
    final sellers = <Status>[];
    final hasUnseen = <String, bool>{};
    for (final status in statuses) {
      if (widget.blockedIds.contains(status.sellerId)) continue;
      hasUnseen[status.sellerId] =
          (hasUnseen[status.sellerId] ?? false) ||
          !viewedIds.contains(status.id);
      if (seen.add(status.sellerId)) sellers.add(status);
      if (sellers.length >= 12) break;
    }

    if (!isSeller && sellers.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (isSeller)
            _StatusBubble(
              label: 'Mon statut',
              onTap: () => context.push('/add-status'),
              child: const Icon(Icons.add, size: 26),
            ),
          for (final status in sellers)
            _StatusBubble(
              label: status.sellerName,
              highlighted: hasUnseen[status.sellerId] ?? false,
              onTap: () => context.push('/statuts', extra: status.sellerId),
              child: _Avatar(
                url: status.sellerProfileImageUrl,
                name: status.sellerName,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble({
    required this.label,
    required this.onTap,
    required this.child,
    this.highlighted = false,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: highlighted ? color : Colors.grey.shade600,
                    width: 2,
                  ),
                ),
                child: ClipOval(child: Center(child: child)),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url?.trim();
    if (imageUrl == null || imageUrl.isEmpty) {
      final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
      return Text(
        initial,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      );
    }
    return OccasionImage.thumbnail(
      imageUrl,
      width: 52,
      height: 52,
      cacheWidth: 104,
      cacheHeight: 104,
    );
  }
}
