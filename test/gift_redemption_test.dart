import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/gift_redemption.dart';

void main() {
  group('GiftRedemption.fromFirestore', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('statut absent retombe sur pending', () async {
      final ref = firestore.collection('giftRedemptions').doc('r1');
      await ref.set({
        'buyerId': 'buyer1',
        'sellerId': 'seller1',
        'itemId': 'item1',
        'itemTitle': 'Casquette',
        'pointsCost': 250,
      });

      final redemption = GiftRedemption.fromFirestore(await ref.get());

      expect(redemption.status, GiftRedemptionStatus.pending);
      expect(redemption.reviewedBy, isNull);
    });

    test('lit un statut connu', () async {
      final ref = firestore.collection('giftRedemptions').doc('r1');
      await ref.set({
        'buyerId': 'buyer1',
        'sellerId': 'seller1',
        'itemId': 'item1',
        'itemTitle': 'Casquette',
        'pointsCost': 250,
        'status': 'fulfilled',
        'reviewedBy': 'seller1',
      });

      final redemption = GiftRedemption.fromFirestore(await ref.get());

      expect(redemption.status, GiftRedemptionStatus.fulfilled);
      expect(redemption.reviewedBy, 'seller1');
    });
  });
}
