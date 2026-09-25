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

  /// Pays à règles détaillées (longueur et préfixes d'opérateurs connus).
  /// Ce sont aussi les seuls pays du paiement Mobile Money actuel.
  static final mobileMoneyCountries = <PhoneCountry>[
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

  /// Autres pays (ouverture internationale) : validation générique E.164,
  /// 6 à 12 chiffres après l'indicatif, sans règles d'opérateur.
  static final _worldCountries = <PhoneCountry>[
    _generic('AF', "Afghanistan", '+93'),
    _generic('ZA', "Afrique du Sud", '+27'),
    _generic('AL', "Albanie", '+355'),
    _generic('DZ', "Algérie", '+213'),
    _generic('DE', "Allemagne", '+49'),
    _generic('AD', "Andorre", '+376'),
    _generic('AO', "Angola", '+244'),
    _generic('SA', "Arabie saoudite", '+966'),
    _generic('AR', "Argentine", '+54'),
    _generic('AM', "Arménie", '+374'),
    _generic('AU', "Australie", '+61'),
    _generic('AT', "Autriche", '+43'),
    _generic('AZ', "Azerbaïdjan", '+994'),
    _generic('BH', "Bahreïn", '+973'),
    _generic('BD', "Bangladesh", '+880'),
    _generic('BE', "Belgique", '+32'),
    _generic('BJ', "Bénin", '+229'),
    _generic('BY', "Biélorussie", '+375'),
    _generic('BO', "Bolivie", '+591'),
    _generic('BA', "Bosnie-Herzégovine", '+387'),
    _generic('BW', "Botswana", '+267'),
    _generic('BR', "Brésil", '+55'),
    _generic('BG', "Bulgarie", '+359'),
    _generic('BF', "Burkina Faso", '+226'),
    _generic('BI', "Burundi", '+257'),
    _generic('KH', "Cambodge", '+855'),
    _generic('CA', "Canada", '+1'),
    _generic('CV', "Cap-Vert", '+238'),
    _generic('CF', "Centrafrique", '+236'),
    _generic('CL', "Chili", '+56'),
    _generic('CN', "Chine", '+86'),
    _generic('CY', "Chypre", '+357'),
    _generic('CO', "Colombie", '+57'),
    _generic('KM', "Comores", '+269'),
    _generic('KR', "Corée du Sud", '+82'),
    _generic('CR', "Costa Rica", '+506'),
    _generic('HR', "Croatie", '+385'),
    _generic('CU', "Cuba", '+53'),
    _generic('DK', "Danemark", '+45'),
    _generic('DJ', "Djibouti", '+253'),
    _generic('EG', "Égypte", '+20'),
    _generic('AE', "Émirats arabes unis", '+971'),
    _generic('EC', "Équateur", '+593'),
    _generic('ER', "Érythrée", '+291'),
    _generic('ES', "Espagne", '+34'),
    _generic('EE', "Estonie", '+372'),
    _generic('SZ', "Eswatini", '+268'),
    _generic('US', "États-Unis", '+1'),
    _generic('ET', "Éthiopie", '+251'),
    _generic('FI', "Finlande", '+358'),
    _generic('FR', "France", '+33'),
    _generic('GA', "Gabon", '+241'),
    _generic('GM', "Gambie", '+220'),
    _generic('GE', "Géorgie", '+995'),
    _generic('GH', "Ghana", '+233'),
    _generic('GR', "Grèce", '+30'),
    _generic('GT', "Guatemala", '+502'),
    _generic('GN', "Guinée", '+224'),
    _generic('GQ', "Guinée équatoriale", '+240'),
    _generic('GW', "Guinée-Bissau", '+245'),
    _generic('HT', "Haïti", '+509'),
    _generic('HN', "Honduras", '+504'),
    _generic('HK', "Hong Kong", '+852'),
    _generic('HU', "Hongrie", '+36'),
    _generic('IN', "Inde", '+91'),
    _generic('ID', "Indonésie", '+62'),
    _generic('IQ', "Irak", '+964'),
    _generic('IR', "Iran", '+98'),
    _generic('IE', "Irlande", '+353'),
    _generic('IS', "Islande", '+354'),
    _generic('IL', "Israël", '+972'),
    _generic('IT', "Italie", '+39'),
    _generic('JM', "Jamaïque", '+1'),
    _generic('JP', "Japon", '+81'),
    _generic('JO', "Jordanie", '+962'),
    _generic('KZ', "Kazakhstan", '+7'),
    _generic('KE', "Kenya", '+254'),
    _generic('KW', "Koweït", '+965'),
    _generic('LS', "Lesotho", '+266'),
    _generic('LV', "Lettonie", '+371'),
    _generic('LB', "Liban", '+961'),
    _generic('LR', "Liberia", '+231'),
    _generic('LY', "Libye", '+218'),
    _generic('LT', "Lituanie", '+370'),
    _generic('LU', "Luxembourg", '+352'),
    _generic('MG', "Madagascar", '+261'),
    _generic('MY', "Malaisie", '+60'),
    _generic('MW', "Malawi", '+265'),
    _generic('ML', "Mali", '+223'),
    _generic('MT', "Malte", '+356'),
    _generic('MA', "Maroc", '+212'),
    _generic('MU', "Maurice", '+230'),
    _generic('MR', "Mauritanie", '+222'),
    _generic('MX', "Mexique", '+52'),
    _generic('MD', "Moldavie", '+373'),
    _generic('MC', "Monaco", '+377'),
    _generic('MZ', "Mozambique", '+258'),
    _generic('NA', "Namibie", '+264'),
    _generic('NP', "Népal", '+977'),
    _generic('NI', "Nicaragua", '+505'),
    _generic('NE', "Niger", '+227'),
    _generic('NG', "Nigeria", '+234'),
    _generic('NO', "Norvège", '+47'),
    _generic('NZ', "Nouvelle-Zélande", '+64'),
    _generic('OM', "Oman", '+968'),
    _generic('UG', "Ouganda", '+256'),
    _generic('UZ', "Ouzbékistan", '+998'),
    _generic('PK', "Pakistan", '+92'),
    _generic('PS', "Palestine", '+970'),
    _generic('PA', "Panama", '+507'),
    _generic('PY', "Paraguay", '+595'),
    _generic('NL', "Pays-Bas", '+31'),
    _generic('PE', "Pérou", '+51'),
    _generic('PH', "Philippines", '+63'),
    _generic('PL', "Pologne", '+48'),
    _generic('PT', "Portugal", '+351'),
    _generic('QA', "Qatar", '+974'),
    _generic('DO', "République dominicaine", '+1'),
    _generic('CZ', "Tchéquie", '+420'),
    _generic('RO', "Roumanie", '+40'),
    _generic('GB', "Royaume-Uni", '+44'),
    _generic('RU', "Russie", '+7'),
    _generic('RW', "Rwanda", '+250'),
    _generic('SV', "Salvador", '+503'),
    _generic('ST', "Sao Tomé-et-Principe", '+239'),
    _generic('RS', "Serbie", '+381'),
    _generic('SC', "Seychelles", '+248'),
    _generic('SL', "Sierra Leone", '+232'),
    _generic('SG', "Singapour", '+65'),
    _generic('SK', "Slovaquie", '+421'),
    _generic('SI', "Slovénie", '+386'),
    _generic('SO', "Somalie", '+252'),
    _generic('SD', "Soudan", '+249'),
    _generic('SS', "Soudan du Sud", '+211'),
    _generic('LK', "Sri Lanka", '+94'),
    _generic('SE', "Suède", '+46'),
    _generic('CH', "Suisse", '+41'),
    _generic('SY', "Syrie", '+963'),
    _generic('TJ', "Tadjikistan", '+992'),
    _generic('TZ', "Tanzanie", '+255'),
    _generic('TD', "Tchad", '+235'),
    _generic('TH', "Thaïlande", '+66'),
    _generic('TG', "Togo", '+228'),
    _generic('TN', "Tunisie", '+216'),
    _generic('TR', "Turquie", '+90'),
    _generic('UA', "Ukraine", '+380'),
    _generic('UY', "Uruguay", '+598'),
    _generic('VE', "Venezuela", '+58'),
    _generic('VN', "Viêt Nam", '+84'),
    _generic('YE', "Yémen", '+967'),
    _generic('ZM', "Zambie", '+260'),
    _generic('ZW', "Zimbabwe", '+263'),
  ];

  /// Tous les pays proposés à l'inscription : la RDC d'abord (par
  /// défaut), puis les pays détaillés, puis le reste du monde par ordre
  /// alphabétique.
  static final countries = <PhoneCountry>[
    ...mobileMoneyCountries,
    ..._worldCountries,
  ];

  static PhoneCountry _generic(String isoCode, String name, String dialCode) {
    return PhoneCountry(
      isoCode: isoCode,
      name: name,
      dialCode: dialCode,
      subscriberLength: 0,
      pattern: RegExp(r'^\d{6,12}$'),
      example: '${dialCode}...',
    );
  }

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
        ? ([...countries]..sort(
            (a, b) => b.dialCode.length.compareTo(a.dialCode.length),
          ))
        : <PhoneCountry>[countryByIso(countryIso)];

    for (final country in candidates) {
      if (!normalized.startsWith(country.dialCode)) continue;

      final subscriber = normalized.substring(country.dialCode.length);
      final isGeneric = country.subscriberLength == 0;
      if (isGeneric && !country.pattern.hasMatch(subscriber)) {
        return PhoneValidationResult(
          isValid: false,
          normalized: normalized,
          country: country,
          message:
              'Numéro invalide pour ${country.name} : 6 à 12 chiffres après ${country.dialCode}.',
        );
      }
      if (!isGeneric && subscriber.length != country.subscriberLength) {
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
          "Indicatif non reconnu. Choisissez votre pays et vérifiez l'indicatif.",
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
