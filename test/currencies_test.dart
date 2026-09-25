import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/utils/currencies.dart';

void main() {
  group('Devises (ouverture internationale)', () {
    test('formatPrice : séparateur de milliers et symbole', () {
      expect(formatPrice(45, 'USD'), endsWith(r' $'));
      expect(formatPrice(45, 'USD'), startsWith('45'));
      expect(formatPrice(20, 'EUR'), '20 €');
      expect(formatPrice(10000, 'XAF'), contains('FCFA'));
      expect(
        formatPrice(1250, 'USD').replaceAll(RegExp(r'\s'), ''),
        r'1250$',
      );
    });

    test('code inconnu : affiché tel quel, jamais d’exception', () {
      expect(formatPrice(5, 'ABC'), '5 ABC');
    });

    test('CDF est reconnu comme le franc congolais historique (FC)', () {
      expect(currencyByCode('CDF')?.code, 'FC');
      expect(currencyByCode('fc')?.code, 'FC');
    });

    test('devise par défaut selon le pays du vendeur', () {
      expect(defaultCurrencyForCountry('CD'), 'USD');
      expect(defaultCurrencyForCountry('CM'), 'XAF');
      expect(defaultCurrencyForCountry('SN'), 'XOF');
      expect(defaultCurrencyForCountry('FR'), 'EUR');
      expect(defaultCurrencyForCountry('KE'), 'KES');
      expect(defaultCurrencyForCountry('ZZ'), 'USD');
    });

    test('le paiement en ligne reste limité à FC et USD', () {
      expect(isOnlinePaymentCurrency('USD'), isTrue);
      expect(isOnlinePaymentCurrency('FC'), isTrue);
      expect(isOnlinePaymentCurrency('EUR'), isFalse);
    });

    test('toutes les devises ont un code unique', () {
      final codes = appCurrencies.map((c) => c.code);
      expect(codes.toSet().length, codes.length);
    });
  });
}
