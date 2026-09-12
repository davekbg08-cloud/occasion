import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/search_alert.dart';
import 'package:occasion/services/search_alert_service.dart';

void main() {
  group('SearchAlert', () {
    test('label combine mot-clé/ville/catégorie renseignés', () {
      const alert = SearchAlert(
        id: 'a1',
        userId: 'buyer1',
        keyword: 'iphone',
        city: 'Lubumbashi',
        category: 'Téléphones',
      );

      expect(alert.label, '"iphone" · Lubumbashi · Téléphones');
    });

    test('label honnête si aucun critère renseigné', () {
      const alert = SearchAlert(id: 'a1', userId: 'buyer1');

      expect(alert.label, 'Toutes les nouvelles annonces');
    });

    test('toJson omet les champs vides', () {
      const alert = SearchAlert(id: 'a1', userId: 'buyer1', keyword: 'iphone');

      final json = alert.toJson();
      expect(json.containsKey('city'), isFalse);
      expect(json.containsKey('category'), isFalse);
      expect(json['keyword'], 'iphone');
    });
  });

  group('SearchAlertService', () {
    late FakeFirebaseFirestore firestore;
    late SearchAlertService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = SearchAlertService(firestore: firestore);
    });

    test('create puis watchForUser retrouve l\'alerte créée', () async {
      await service.create(
        userId: 'buyer1',
        keyword: 'iphone',
        city: 'Lubumbashi',
      );

      final alerts = await service.watchForUser('buyer1').first;

      expect(alerts, hasLength(1));
      expect(alerts.first.keyword, 'iphone');
      expect(alerts.first.city, 'Lubumbashi');
    });

    test(
      'watchForUser n\'expose jamais les alertes d\'un autre utilisateur',
      () async {
        await service.create(userId: 'buyer1', keyword: 'iphone');
        await service.create(userId: 'buyer2', keyword: 'vélo');

        final alerts = await service.watchForUser('buyer1').first;

        expect(alerts, hasLength(1));
        expect(alerts.first.userId, 'buyer1');
      },
    );

    test('delete retire bien l\'alerte', () async {
      await service.create(userId: 'buyer1', keyword: 'iphone');
      final alerts = await service.watchForUser('buyer1').first;
      final alertId = alerts.first.id;

      await service.delete(alertId);

      final remaining = await service.watchForUser('buyer1').first;
      expect(remaining, isEmpty);
    });

    test('create refuse un utilisateur non connecté', () async {
      await expectLater(
        service.create(userId: '', keyword: 'iphone'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
