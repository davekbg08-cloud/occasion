import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/l10n/app_language.dart';

void main() {
  group('Traduction (français → anglais)', () {
    tearDown(() => AppLanguage.current.value = 'fr');

    test('en français, le texte source est renvoyé tel quel', () {
      AppLanguage.current.value = 'fr';
      expect(tr('Accueil'), 'Accueil');
    });

    test('en anglais, les textes connus sont traduits', () {
      AppLanguage.current.value = 'en';
      expect(tr('Accueil'), 'Home');
      expect(tr('Passer à la caisse'), 'Checkout');
      expect(tr("Demandes d'échange"), 'Exchange requests');
    });

    test('un texte sans traduction reste en français (jamais vide)', () {
      AppLanguage.current.value = 'en';
      expect(tr('Texte inconnu'), 'Texte inconnu');
    });

    test('aucune traduction vide', () {
      for (final entry in englishTranslations.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });
  });
}
