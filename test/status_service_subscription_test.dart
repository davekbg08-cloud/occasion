import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mockito/mockito.dart';
import 'package:occasion/models/status.dart';
import 'package:occasion/services/status_service.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

void main() {
  group('StatusService.createStatus - exige un abonnement vendeur actif', () {
    late FakeFirebaseFirestore firestore;
    late StatusService service;
    const sellerId = 'seller1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = StatusService(firestore, MockFirebaseStorage());
    });

    Future<Object> publishAndCaptureError() async {
      try {
        await service.createStatus(
          sellerId: sellerId,
          sellerName: 'Vendeur test',
          mediaFile: XFile(''),
          type: StatusType.image,
        );
      } catch (e) {
        return e;
      }
      throw StateError('createStatus aurait dû échouer');
    }

    test('refuse la publication sans abonnement', () async {
      final error = await publishAndCaptureError();
      expect(error.toString(), contains('abonnement'));
    });

    test('refuse la publication avec un abonnement expiré', () async {
      await firestore.collection('subscriptions').doc(sellerId).set({
        'isActive': true,
        'expiryDate': DateTime.now().subtract(const Duration(days: 1)),
      });

      final error = await publishAndCaptureError();
      expect(error.toString(), contains('abonnement'));
    });

    test(
      "avec un abonnement actif : la vérification d'abonnement n'est pas ce qui bloque",
      () async {
        await firestore.collection('subscriptions').doc(sellerId).set({
          'isActive': true,
          'expiryDate': DateTime.now().add(const Duration(days: 30)),
        });

        final error = await publishAndCaptureError();
        expect(error.toString(), isNot(contains('abonnement')));
      },
    );
  });
}
