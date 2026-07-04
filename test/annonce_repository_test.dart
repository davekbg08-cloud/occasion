import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mockito/mockito.dart';
import 'package:occasion/annonce/data/annonce_repository.dart';
import 'package:occasion/shared/models/annonce.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

Annonce _baseAnnonce({required String userId}) => Annonce(
  id: '',
  title: 'Annonce test',
  description: 'Description test',
  price: 100,
  category: 'Divers',
  userId: userId,
);

void main() {
  group('AnnonceRepositoryImpl - limites photos et annonces actives', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late AnnonceRepositoryImpl repository;
    const sellerId = 'user1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: sellerId));
      repository = AnnonceRepositoryImpl(
        firestore: firestore,
        auth: auth,
        storage: MockFirebaseStorage(),
      );
    });

    test('formule gratuite : refuse plus de 2 photos', () async {
      final images = List.generate(3, (_) => XFile(''));
      await expectLater(
        repository.createAnnonce(_baseAnnonce(userId: sellerId), images),
        throwsA(isA<Exception>()),
      );
    });

    test('formule gratuite : refuse une 2e annonce active', () async {
      await firestore.collection('annonces').add({
        'vendeurId': sellerId,
        'isPublished': true,
        'status': 'published',
        'active': true,
      });

      final images = [XFile('')];
      await expectLater(
        repository.createAnnonce(_baseAnnonce(userId: sellerId), images),
        throwsA(
          predicate<Exception>(
            (e) => e.toString().contains('1 annonce active maximum'),
          ),
        ),
      );
    });

    test('avec abonnement vendeur actif : refuse plus de 5 photos', () async {
      await firestore.collection('subscriptions').doc(sellerId).set({
        'isActive': true,
        'expiryDate': DateTime.now().add(const Duration(days: 30)),
      });

      final images = List.generate(6, (_) => XFile(''));
      await expectLater(
        repository.createAnnonce(_baseAnnonce(userId: sellerId), images),
        throwsA(
          predicate<Exception>(
            (e) => e.toString().contains('jusqu’à 5 photos'),
          ),
        ),
      );
    });

    test(
      'avec abonnement vendeur actif : pas de limite à 1 annonce active',
      () async {
        await firestore.collection('subscriptions').doc(sellerId).set({
          'isActive': true,
          'expiryDate': DateTime.now().add(const Duration(days: 30)),
        });
        await firestore.collection('annonces').add({
          'vendeurId': sellerId,
          'isPublished': true,
          'status': 'published',
          'active': true,
        });

        // Va échouer plus loin (lecture du fichier photo factice), mais ce
        // qui nous intéresse ici est que ce ne soit PAS le contrôle de
        // limite d'annonces actives qui bloque, une fois abonné.
        final images = [XFile('')];
        var reachedBeyondLimitCheck = false;
        try {
          await repository.createAnnonce(_baseAnnonce(userId: sellerId), images);
        } catch (e) {
          expect(e.toString(), isNot(contains('1 annonce active maximum')));
          reachedBeyondLimitCheck = true;
        }
        expect(reachedBeyondLimitCheck, isTrue);
      },
    );
  });
}
