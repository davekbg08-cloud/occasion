import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Logo Occasion présenté comme une icône d'app : tuile blanche aux coins
/// arrondis. Le fichier a un fond blanc opaque (pas de transparence) ;
/// posé tel quel sur le fond sombre, il apparaissait comme un carré blanc
/// découpé.
class OccasionLogo extends StatelessWidget {
  const OccasionLogo({super.key, this.size = 96, this.fit = BoxFit.contain});

  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);
    // Centré dans l'espace reçu : une colonne `stretch` étirerait sinon la
    // tuile sur toute la largeur.
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          boxShadow: size >= 64
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: size * 0.18,
                    offset: Offset(0, size * 0.05),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Image.asset(
            'assets/branding/occasion_logo.png',
            width: size,
            height: size,
            fit: fit,
            semanticLabel: 'Occasion',
          ),
        ),
      ),
    );
  }
}

/// Logo des écrans de démarrage/chargement : apparaît en douceur (fondu +
/// léger agrandissement), dans la continuité de l'écran de démarrage
/// natif et de la page web qui l'affichent déjà à la même place.
class OccasionSplashLogo extends StatelessWidget {
  const OccasionSplashLogo({super.key, this.size = 132});

  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = OccasionLogo(size: size);
    if (OccasionMotion.reduced(context)) return logo;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: OccasionMotion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      ),
      child: logo,
    );
  }
}
