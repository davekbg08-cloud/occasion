import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/loyalty_points.dart';

void main() {
  group('BuyerLoyaltyPoints.fromFirestore', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('valeurs par défaut à 0 si le document est vide', () async {
      final ref = firestore.collection('loyaltyPoints').doc('buyer1_seller1');
      await ref.set({});

      final points = BuyerLoyaltyPoints.fromFirestore(await ref.get());

      expect(points.balance, 0);
      expect(points.lifetimeEarned, 0);
      expect(points.lifetimeRedeemed, 0);
      expect(points.updatedAt, isNull);
    });

    test('lit tous les champs', () async {
      final ref = firestore.collection('loyaltyPoints').doc('buyer1_seller1');
      await ref.set({
        'buyerId': 'buyer1',
        'sellerId': 'seller1',
        'balance': 40,
        'lifetimeEarned': 100,
        'lifetimeRedeemed': 60,
        'updatedAt': DateTime(2026, 1, 1),
      });

      final points = BuyerLoyaltyPoints.fromFirestore(await ref.get());

      expect(points.buyerId, 'buyer1');
      expect(points.sellerId, 'seller1');
      expect(points.balance, 40);
      expect(points.lifetimeEarned, 100);
      expect(points.lifetimeRedeemed, 60);
      expect(points.updatedAt, isNotNull);
    });
  });
}
