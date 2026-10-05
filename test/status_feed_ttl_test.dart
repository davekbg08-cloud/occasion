import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:occasion/services/status_service.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

void main() {
  group('StatusService.feed — un statut disparaît du fil après 72 h', () {
    late FakeFirebaseFirestore firestore;
    late StatusService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = StatusService(firestore, MockFirebaseStorage());
    });

    Future<void> seedStatus(String id, {required DateTime createdAt}) {
      // `createdAt` en millisecondes epoch (jamais un Timestamp) — même
      // format que Status.toMap()/fromMap(), sinon le filtre de
      // _feedCutoffMillis() ne matcherait rien (comparaison de types
      // différents, Firestore ne renvoie alors aucun résultat).
      return firestore.collection('statuses').doc(id).set({
        'id': id,
        'sellerId': 'seller1',
        'sellerName': 'Vendeur test',
        'mediaUrl': 'https://example.com/$id.jpg',
        'type': 'image',
        'active': true,
        'createdAt': createdAt.millisecondsSinceEpoch,
      });
    }

    test(
      'un statut vieux de plus de 72 h n\'apparaît plus dans le fil',
      () async {
        await seedStatus(
          'recent',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        );
        await seedStatus(
          'ancien',
          createdAt: DateTime.now().subtract(const Duration(hours: 73)),
        );

        final docs = await service.feed().first;
        final ids = docs.map((d) => d.id).toSet();

        expect(ids, contains('recent'));
        expect(ids, isNot(contains('ancien')));
      },
    );

    test(
      'un statut vieux de 71h59 reste visible (pas coupé trop tôt)',
      () async {
        await seedStatus(
          'presque-expire',
          createdAt: DateTime.now().subtract(
            const Duration(hours: 71, minutes: 59),
          ),
        );

        final docs = await service.feed().first;
        expect(docs.map((d) => d.id), contains('presque-expire'));
      },
    );

    test('fetchMoreFeed applique le même filtre de 72 h', () async {
      await seedStatus(
        'recent-1',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await seedStatus(
        'recent-2',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await seedStatus(
        'ancien',
        createdAt: DateTime.now().subtract(const Duration(hours: 96)),
      );

      final firstPage = await service.feed().first;
      final after = firstPage.last;
      final nextPage = await service.fetchMoreFeed(after: after);

      final allIds = {
        ...firstPage.map((d) => d.id),
        ...nextPage.map((d) => d.id),
      };
      expect(allIds, isNot(contains('ancien')));
    });
  });
}
