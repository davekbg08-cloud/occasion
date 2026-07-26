/// Configuration du paiement Orange Money manuel (unique moyen de paiement).
class PaymentConfig {
  const PaymentConfig._();

  /// Numéro Orange Money sur lequel les acheteurs envoient l'argent
  /// directement (paiement manuel, vérifié à la main par un admin).
  /// ⚠️ A REMPLIR : ton vrai numéro Orange Money (ex: '+243 8xx xxx xxx').
  static const String manualOrangeMoneyNumber = String.fromEnvironment(
    'MANUAL_ORANGE_MONEY_NUMBER',
    defaultValue: '+243 856 373 707',
  );

  /// Nom affiché à l'acheteur pour confirmer qu'il envoie au bon compte.
  static const String manualOrangeMoneyHolderName = String.fromEnvironment(
    'MANUAL_ORANGE_MONEY_NAME',
    defaultValue: 'Occasion',
  );

  static bool get isManualOrangeMoneyConfigured =>
      manualOrangeMoneyNumber != 'TON_NUMERO_ORANGE_MONEY';
}
