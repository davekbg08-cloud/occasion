import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/services/phone_number_validator.dart';

void main() {
  group('PhoneNumberValidator (ouverture internationale)', () {
    test('la RDC reste le pays par défaut et le premier de la liste', () {
      expect(PhoneNumberValidator.defaultCountryIso, 'CD');
      expect(PhoneNumberValidator.countries.first.isoCode, 'CD');
    });

    test('les règles détaillées RDC sont conservées', () {
      expect(
        PhoneNumberValidator.validate(
          '+243812345678',
          countryIso: 'CD',
        ).isValid,
        isTrue,
      );
      expect(
        PhoneNumberValidator.validate(
          '+243712345678',
          countryIso: 'CD',
        ).isValid,
        isFalse,
      );
    });

    test('un numéro français, belge ou kényan est accepté', () {
      expect(
        PhoneNumberValidator.validate('+33612345678', countryIso: 'FR').isValid,
        isTrue,
      );
      expect(
        PhoneNumberValidator.validate('+32470123456', countryIso: 'BE').isValid,
        isTrue,
      );
      expect(
        PhoneNumberValidator.validate(
          '+254712345678',
          countryIso: 'KE',
        ).isValid,
        isTrue,
      );
    });

    test('sans pays choisi, le pays est déduit de l’indicatif', () {
      final result = PhoneNumberValidator.validate('+241 06 12 34 56');
      expect(result.isValid, isTrue);
      expect(result.country?.isoCode, 'GA');
      expect(
        PhoneNumberValidator.validate('+243812345678').country?.isoCode,
        'CD',
      );
    });

    test('un numéro trop court ou trop long est refusé', () {
      expect(
        PhoneNumberValidator.validate('+3312', countryIso: 'FR').isValid,
        isFalse,
      );
      expect(
        PhoneNumberValidator.validate(
          '+331234567890123',
          countryIso: 'FR',
        ).isValid,
        isFalse,
      );
    });

    test('aucun doublon de code pays', () {
      final isos = PhoneNumberValidator.countries.map((c) => c.isoCode);
      expect(isos.toSet().length, isos.length);
    });

    test('le paiement Mobile Money reste limité aux 5 pays détaillés', () {
      expect(PhoneNumberValidator.mobileMoneyCountries.map((c) => c.isoCode), [
        'CD',
        'CI',
        'SN',
        'CM',
        'CG',
      ]);
    });
  });
}
