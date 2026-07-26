import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/gift_catalog_item.dart';

void main() {
  group('GiftCatalogItem.fromFirestore', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('valeurs par défaut si champs absents', () async {
      final ref = firestore.collection('giftCatalogItems').doc('item1');
      await ref.set({'sellerId': 'seller1', 'title': 'Casquette'});

      final item = GiftCatalogItem.fromFirestore(await ref.get());

      expect(item.id, 'item1');
      expect(item.sellerId, 'seller1');
      expect(item.title, 'Casquette');
      expect(item.description, isEmpty);
      expect(item.pointsCost, 0);
      expect(item.isActive, isTrue);
    });

    test('lit tous les champs', () async {
      final ref = firestore.collection('giftCatalogItems').doc('item1');
      await ref.set({
        'sellerId': 'seller1',
        'title': 'Casquette',
        'description': 'Casquette brodée',
        'imageUrl': 'https://example.com/cap.jpg',
        'pointsCost': 250,
        'isActive': false,
        'createdAt': DateTime(2026, 1, 1),
      });

      final item = GiftCatalogItem.fromFirestore(await ref.get());

      expect(item.description, 'Casquette brodée');
      expect(item.pointsCost, 250);
      expect(item.isActive, isFalse);
      expect(item.createdAt, isNotNull);
    });

    test('toFirestore ne réécrit pas id/createdAt', () {
      const item = GiftCatalogItem(
        id: 'item1',
        sellerId: 'seller1',
        title: 'Casquette',
        pointsCost: 250,
      );
      final map = item.toFirestore();
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
      expect(map['pointsCost'], 250);
    });

    test('toFirestore omet imageUrl si absent (jamais null explicite)', () {
      const item = GiftCatalogItem(
        id: 'item1',
        sellerId: 'seller1',
        title: 'Casquette',
        pointsCost: 250,
      );
      // Les règles Firestore valident un champ présent comme devant être
      // une string : écrire `imageUrl: null` échouerait la validation.
      expect(item.toFirestore().containsKey('imageUrl'), isFalse);
    });
  });
}
