import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:occasion/providers/auth_provider.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

/// Simule un appareil où le SDK natif Firebase Auth ne répond jamais (Google
/// Play Services obsolète/absent, entre autres causes réelles) :
/// `authStateChanges()` ne produit ni valeur ni erreur, pour toujours.
// ignore: subtype_of_sealed_class
class _NeverRespondingAuth extends Fake implements firebase_auth.FirebaseAuth {
  @override
  Stream<firebase_auth.User?> authStateChanges() => const Stream.empty();

  @override
  firebase_auth.User? get currentUser => null;
}

void main() {
  test('régression : authStateChanges() qui ne répond jamais ne bloque plus '
      "isLoading à true indéfiniment (l'app restait figée sur le logo) — "
      'un filet de 15s force un état actionnable', () {
    fakeAsync((async) {
      final notifier = AuthNotifier(
        auth: _NeverRespondingAuth(),
        firestore: FakeFirebaseFirestore(),
        storage: MockFirebaseStorage(),
      );

      expect(notifier.state.isLoading, isTrue);

      async.elapse(const Duration(seconds: 14));
      expect(
        notifier.state.isLoading,
        isTrue,
        reason: 'le filet de 15s ne doit pas se déclencher trop tôt',
      );

      async.elapse(const Duration(seconds: 2));
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, isNotNull);

      notifier.dispose();
    });
  });

  test('une réponse normale avant le filet de 15s annule bien le timeout '
      '(jamais de double écriture de state après)', () {
    fakeAsync((async) {
      final firestore = FakeFirebaseFirestore();
      final auth = _RespondingThenNeverAgainAuth();
      final notifier = AuthNotifier(
        auth: auth,
        firestore: firestore,
        storage: MockFirebaseStorage(),
      );

      async.elapse(const Duration(milliseconds: 1600));
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.isAuthenticated, isFalse);
      final errorAfterRestore = notifier.state.errorMessage;

      // Le filet de 15s ne doit jamais écraser un état déjà résolu.
      async.elapse(const Duration(seconds: 15));
      expect(notifier.state.errorMessage, errorAfterRestore);

      notifier.dispose();
    });
  });
}

// ignore: subtype_of_sealed_class
class _RespondingThenNeverAgainAuth extends Fake
    implements firebase_auth.FirebaseAuth {
  @override
  Stream<firebase_auth.User?> authStateChanges() => Stream.value(null);

  @override
  firebase_auth.User? get currentUser => null;
}
