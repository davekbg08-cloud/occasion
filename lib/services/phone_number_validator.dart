class PhoneCountry {
  const PhoneCountry({
    required this.isoCode,
    required this.name,
    required this.dialCode,
    required this.subscriberLength,
    required this.pattern,
    required this.example,
  });

  final String isoCode;
  final String name;
  final String dialCode;
  final int subscriberLength;
  final RegExp pattern;
  final String example;
}

class PhoneValidationResult {
  const PhoneValidationResult({
    required this.isValid,
    required this.normalized,
    required this.message,
    this.country,
  });

  final bool isValid;
  final String normalized;
  final String message;
  final PhoneCountry? country;
}

class PhoneNumberValidator {
  static const defaultCountryIso = 'CD';

  static final countries = <PhoneCountry>[
    PhoneCountry(
      isoCode: 'CD',
      name: 'RDC',
      dialCode: '+243',
      subscriberLength: 9,
      pattern: RegExp(r'^[89]\d{8}$'),
      example: '+243812345678',
    ),
    PhoneCountry(
      isoCode: 'CI',
      name: "Cote d'Ivoire",
      dialCode: '+225',
      subscriberLength: 10,
      pattern: RegExp(r'^(01|05|07)\d{8}$'),
      example: '+2250701020304',
    ),
    PhoneCountry(
      isoCode: 'SN',
      name: 'Senegal',
      dialCode: '+221',
      subscriberLength: 9,
      pattern: RegExp(r'^7[05678]\d{7}$'),
      example: '+221771234567',
    ),
    PhoneCountry(
      isoCode: 'CM',
      name: 'Cameroun',
      dialCode: '+237',
      subscriberLength: 9,
      pattern: RegExp(r'^[62]\d{8}$'),
      example: '+237699123456',
    ),
    PhoneCountry(
      isoCode: 'CG',
      name: 'Congo',
      dialCode: '+242',
      subscriberLength: 9,
      pattern: RegExp(r'^0[456]\d{7}$'),
      example: '+242061234567',
    ),
  ];

  static PhoneCountry countryByIso(String isoCode) {
    return countries.firstWhere(
      (country) => country.isoCode == isoCode,
      orElse: () => countries.first,
    );
  }

  static PhoneValidationResult validate(String raw, {String? countryIso}) {
    final normalized = normalize(raw);
    if (normalized.isEmpty) {
      return const PhoneValidationResult(
        isValid: false,
        normalized: '',
        message: 'Entre un numero de telephone.',
      );
    }

    if (!normalized.startsWith('+')) {
      return PhoneValidationResult(
        isValid: false,
        normalized: normalized,
        message: "Ajoutez l'indicatif international, par exemple +243.",
      );
    }

    final candidates = countryIso == null
        ? countries
        : <PhoneCountry>[countryByIso(countryIso)];

    for (final country in candidates) {
      if (!normalized.startsWith(country.dialCode)) continue;

      final subscriber = normalized.substring(country.dialCode.length);
      if (subscriber.length != country.subscriberLength) {
        return PhoneValidationResult(
          isValid: false,
          normalized: normalized,
          country: country,
          message:
              'Numero invalide pour ${country.name}: ${country.subscriberLength} chiffres apres ${country.dialCode}. Exemple ${country.example}.',
        );
      }

      if (!country.pattern.hasMatch(subscriber)) {
        return PhoneValidationResult(
          isValid: false,
          normalized: normalized,
          country: country,
          message:
              'Numero invalide pour ${country.name}. Exemple ${country.example}.',
        );
      }

      return PhoneValidationResult(
        isValid: true,
        normalized: normalized,
        country: country,
        message: 'Numero valide.',
      );
    }

    return PhoneValidationResult(
      isValid: false,
      normalized: normalized,
      message:
          'Indicatif non pris en charge. Utilisez ${countries.map((country) => country.dialCode).join(', ')}.',
    );
  }

  static String normalize(String raw) {
    var value = raw.trim();
    if (value.startsWith('00')) {
      value = '+${value.substring(2)}';
    }
    value = value.replaceAll(RegExp(r'[\s().-]'), '');
    if (value.startsWith('+')) {
      return '+${value.substring(1).replaceAll(RegExp(r'\D'), '')}';
    }
    return value.replaceAll(RegExp(r'\D'), '');
  }
}
