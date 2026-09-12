import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/utils/loyalty_points_estimate.dart';

void main() {
  group('estimateLoyaltyPoints', () {
    test(
      'FC : 1 point pour 1000 FC (même taux que pointsForAmount côté serveur)',
      () {
        expect(estimateLoyaltyPoints(15000, 'FC'), 15);
        expect(estimateLoyaltyPoints(999, 'FC'), 0);
      },
    );

    test('USD : 1 point pour 1 USD', () {
      expect(estimateLoyaltyPoints(45, 'USD'), 45);
      expect(estimateLoyaltyPoints(45.9, 'USD'), 45);
    });

    test('devise non prise en charge : retourne 0, jamais une exception', () {
      expect(estimateLoyaltyPoints(1000, 'EUR'), 0);
    });

    test('prix nul ou négatif : retourne 0', () {
      expect(estimateLoyaltyPoints(0, 'USD'), 0);
      expect(estimateLoyaltyPoints(-10, 'USD'), 0);
    });
  });
}
