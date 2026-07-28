import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/screens/chat_list_screen.dart';

void main() {
  group(
    'formatUnreadBadgeLabel (pastille numérique de la liste de conversations)',
    () {
      test('affiche le compte exact pour 0, 1 et 16', () {
        expect(formatUnreadBadgeLabel(0), '0');
        expect(formatUnreadBadgeLabel(1), '1');
        expect(formatUnreadBadgeLabel(16), '16');
      });

      test('affiche 99+ au-delà de 99 (ex. 120)', () {
        expect(formatUnreadBadgeLabel(99), '99');
        expect(formatUnreadBadgeLabel(120), '99+');
      });
    },
  );
}
