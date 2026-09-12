import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/price_history_entry.dart';

void main() {
  group('PriceHistoryEntry', () {
    test('fromJson lit tous les champs', () {
      final entry = PriceHistoryEntry.fromJson({
        'oldPrice': 1000,
        'newPrice': 800,
        'currency': 'FC',
        'changedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      expect(entry.oldPrice, 1000.0);
      expect(entry.newPrice, 800.0);
      expect(entry.currency, 'FC');
      expect(entry.changedAt?.toUtc(), DateTime.utc(2026, 1, 1));
    });

    test('isDecrease vrai uniquement si le nouveau prix est inférieur', () {
      const decrease = PriceHistoryEntry(
        oldPrice: 1000,
        newPrice: 800,
        currency: 'FC',
        changedAt: null,
      );
      const increase = PriceHistoryEntry(
        oldPrice: 800,
        newPrice: 1000,
        currency: 'FC',
        changedAt: null,
      );

      expect(decrease.isDecrease, isTrue);
      expect(increase.isDecrease, isFalse);
    });

    test('valeurs par défaut honnêtes si des champs sont absents', () {
      final entry = PriceHistoryEntry.fromJson(const {});

      expect(entry.oldPrice, 0);
      expect(entry.newPrice, 0);
      expect(entry.currency, 'FC');
      expect(entry.changedAt, isNull);
    });
  });
}
