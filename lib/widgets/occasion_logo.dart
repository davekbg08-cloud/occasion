import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Logo Occasion, jamais posé comme une image à fond blanc découpée :
/// - sur fond sombre (par défaut) : version sans fond, bleu marine passé en
///   blanc pour rester lisible (`occasion_logo_dark.png`) ;
/// - sur une page blanche ([onLight]) : logo d'origine, dont le fond blanc
///   se fond dans celui de la page.
class OccasionLogo extends StatelessWidget {
  const OccasionLogo({
    super.key,
    this.size = 96,
    this.fit = BoxFit.contain,
    this.onLight = false,
  });

  final double size;
  final BoxFit fit;
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      onLight
          ? 'assets/branding/occasion_logo.png'
          : 'assets/branding/occasion_logo_dark.png',
      width: size,
      height: size,
      fit: fit,
      semanticLabel: 'Occasion',
    );
  }
}

/// Emblème seul (O, sac, téléphone), sans le mot « Occasion » ni le
/// slogan, illisibles en petit : pour l'en-tête, où le nom est déjà écrit
/// à côté. Version pour fond sombre.
class OccasionEmblem extends StatelessWidget {
  const OccasionEmblem({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/occasion_emblem_dark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Occasion',
    );
  }
}

/// Fond des écrans de démarrage : celui du logo, pour une suite continue
/// avec l'écran de démarrage natif (Android) et la page d'attente web.
const occasionSplashBackground = Colors.white;

/// Logo des écrans de démarrage/chargement (page blanche) : apparaît en
/// douceur (fondu + léger agrandissement).
class OccasionSplashLogo extends StatelessWidget {
  const OccasionSplashLogo({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = OccasionLogo(size: size, onLight: true);
    if (OccasionMotion.reduced(context)) return logo;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: OccasionMotion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: logo,
    );
  }
}
