/// Taux de conversion prix -> points de fidélité, dupliqué côté client
/// depuis `LOYALTY_POINTS_RATE` (functions/index.js) uniquement pour
/// l'AFFICHAGE (badge "🎁 +X points" sur les listings) — le crédit réel des
/// points reste exclusivement calculé et appliqué côté serveur
/// (`pointsForAmount`/`onOrderCompleted`), jamais par ce fichier. Garder ces
/// deux constantes synchronisées si le taux change côté serveur.
const Map<String, double> loyaltyPointsRate = {'FC': 1 / 1000, 'USD': 1};

/// Estimation du nombre de points qu'un acheteur gagnerait en achetant un
/// article à [price] dans [currency] — même calcul que `pointsForAmount`
/// côté serveur (floor(prix * taux)). Retourne 0 pour une devise non prise
/// en charge ou un prix non positif, jamais une exception.
int estimateLoyaltyPoints(double price, String currency) {
  final rate = loyaltyPointsRate[currency];
  if (rate == null || price <= 0) return 0;
  return (price * rate).floor();
}
