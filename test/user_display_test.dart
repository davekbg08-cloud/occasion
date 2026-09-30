import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/utils/user_display.dart';

void main() {
  group('userTag', () {
    test('toujours 4 chiffres, quel que soit l\'id', () {
      for (final uid in ['a', 'seller-1', 'X' * 40, '']) {
        final tag = userTag(uid);
        expect(tag.length, 4);
        expect(int.tryParse(tag), isNotNull);
      }
    });

    test('stable : le même id donne toujours le même numéro', () {
      const uid = 'seller-abc-123';
      expect(userTag(uid), userTag(uid));
    });

    test('des id différents donnent (en général) des numéros différents', () {
      final tags = {for (var i = 0; i < 50; i++) userTag('user-$i'): true};
      // Pas de garantie absolue (c'est un hash sur une petite plage), mais
      // sur 50 id bien distincts on doit voir une vraie diversité — sinon
      // la fonction ne servirait à rien.
      expect(tags.length, greaterThan(40));
    });
  });

  group('displayNameWithTag', () {
    test('combine le nom et le numéro', () {
      final result = displayNameWithTag('Jean Kabila', 'uid-1');
      expect(result, startsWith('Jean Kabila #'));
      expect(result, endsWith(userTag('uid-1')));
    });

    test('nom vide (ou espaces) retombe sur "Utilisateur"', () {
      expect(displayNameWithTag('', 'uid-1'), startsWith('Utilisateur #'));
      expect(displayNameWithTag('   ', 'uid-1'), startsWith('Utilisateur #'));
    });

    test('deux homonymes affichent des étiquettes différentes', () {
      final a = displayNameWithTag('Marie', 'buyer-aaa');
      final b = displayNameWithTag('Marie', 'buyer-bbb');
      expect(a, isNot(equals(b)));
    });
  });
}
