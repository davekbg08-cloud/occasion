import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_language.dart';
import '../theme/app_theme.dart';

/// Écran de blocage plein écran : affiché par-dessus TOUT le reste de
/// l'app (voir `OccasionApp.build` dans `main.dart`) dès que
/// `forceUpdateRequiredProvider` vaut `true`. Volontairement impossible à
/// fermer — pas de bouton retour (`PopScope(canPop: false)`), aucun moyen
/// d'atteindre l'app tant que la mise à jour n'a pas été installée.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.occasion.app';

  Future<void> _openStore() async {
    final uri = Uri.parse(_playStoreUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_outlined,
                    color: AppColors.primary,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  tr('Mise à jour requise'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    'Une nouvelle version est disponible. Mets à jour '
                    "l'application pour continuer à l'utiliser.",
                  ),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _openStore,
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(tr('Mettre à jour')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
