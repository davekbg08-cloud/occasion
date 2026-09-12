import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/review.dart';

void main() {
  group('Review', () {
    test('fromJson lit tous les champs', () {
      final review = Review.fromJson({
        'orderId': 'order1',
        'sellerId': 'seller1',
        'reviewerId': 'buyer1',
        'revieweeId': 'seller1',
        'direction': 'buyer_to_seller',
        'rating': 5,
        'comment': 'Très bien',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'id': 'order1_seller1_buyer_to_seller',
      });

      expect(review.id, 'order1_seller1_buyer_to_seller');
      expect(review.orderId, 'order1');
      expect(review.sellerId, 'seller1');
      expect(review.reviewerId, 'buyer1');
      expect(review.revieweeId, 'seller1');
      expect(review.direction, 'buyer_to_seller');
      expect(review.rating, 5);
      expect(review.comment, 'Très bien');
      expect(review.createdAt?.toUtc(), DateTime.utc(2026, 1, 1));
    });

    test('valeurs par défaut honnêtes si des champs sont absents', () {
      final review = Review.fromJson(const {});

      expect(review.id, '');
      expect(review.rating, 0);
      expect(review.comment, '');
      expect(review.createdAt, isNull);
    });
  });
}
