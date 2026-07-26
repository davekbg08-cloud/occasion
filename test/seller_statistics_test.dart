import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/seller_statistics.dart';

void main() {
  group('SellerStatistics.fromFirestore', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('valeurs par défaut à 0 si le document est vide', () async {
      final ref = firestore.collection('sellerStatistics').doc('seller1');
      await ref.set({});

      final snapshot = await ref.get();
      final statistics = SellerStatistics.fromFirestore(snapshot);

      expect(statistics.totalViews, 0);
      expect(statistics.totalMessages, 0);
      expect(statistics.totalSales, 0);
      expect(statistics.revenue, isEmpty);
      expect(statistics.loyaltyPoints, 0);
      expect(statistics.updatedAt, isNull);
    });

    test('lit tous les champs et le revenu par devise', () async {
      final ref = firestore.collection('sellerStatistics').doc('seller1');
      await ref.set({
        'totalViews': 42,
        'totalMessages': 7,
        'totalSales': 3,
        'revenue': {'FC': 15000, 'USD': 20},
        'loyaltyPoints': 18,
        'updatedAt': DateTime(2026, 1, 1),
      });

      final snapshot = await ref.get();
      final statistics = SellerStatistics.fromFirestore(snapshot);

      expect(statistics.totalViews, 42);
      expect(statistics.totalMessages, 7);
      expect(statistics.totalSales, 3);
      expect(statistics.revenue['FC'], 15000);
      expect(statistics.revenue['USD'], 20);
      expect(statistics.loyaltyPoints, 18);
      expect(statistics.updatedAt, isNotNull);
    });
  });
}
