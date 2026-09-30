import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:occasion/providers/auth_provider.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

void main() {
  const uid = 'seller1';

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 1600));

  test('updateName modifie le nom sur users/{uid} ET publicProfiles/{uid}, et '
      'met à jour l\'état local immédiatement', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc(uid).set({
      'name': 'Ancien Nom',
      'phone': '+243800000000',
      'role': 'seller',
      'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
    });
    await firestore.collection('publicProfiles').doc(uid).set({
      'id': uid,
      'name': 'Ancien Nom',
      'role': 'seller',
    });

    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'seller@test.com'),
    );
    final notifier = AuthNotifier(
      auth: auth,
      firestore: firestore,
      storage: MockFirebaseStorage(),
    );
    await settle();
    expect(notifier.state.currentUser?.name, 'Ancien Nom');

    await notifier.updateName('  Nouveau Nom  ');

    // Recadré (trim) et reflété tout de suite dans l'état local, sans
    // attendre un rechargement.
    expect(notifier.state.currentUser?.name, 'Nouveau Nom');

    final usersDoc = await firestore.collection('users').doc(uid).get();
    expect(usersDoc.data()?['name'], 'Nouveau Nom');

    final publicDoc = await firestore
        .collection('publicProfiles')
        .doc(uid)
        .get();
    expect(publicDoc.data()?['name'], 'Nouveau Nom');
    // Le rôle (et le reste du miroir public) n'est jamais perdu au
    // passage, même écriture set(merge:true) que updateProfilePhoto.
    expect(publicDoc.data()?['role'], 'seller');
  });

  test('updateName refuse un nom vide (ou uniquement des espaces)', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc(uid).set({
      'name': 'Nom',
      'phone': '',
      'role': 'seller',
      'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
    });
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'seller@test.com'),
    );
    final notifier = AuthNotifier(
      auth: auth,
      firestore: firestore,
      storage: MockFirebaseStorage(),
    );
    await settle();

    await expectLater(notifier.updateName('   '), throwsArgumentError);
  });
}
