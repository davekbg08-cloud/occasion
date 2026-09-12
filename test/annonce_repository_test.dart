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
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: sellerId),
      );
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
          await repository.createAnnonce(
            _baseAnnonce(userId: sellerId),
            images,
          );
        } catch (e) {
          expect(e.toString(), isNot(contains('1 annonce active maximum')));
          reachedBeyondLimitCheck = true;
        }
        expect(reachedBeyondLimitCheck, isTrue);
      },
    );

    test('updateSaleState modifie uniquement le saleState', () async {
      final docRef = await firestore
          .collection('annonces')
          .add(_baseAnnonce(userId: sellerId).toJson());
      final created = Annonce.fromJson({
        ...(await docRef.get()).data()!,
        'id': docRef.id,
      });

      final updated = await repository.updateSaleState(created, 'sold');

      expect(updated.saleState, 'sold');
      expect(updated.title, created.title);
    });
  });

  group('AnnonceRepositoryImpl - filtre ville', () {
    late FakeFirebaseFirestore firestore;
    late AnnonceRepositoryImpl repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = AnnonceRepositoryImpl(
        firestore: firestore,
        auth: MockFirebaseAuth(),
        storage: MockFirebaseStorage(),
      );
    });

    test('getAnnonces filtre par ville quand city est renseigné', () async {
      await firestore.collection('annonces').add({
        'vendeurId': 'seller1',
        'titre': 'Annonce Lubumbashi',
        'isPublished': true,
        'status': 'published',
        'active': true,
        'ville': 'Lubumbashi',
        'dateCreation': DateTime.now(),
      });
      await firestore.collection('annonces').add({
        'vendeurId': 'seller2',
        'titre': 'Annonce Kinshasa',
        'isPublished': true,
        'status': 'published',
        'active': true,
        'ville': 'Kinshasa',
        'dateCreation': DateTime.now(),
      });

      final results = await repository.getAnnonces(city: 'Lubumbashi');

      expect(results, hasLength(1));
      expect(results.first.city, 'Lubumbashi');
    });

    test(
      'getAnnonces sans city retourne toutes les annonces publiées',
      () async {
        await firestore.collection('annonces').add({
          'vendeurId': 'seller1',
          'titre': 'Annonce Lubumbashi',
          'isPublished': true,
          'status': 'published',
          'active': true,
          'ville': 'Lubumbashi',
          'dateCreation': DateTime.now(),
        });
        await firestore.collection('annonces').add({
          'vendeurId': 'seller2',
          'titre': 'Annonce Kinshasa',
          'isPublished': true,
          'status': 'published',
          'active': true,
          'ville': 'Kinshasa',
          'dateCreation': DateTime.now(),
        });

        final results = await repository.getAnnonces();

        expect(results, hasLength(2));
      },
    );
  });
}
