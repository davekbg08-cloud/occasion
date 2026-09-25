import 'package:intl/intl.dart';

/// Devise proposée pour une annonce (ouverture internationale).
class AppCurrency {
  const AppCurrency(this.code, this.symbol, this.name);

  /// Code stocké dans Firestore. `FC` est conservé pour le franc
  /// congolais (valeur historique des annonces existantes).
  final String code;
  final String symbol;
  final String name;
}

const appCurrencies = <AppCurrency>[
  AppCurrency('USD', r'$', 'Dollar américain'),
  AppCurrency('FC', 'FC', 'Franc congolais'),
  AppCurrency('EUR', '€', 'Euro'),
  AppCurrency('XAF', 'FCFA', 'Franc CFA (Afrique centrale)'),
  AppCurrency('XOF', 'FCFA', "Franc CFA (Afrique de l'Ouest)"),
  AppCurrency('GBP', '£', 'Livre sterling'),
  AppCurrency('CAD', r'CA$', 'Dollar canadien'),
  AppCurrency('CHF', 'CHF', 'Franc suisse'),
  AppCurrency('ZAR', 'R', 'Rand sud-africain'),
  AppCurrency('NGN', '₦', 'Naira nigérian'),
  AppCurrency('GHS', 'GH₵', 'Cedi ghanéen'),
  AppCurrency('KES', 'KSh', 'Shilling kényan'),
  AppCurrency('TZS', 'TSh', 'Shilling tanzanien'),
  AppCurrency('UGX', 'USh', 'Shilling ougandais'),
  AppCurrency('RWF', 'FRw', 'Franc rwandais'),
  AppCurrency('BIF', 'FBu', 'Franc burundais'),
  AppCurrency('ZMW', 'ZK', 'Kwacha zambien'),
  AppCurrency('AOA', 'Kz', 'Kwanza angolais'),
  AppCurrency('MAD', 'MAD', 'Dirham marocain'),
  AppCurrency('DZD', 'DA', 'Dinar algérien'),
  AppCurrency('TND', 'DT', 'Dinar tunisien'),
  AppCurrency('EGP', 'E£', 'Livre égyptienne'),
  AppCurrency('ETB', 'Br', 'Birr éthiopien'),
  AppCurrency('AED', 'AED', 'Dirham des Émirats'),
  AppCurrency('CNY', '¥', 'Yuan chinois'),
];

/// Devises payables en ligne aujourd'hui (Orange Money RDC). Les autres
/// annonces se règlent directement avec le vendeur, en attendant un
/// prestataire de paiement international.
const onlinePaymentCurrencies = <String>{'FC', 'USD'};

bool isOnlinePaymentCurrency(String code) =>
    onlinePaymentCurrencies.contains(code.trim().toUpperCase());

AppCurrency? currencyByCode(String code) {
  final normalized = code.trim().toUpperCase();
  final lookup = normalized == 'CDF' ? 'FC' : normalized;
  for (final currency in appCurrencies) {
    if (currency.code == lookup) return currency;
  }
  return null;
}

/// Devise proposée par défaut selon le pays du vendeur.
String defaultCurrencyForCountry(String isoCode) {
  switch (isoCode.toUpperCase()) {
    case 'CD':
    case 'US':
    case 'EC':
    case 'SV':
    case 'PA':
      return 'USD';
    case 'CM':
    case 'CG':
    case 'GA':
    case 'TD':
    case 'CF':
    case 'GQ':
      return 'XAF';
    case 'CI':
    case 'SN':
    case 'BJ':
    case 'BF':
    case 'ML':
    case 'NE':
    case 'TG':
    case 'GW':
      return 'XOF';
    case 'FR':
    case 'BE':
    case 'DE':
    case 'ES':
    case 'IT':
    case 'PT':
    case 'NL':
    case 'LU':
    case 'IE':
    case 'AT':
    case 'FI':
    case 'GR':
    case 'EE':
    case 'LV':
    case 'LT':
    case 'SK':
    case 'SI':
    case 'MT':
    case 'CY':
    case 'HR':
    case 'MC':
    case 'AD':
      return 'EUR';
    case 'GB':
      return 'GBP';
    case 'CA':
      return 'CAD';
    case 'CH':
      return 'CHF';
    case 'ZA':
      return 'ZAR';
    case 'NG':
      return 'NGN';
    case 'GH':
      return 'GHS';
    case 'KE':
      return 'KES';
    case 'TZ':
      return 'TZS';
    case 'UG':
      return 'UGX';
    case 'RW':
      return 'RWF';
    case 'BI':
      return 'BIF';
    case 'ZM':
      return 'ZMW';
    case 'AO':
      return 'AOA';
    case 'MA':
      return 'MAD';
    case 'DZ':
      return 'DZD';
    case 'TN':
      return 'TND';
    case 'EG':
      return 'EGP';
    case 'ET':
      return 'ETB';
    case 'AE':
      return 'AED';
    case 'CN':
      return 'CNY';
    default:
      return 'USD';
  }
}

/// Prix lisible : séparateur de milliers, sans décimales inutiles, suivi
/// du symbole de la devise (« 1 250 $ », « 5 000 FC », « 20 € »).
String formatPrice(num price, String currencyCode) {
  final formatter = NumberFormat.decimalPattern('fr');
  final value = price == price.roundToDouble()
      ? formatter.format(price.round())
      : formatter.format(price);
  final symbol = currencyByCode(currencyCode)?.symbol ?? currencyCode;
  return '$value $symbol';
}
