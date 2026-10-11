import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_language.dart';
import '../models/status.dart';
import '../providers/auth_provider.dart';
import '../providers/popularity_provider.dart';
import '../providers/status_provider.dart';
import 'occasion_image.dart';
import 'popularity_badge.dart';
import '../theme/motion.dart';

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

/// Bulles affichées au plus, choisies parmi [_candidateSellers] vendeurs
/// du fil une fois triés par popularité.
const _maxBubbles = 12;
const _candidateSellers = 30;

/// Trie les vendeurs par points de popularité décroissants, en gardant
/// l'ordre d'origine (fil, plus récent d'abord) à égalité.
List<Status> orderSellersByPopularity(
  List<Status> sellers,
  Map<String, int> points,
) {
  final indexed = sellers.indexed.toList()
    ..sort((a, b) {
      final byPoints = (points[b.$2.sellerId] ?? 0).compareTo(
        points[a.$2.sellerId] ?? 0,
      );
      return byPoints != 0 ? byPoints : a.$1.compareTo(b.$1);
    });
  return [for (final (_, status) in indexed) status];
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
      if (sellers.length >= _candidateSellers) break;
    }
    // Les vendeurs les plus populaires (points gagnés grâce aux j'aime) en
    // premier ; à égalité, l'ordre du fil (statut le plus récent d'abord).
    final ordered = orderSellersByPopularity(sellers, {
      for (final status in sellers)
        status.sellerId:
            ref
                .watch(sellerPopularityPointsProvider(status.sellerId))
                .valueOrNull ??
            0,
    }).take(_maxBubbles).toList();

    if (!isSeller && sellers.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 124,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (isSeller)
            _StatusBubble(
              label: tr('Mon statut'),
              onTap: () => context.push('/add-status'),
              child: const Icon(Icons.add, size: 30),
            ),
          for (final status in ordered)
            _StatusBubble(
              label: status.sellerName,
              highlighted: hasUnseen[status.sellerId] ?? false,
              badge: PopularityBadge(sellerId: status.sellerId, dense: true),
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
    this.badge,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool highlighted;

  /// Points de popularité du vendeur, à cheval sur le bas du cercle.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: PressableScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(40),
          child: SizedBox(
            width: 82,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: highlighted ? color : Colors.grey.shade600,
                          width: 2.5,
                        ),
                      ),
                      child: ClipOval(child: Center(child: child)),
                    ),
                    if (badge != null) Positioned(bottom: -6, child: badge!),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
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
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      );
    }
    return OccasionImage.thumbnail(
      imageUrl,
      width: 70,
      height: 70,
      cacheWidth: 140,
      cacheHeight: 140,
    );
  }
}
