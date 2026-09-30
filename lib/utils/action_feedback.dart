import 'package:flutter/services.dart';

/// Petit retour sensoriel (vibration légère + son système du téléphone)
/// pour confirmer immédiatement une action "je viens de faire quelque
/// chose d'important" — envoyer un message, publier une annonce.
///
/// Volontairement basé sur les API Flutter natives (`HapticFeedback`,
/// `SystemSound`) plutôt qu'un package audio dédié : pas de nouvelle
/// dépendance ni de fichier son à embarquer pour un simple clic de
/// confirmation. `SystemSound.play` respecte déjà les réglages sonores/
/// silencieux du téléphone (rien à gérer côté app), et les deux appels
/// sont best-effort : jamais d'exception ne doit remonter jusqu'à
/// l'appelant pour un simple retour sensoriel.
void playActionFeedback() {
  try {
    HapticFeedback.lightImpact();
  } catch (_) {
    // Vibreur absent/indisponible (web, certains émulateurs) : pas grave,
    // le son suffit.
  }
  try {
    SystemSound.play(SystemSoundType.click);
  } catch (_) {
    // Idem côté son.
  }
}
