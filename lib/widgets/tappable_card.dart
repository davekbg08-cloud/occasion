import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// Carte de liste cliquable (conversations, répertoire) : fond plus clair
/// que l'écran, coins arrondis et bordure — chaque élément est nettement
/// séparé du suivant — avec un léger enfoncement et l'onde Material au
/// toucher. [highlighted] (ex. conversation non lue) : fond plus marqué,
/// bordure et barre latérale turquoise.
class TappableCard extends StatelessWidget {
  const TappableCard({
    super.key,
    required this.onTap,
    required this.child,
    this.highlighted = false,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 4, 12),
  });

  final VoidCallback onTap;
  final Widget child;
  final bool highlighted;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: highlighted ? AppColors.surfaceHigh : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          side: BorderSide(
            color: highlighted
                ? AppColors.primary.withValues(alpha: 0.55)
                : AppColors.outline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.primary.withValues(alpha: 0.12),
          highlightColor: AppColors.primary.withValues(alpha: 0.06),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: OccasionMotion.short,
                  width: 4,
                  color: highlighted ? AppColors.primary : Colors.transparent,
                ),
                Expanded(
                  child: Padding(padding: padding, child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chevron « › » en bout de carte : indique que la ligne s'ouvre.
class OpenChevron extends StatelessWidget {
  const OpenChevron({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 2, right: 4),
      child: Icon(Icons.chevron_right, size: 22, color: AppColors.primary),
    );
  }
}
