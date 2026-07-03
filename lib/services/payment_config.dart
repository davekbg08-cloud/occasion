/// Identifiants CinetPay du compte marchand Occasion.
///
/// ⚠️ A REMPLIR AVANT LA MISE EN PRODUCTION ⚠️
/// Récupère ces valeurs sur https://app.cinetpay.com (Compte > API / Site).
/// `apiKey` et `siteId` sont les identifiants CLIENT (utilisés par le SDK
/// CinetPay pour ouvrir le paiement) : c'est normal qu'ils soient dans
/// l'app, CinetPay les considère comme publics côté mobile.
///
/// En revanche, la VRAIE confirmation du paiement ne se fait jamais côté
/// client : elle est revérifiée côté serveur (Cloud Functions,
/// functions/index.js) avec les mêmes identifiants stockés en secret via :
///   firebase functions:secrets:set CINETPAY_APIKEY
///   firebase functions:secrets:set CINETPAY_SITE_ID
class PaymentConfig {
  const PaymentConfig._();

  /// Clé API CinetPay (onglet "API" du compte marchand).
  static const String cinetpayApiKey = String.fromEnvironment(
    'CINETPAY_APIKEY',
    defaultValue: 'TA_CLE_API',
  );

  /// Identifiant de site CinetPay (onglet "Sites" du compte marchand).
  static const String cinetpaySiteId = String.fromEnvironment(
    'CINETPAY_SITE_ID',
    defaultValue: 'TON_SITE_ID',
  );

  /// URL de la Cloud Function `cinetpayNotify` (webhook serveur-à-serveur).
  /// Format par défaut Firebase (région us-central1, projet occasion-10cdb) :
  static const String cinetpayNotifyUrl =
      'https://us-central1-occasion-10cdb.cloudfunctions.net/cinetpayNotify';

  static bool get isConfigured =>
      cinetpayApiKey != 'TA_CLE_API' && cinetpaySiteId != 'TON_SITE_ID';

  /// Numéro Orange Money sur lequel les acheteurs envoient l'argent
  /// directement (paiement manuel, vérifié à la main par un admin en
  /// attendant l'activation complète de CinetPay).
  /// ⚠️ A REMPLIR : ton vrai numéro Orange Money (ex: '+243 8xx xxx xxx').
  static const String manualOrangeMoneyNumber = String.fromEnvironment(
    'MANUAL_ORANGE_MONEY_NUMBER',
    defaultValue: 'TON_NUMERO_ORANGE_MONEY',
  );

  /// Nom affiché à l'acheteur pour confirmer qu'il envoie au bon compte.
  static const String manualOrangeMoneyHolderName = String.fromEnvironment(
    'MANUAL_ORANGE_MONEY_NAME',
    defaultValue: 'Occasion',
  );

  static bool get isManualOrangeMoneyConfigured =>
      manualOrangeMoneyNumber != 'TON_NUMERO_ORANGE_MONEY';
}
