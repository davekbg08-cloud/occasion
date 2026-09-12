import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/favoris/providers/favoris_provider.dart';

void main() {
  group('FavorisNotifier', () {
    late FakeFirebaseFirestore firestore;
    const userId = 'user1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test(
      'loadFavoris retrouve un favori déjà persisté (régression : la '
      'requête doit filtrer sur "utilisateurId", le champ réellement écrit '
      'par toggleFavori, pas sur "userId" qui n\'existe dans aucun document)',
      () async {
        await firestore.collection('favoris').add({
          'utilisateurId': userId,
          'annonceId': 'annonce1',
          'dateAjout': DateTime.now(),
        });

        final notifier = FavorisNotifier(userId: userId, firestore: firestore);
        await notifier.loadFavoris();

        expect(notifier.state, hasLength(1));
        expect(notifier.state.first.annonceId, 'annonce1');
      },
    );

    test('toggleFavori ajoute puis retire un favori', () async {
      final notifier = FavorisNotifier(userId: userId, firestore: firestore);

      await notifier.toggleFavori('annonce1');
      expect(notifier.isFavorite('annonce1'), isTrue);

      final snapshotAfterAdd = await firestore.collection('favoris').get();
      expect(snapshotAfterAdd.docs, hasLength(1));
      expect(snapshotAfterAdd.docs.first.data()['utilisateurId'], userId);

      await notifier.toggleFavori('annonce1');
      expect(notifier.isFavorite('annonce1'), isFalse);

      final snapshotAfterRemove = await firestore.collection('favoris').get();
      expect(snapshotAfterRemove.docs, isEmpty);
    });

    test('un favori ajouté via toggleFavori est retrouvé par un nouveau '
        'chargement (bout en bout, comme un redémarrage de l\'app)', () async {
      final notifier = FavorisNotifier(userId: userId, firestore: firestore);
      await notifier.toggleFavori('annonce1');

      final reloaded = FavorisNotifier(userId: userId, firestore: firestore);
      await reloaded.loadFavoris();

      expect(reloaded.state, hasLength(1));
      expect(reloaded.state.first.annonceId, 'annonce1');
    });
  });
}
