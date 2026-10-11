import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

import '../theme/motion.dart';

/// Logo Occasion, jamais posé comme une image à fond blanc découpée :
/// - sur fond sombre (par défaut) : version sans fond, bleu marine passé en
///   blanc pour rester lisible (`occasion_logo_dark.png`) ;
/// - sur fond clair ([onLight]) : logo d'origine, sans fond.
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

/// Les écrans de démarrage suivent le mode du téléphone : page blanche et
/// logo d'origine en mode clair, fond sombre de l'app et logo clair en
/// mode sombre — même rendu que l'écran natif Android
/// (`values[-night]-v31/styles.xml`) et la page d'attente web
/// (`web/index.html`) qui les précèdent.
bool occasionSplashIsLight(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context) == Brightness.light;

Color occasionSplashBackground(BuildContext context) =>
    occasionSplashIsLight(context) ? Colors.white : AppColors.background;

/// Couleur des textes posés sur un écran de démarrage.
Color occasionSplashHintColor(BuildContext context) =>
    occasionSplashIsLight(context)
    ? const Color(0xFF5B6B7C)
    : AppColors.textSecondary;

/// Page d'écran de démarrage (fond et icônes de la barre d'état adaptés au
/// mode clair/sombre), [child] centré.
class OccasionSplashScaffold extends StatelessWidget {
  const OccasionSplashScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final light = occasionSplashIsLight(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: occasionSplashBackground(context),
        body: Center(child: child),
      ),
    );
  }
}

/// Logo des écrans de démarrage/chargement : version adaptée au mode
/// clair/sombre, apparaît en douceur (fondu + léger agrandissement).
class OccasionSplashLogo extends StatelessWidget {
  const OccasionSplashLogo({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = OccasionLogo(
      size: size,
      onLight: occasionSplashIsLight(context),
    );
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
