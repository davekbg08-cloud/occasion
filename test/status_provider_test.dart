import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/providers/status_provider.dart';
import 'package:occasion/services/status_service.dart';

/// Simule le comportement réel de Firestore `snapshots()` sur une
/// connexion instable : ni données, ni erreur, jamais — exactement le
/// symptôme observé en prod (`ERR_NAME_NOT_RESOLVED` récurrent) qui
/// laissait auparavant le feed bloqué en chargement infini.
class _NeverEmittingStatusService extends StatusService {
  @override
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> feed({
    int pageSize = StatusService.feedPageSize,
  }) {
    return const Stream.empty();
  }
}

/// `toggleLike()` ne se résout que lorsque le test appelle [resolve] —
/// simule le délai réel d'un aller-retour vers la Cloud Function, pendant
/// lequel une réémission du flux `feed()` (déclenchée en modifiant le doc
/// via la même instance Firestore que [StatusService] observe) peut
/// arriver et tenter d'écraser la mise à jour optimiste.
class _ControllableLikeStatusService extends StatusService {
  // `StatusService`'s premier paramètre positionnel est un champ PRIVÉ
  // (`_firestore`) d'une autre bibliothèque : le raccourci `super.firestore`
  // exigerait un paramètre nommé `firestore` (sans tiret bas) sur le
  // constructeur parent, ce qui n'est pas le cas ici — l'appel explicite
  // reste nécessaire.
  // ignore: use_super_parameters
  _ControllableLikeStatusService(FirebaseFirestore firestore)
    : super(firestore);

  Completer<bool>? pendingToggle;

  @override
  Future<bool> toggleLike(String statusId) {
    final completer = Completer<bool>();
    pendingToggle = completer;
    return completer.future;
  }

  void resolve(bool liked) => pendingToggle!.complete(liked);
}

void main() {
  group('StatusNotifier.loadFeed', () {
    test('régression : un flux qui ne livre jamais rien ne laisse plus '
        'isLoading bloqué à true indéfiniment (bascule sur une erreur '
        'après le délai configuré)', () async {
      final notifier = StatusNotifier(
        service: _NeverEmittingStatusService(),
        loadTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(notifier.dispose);

      notifier.loadFeed();
      expect(notifier.state.isLoading, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.statuses, isEmpty);
    });

    test('retryLoadFeed relance le chargement après un timeout', () async {
      final notifier = StatusNotifier(
        service: _NeverEmittingStatusService(),
        loadTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(notifier.dispose);

      notifier.loadFeed();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(notifier.state.isLoading, isFalse);

      notifier.retryLoadFeed();
      expect(notifier.state.isLoading, isTrue);
    });
  });

  group('StatusNotifier.toggleLike', () {
    test(
      'régression : une réémission du flux pendant un toggleLike en vol '
      'ne doit pas écraser le compteur optimiste avec l\'ancienne valeur',
      () async {
        final firestore = FakeFirebaseFirestore();
        final docRef = await firestore.collection('statuses').add({
          'sellerId': 's1',
          'sellerName': 'Vendeur',
          'mediaUrl': 'https://example.com/x.jpg',
          'type': 'image',
          'likesCount': 5,
          'status': 'published',
          'active': true,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        final service = _ControllableLikeStatusService(firestore);
        final notifier = StatusNotifier(service: service);
        addTearDown(notifier.dispose);

        notifier.loadFeed();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(notifier.state.statuses.single.likesCount, 5);

        final toggleFuture = notifier.toggleLike(docRef.id);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(notifier.state.statuses.single.likesCount, 6);

        // Course : une réémission du listener arrive avec l'ANCIENNE
        // valeur pendant que le toggle est encore en vol côté serveur.
        await docRef.update({'likesCount': 5});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(notifier.state.statuses.single.likesCount, 6);

        service.resolve(true);
        await toggleFuture;

        // Une fois le toggle réglé, une réémission doit de nouveau être
        // prise en compte normalement.
        await docRef.update({'likesCount': 6});
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(notifier.state.statuses.single.likesCount, 6);
      },
    );
  });
}
