import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

/// Badge numérique sur l'icône de l'app (comme WhatsApp) — best-effort :
/// non supporté sur tous les lanceurs/OEM Android (voir `app_badge_plus`),
/// et jamais garanti à jour quand l'app est totalement fermée (contrainte
/// de la plateforme, pas de ce service). Toute erreur est avalée : un
/// badge qui échoue à se mettre à jour ne doit jamais faire planter l'app.
class AppBadgeService {
  static Future<void> update(int count) async {
    try {
      await AppBadgePlus.updateBadge(count);
    } catch (error) {
      debugPrint('Badge d\'icône non mis à jour : $error');
    }
  }
}
