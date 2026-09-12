import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/services/account_deletion_service.dart';

void main() {
  group('AccountDeletionService', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late AccountDeletionService service;
    const userId = 'user1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: userId));
      service = AccountDeletionService(
        firestore: firestore,
        firebaseAuth: auth,
      );
    });

    test(
      'anonymise le profil (nom, téléphone, photo) et le marque isDeleted',
      () async {
        await firestore.collection('users').doc(userId).set({
          'name': 'Alice',
          'phone': '+243800000000',
        });

        await service.deleteAccount(userId);

        final userDoc = await firestore.collection('users').doc(userId).get();
        expect(userDoc.data()!['name'], 'Utilisateur supprimé');
        expect(userDoc.data()!['phone'], '');
        expect(userDoc.data()!['profileImageUrl'], isNull);
        expect(userDoc.data()!['isDeleted'], isTrue);
      },
    );

    test(
      'supprime les annonces du vendeur dans la collection annonces '
      '(régression : ne doit plus interroger l\'ancienne collection '
      '"products", qui n\'est jamais écrite par le reste de l\'app)',
      () async {
        await firestore.collection('annonces').add({
          'vendeurId': userId,
          'titre': 'Vélo',
        });
        await firestore.collection('annonces').add({
          'vendeurId': 'autreVendeur',
          'titre': 'Pas concerné',
        });

        await service.deleteAccount(userId);

        final remaining = await firestore.collection('annonces').get();
        expect(remaining.docs, hasLength(1));
        expect(remaining.docs.first.data()['vendeurId'], 'autreVendeur');
      },
    );

    test('vide blockedUsers et devices du compte supprimé', () async {
      final userRef = firestore.collection('users').doc(userId);
      await userRef.collection('blockedUsers').doc('other1').set({
        'userId': 'other1',
      });
      await userRef.collection('devices').doc('device1').set({'token': 'abc'});

      await service.deleteAccount(userId);

      final blocked = await userRef.collection('blockedUsers').get();
      final devices = await userRef.collection('devices').get();
      expect(blocked.docs, isEmpty);
      expect(devices.docs, isEmpty);
    });

    test('anonymise le nom affiché dans les conversations existantes '
        '(régression : Chat.otherUserName lit buyerName/sellerName '
        'dénormalisés sur le chat, jamais users/{uid} en direct)', () async {
      await firestore.collection('chats').doc('chatAsBuyer').set({
        'buyerId': userId,
        'sellerId': 'seller1',
        'buyerName': 'Alice',
        'sellerName': 'Bob',
      });
      await firestore.collection('chats').doc('chatAsSeller').set({
        'buyerId': 'buyer1',
        'sellerId': userId,
        'buyerName': 'Carol',
        'sellerName': 'Alice',
      });
      await firestore.collection('chats').doc('unrelatedChat').set({
        'buyerId': 'buyer2',
        'sellerId': 'seller2',
        'buyerName': 'Dan',
        'sellerName': 'Eve',
      });

      await service.deleteAccount(userId);

      final chatAsBuyer = await firestore
          .collection('chats')
          .doc('chatAsBuyer')
          .get();
      expect(chatAsBuyer.data()!['buyerName'], 'Utilisateur supprimé');
      expect(chatAsBuyer.data()!['sellerName'], 'Bob');

      final chatAsSeller = await firestore
          .collection('chats')
          .doc('chatAsSeller')
          .get();
      expect(chatAsSeller.data()!['sellerName'], 'Utilisateur supprimé');
      expect(chatAsSeller.data()!['buyerName'], 'Carol');

      final unrelated = await firestore
          .collection('chats')
          .doc('unrelatedChat')
          .get();
      expect(unrelated.data()!['buyerName'], 'Dan');
      expect(unrelated.data()!['sellerName'], 'Eve');
    });

    test('supprime le compte Firebase Auth sans lever d\'exception', () async {
      // MockUser.delete() (firebase_auth_mocks) ne réinitialise pas
      // `auth.currentUser` — seul le vrai SDK le fait. On vérifie donc
      // que l'appel aboutit sans exception, ce qui couvre le vrai risque :
      // une `FirebaseAuthException` autre que `requires-recent-login`
      // ne doit jamais faire échouer `deleteAccount` silencieusement.
      await expectLater(service.deleteAccount(userId), completes);
    });
  });
}
