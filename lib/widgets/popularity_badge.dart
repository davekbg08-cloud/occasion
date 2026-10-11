import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_language.dart';
import '../providers/popularity_provider.dart';
import '../theme/app_theme.dart';

/// Pastille « ★ 12 » des points de popularité d'un vendeur (j'aime reçus
/// sur ses statuts). Masquée tant qu'il n'a aucun point.
class PopularityBadge extends ConsumerWidget {
  const PopularityBadge({
    super.key,
    required this.sellerId,
    this.showLabel = false,
    this.dense = false,
  });

  final String sellerId;

  /// Ajoute « points » après le nombre (fil plein écran).
  final bool showLabel;

  /// Version compacte posée sur la bulle de statut.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points =
        ref.watch(sellerPopularityPointsProvider(sellerId)).valueOrNull ?? 0;
    if (points <= 0) return const SizedBox.shrink();
    final label = points > 999 ? '999+' : '$points';
    return Semantics(
      label: '$points ${tr('points de popularité')}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 5 : 8,
          vertical: dense ? 1 : 3,
        ),
        decoration: BoxDecoration(
          color: AppColors.price,
          borderRadius: BorderRadius.circular(12),
          border: dense
              ? Border.all(color: AppColors.background, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_rounded,
              size: dense ? 11 : 14,
              color: Colors.white,
            ),
            const SizedBox(width: 2),
            Text(
              showLabel ? '$label ${tr('points')}' : label,
              style: TextStyle(
                color: Colors.white,
                fontSize: dense ? 10 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
