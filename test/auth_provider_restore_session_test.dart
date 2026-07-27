import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:occasion/providers/auth_provider.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

// Firestore minimal qui échoue systématiquement sur `users/{uid}.get()` avec
// l'erreur donnée — pas besoin de stubbing Mockito (`when`/dummy values),
// juste les quelques méthodes réellement appelées par
// `AuthNotifier._restoreSession`. Fake minimal (2 méthodes implémentées) :
// implémenter ces classes scellées est nécessaire pour ce test.
// ignore: subtype_of_sealed_class
class _ThrowingDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _ThrowingDocumentReference(this.error);
  final Object error;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    throw error;
  }
}

// Même raison que _ThrowingDocumentReference ci-dessus.
// ignore: subtype_of_sealed_class
class _ThrowingCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _ThrowingCollectionReference(this.error);
  final Object error;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _ThrowingDocumentReference(error);
}

class _ThrowingFirestore extends Fake implements FirebaseFirestore {
  _ThrowingFirestore(this.error);
  final Object error;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _ThrowingCollectionReference(error);
}

void main() {
  const uid = 'user1';

  /// Attend que l'écoute asynchrone de `authStateChanges()` (déclenchée à la
  /// construction de `AuthNotifier`) ait eu le temps de s'exécuter, y
  /// compris les 3 tentatives avec délais (jusqu'à ~1.3s au total).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 1600));

  test("une erreur réseau persistante ne déconnecte pas l'utilisateur et ne "
      'force pas isAuthenticated à false de façon permanente', () async {
    final firestore = _ThrowingFirestore(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'buyer@test.com'),
    );
    final notifier = AuthNotifier(
      auth: auth,
      firestore: firestore,
      storage: MockFirebaseStorage(),
    );
    await settle();

    // La session Firebase Auth n'a jamais été coupée : c'est le signal
    // utilisé par l'UI (_AuthGate) pour proposer "Réessayer" plutôt que
    // de renvoyer vers l'écran de connexion.
    expect(auth.currentUser, isNotNull);
    expect(notifier.state.errorMessage, 'Connexion indisponible, réessayez.');
    expect(notifier.state.isLoading, isFalse);
  });

  test('un profil réellement absent (jamais trouvé après 3 tentatives sans '
      "erreur) déconnecte bien l'utilisateur", () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'buyer@test.com'),
    );
    final notifier = AuthNotifier(
      auth: auth,
      firestore: firestore,
      storage: MockFirebaseStorage(),
    );
    await settle();

    expect(auth.currentUser, isNull);
    expect(notifier.state.isAuthenticated, isFalse);
    expect(
      notifier.state.errorMessage,
      contains('Profil Occasion introuvable'),
    );
  });

  test(
    'un profil trouvé dès la première tentative authentifie normalement',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc(uid).set({
        'name': 'Acheteur test',
        'email': 'buyer@test.com',
        'role': 'buyer',
      });
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: 'buyer@test.com'),
      );
      final notifier = AuthNotifier(
        auth: auth,
        firestore: firestore,
        storage: MockFirebaseStorage(),
      );
      await settle();

      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.currentUser?.id, uid);
      expect(notifier.state.errorMessage, isNull);
    },
  );
}
