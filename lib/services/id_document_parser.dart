class IdDocumentParser {
  const IdDocumentParser._();

  static String parse(String fullText) {
    final text = _normalize(fullText).trim();
    final extracted = <String, String>{};

    final documentType = _detectDocumentType(text);
    if (documentType != null) {
      extracted['Document'] = documentType;
    }

    final documentNumber = _extractDocumentNumber(text, documentType);
    if (documentNumber != null) {
      extracted['Numero'] = documentNumber;
    }

    final name = _firstMatch(text, [
      RegExp(
        r"(?:NOM ET PRENOMS|NOM ET PRENOM|NOMS ET PRENOMS|NOMS?|NAME|PRENOMS?)\s*[:\-]?\s*([A-Z][A-Z '\-]{3,50})",
      ),
    ]);
    if (name != null) {
      extracted['Nom'] = name;
    } else {
      final upperName = RegExp(
        r"^([A-Z][A-Z '\-]{7,50})$",
        multiLine: true,
      ).firstMatch(text);
      if (upperName != null) {
        extracted['Nom'] = upperName.group(1)?.trim() ?? '';
      }
    }

    final birthDate = _firstMatch(text, [
      RegExp(
        r'(?:DATE DE NAISSANCE|NAISSANCE|DOB|NE\s*LE)\s*[:\-]?\s*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})',
      ),
      RegExp(r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})\b'),
    ]);
    if (birthDate != null) {
      extracted['DateNaissance'] = birthDate;
    }

    final birthPlace = _firstMatch(text, [
      RegExp(
        r"(?:LIEU DE NAISSANCE|LIEU|NE\s*A|PLACE)\s*[:\-]?\s*([A-Z][A-Z '\-]{3,40})",
      ),
    ]);
    if (birthPlace != null) {
      extracted['LieuNaissance'] = birthPlace;
    }

    final expiry = _firstMatch(text, [
      RegExp(
        r'(?:DATE D EXPIRATION|EXPIRATION|VALIDITE|EXPIRE|FIN)\s*[:\-]?\s*(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})',
      ),
    ]);
    if (expiry != null) {
      extracted['Expiration'] = expiry;
    }

    if (documentType == "Carte d'electeur") {
      _extractVoterCardFields(text, extracted);
    }

    if (extracted.isEmpty) {
      final preview = fullText.length > 300
          ? '${fullText.substring(0, 300)}...'
          : fullText;
      return preview.trim().isEmpty ? '' : 'Texte detecte :\n$preview';
    }

    final buffer = StringBuffer();
    extracted.forEach((key, value) {
      if (value.isNotEmpty) {
        buffer.writeln('$key : $value');
      }
    });

    return buffer.toString().trim();
  }

  static String _normalize(String value) {
    return value
        .toUpperCase()
        .replaceAll('\r\n', '\n')
        .replaceAll('’', "'")
        .replaceAll(RegExp('[ÀÁÂÃÄÅ]'), 'A')
        .replaceAll(RegExp('[ÉÈÊË]'), 'E')
        .replaceAll(RegExp('[ÎÏÍÌ]'), 'I')
        .replaceAll(RegExp('[ÔÖÓÒÕ]'), 'O')
        .replaceAll(RegExp('[ÙÛÜÚ]'), 'U')
        .replaceAll('Ç', 'C');
  }

  static String? _detectDocumentType(String text) {
    if (RegExp(
      r"(?:CARTE\s+D[' ]?ELECTEUR|CARTE\s+ELECTORALE|ELECTEUR|ELECTRICE|VOTER|BUREAU\s+DE\s+VOTE|CENTRE\s+DE\s+VOTE|CENI|CEI|INEC)",
    ).hasMatch(text)) {
      return "Carte d'electeur";
    }

    if (RegExp(r'\b(?:PASSEPORT|PASSPORT)\b').hasMatch(text)) {
      return 'Passeport';
    }

    if (RegExp(
      r'\b(?:CARTE NATIONALE|CNI|NNI|IDENTITE|IDENTITY)\b',
    ).hasMatch(text)) {
      return 'Carte nationale';
    }

    return null;
  }

  static String? _extractDocumentNumber(String text, String? documentType) {
    final patterns = <RegExp>[
      if (documentType == "Carte d'electeur")
        RegExp(
          r'(?:NUMERO|NO|N[^A-Z0-9]{0,3}|ID|CODE)\s*(?:DE\s+|D\s+)?(?:ELECTEUR|ELECTRICE|VOTANT|INSCRIPTION|CARTE)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\s\-\/]{5,24})',
        ),
      if (documentType == "Carte d'electeur")
        RegExp(
          r'(?:NUMERO|NO|N[^A-Z0-9]{0,3}|ID|CODE)\s*[:\-]?\s*([A-Z0-9][A-Z0-9\s\-\/]{5,24})',
        ),
      RegExp(
        r'(?:PASSEPORT|PASSPORT)\s*(?:NUMERO|NO|N[^A-Z0-9]{0,3})?\s*[:\-]?\s*([A-Z0-9][A-Z0-9\s\-\/]{5,14})',
      ),
      RegExp(r'(?:CNI|NNI|NUMERO|ID|IDENTITE|NUM)\s*[:\-]?\s*(\d[\d\s]{7,16})'),
      RegExp(r'\b(\d{9,14})\b'),
      if (documentType == "Carte d'electeur")
        RegExp(
          r'\b(?=[A-Z0-9\/-]{6,24}\b)(?=[A-Z0-9\/-]*\d)[A-Z0-9][A-Z0-9\/-]{5,23}\b',
        ),
    ];

    for (final pattern in patterns) {
      final value = _firstMatch(text, [pattern]);
      if (value != null) {
        return value.replaceAll(RegExp(r'\s+'), '');
      }
    }

    return null;
  }

  static void _extractVoterCardFields(
    String text,
    Map<String, String> extracted,
  ) {
    final voteCenter = _firstMatch(text, [
      RegExp(
        r"(?:CENTRE DE VOTE|LIEU DE VOTE|CENTRE)\s*[:\-]?\s*([A-Z0-9][A-Z0-9 '\-]{2,50})",
      ),
    ]);
    if (voteCenter != null) {
      extracted['CentreVote'] = voteCenter;
    }

    final pollingStation = _firstMatch(text, [
      RegExp(
        r"(?:BUREAU DE VOTE|BUREAU|BV)\s*[:\-]?\s*([A-Z0-9][A-Z0-9 '\-]{1,30})",
      ),
    ]);
    if (pollingStation != null) {
      extracted['BureauVote'] = pollingStation;
    }

    final commune = _firstMatch(text, [
      RegExp(
        r"(?:COMMUNE|ARRONDISSEMENT|CIRCONSCRIPTION|LOCALITE|QUARTIER)\s*[:\-]?\s*([A-Z][A-Z '\-]{2,40})",
      ),
    ]);
    if (commune != null) {
      extracted['Commune'] = commune;
    }
  }

  static String? _firstMatch(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}
