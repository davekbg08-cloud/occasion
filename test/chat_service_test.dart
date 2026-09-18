import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/services/chat_service.dart';

void main() {
  group('ChatService.getOrCreateChat', () {
    late FakeFirebaseFirestore firestore;
    late ChatService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ChatService(firestore);
    });

    Future<void> seedAnnonce(String id, {int messagesCount = 0}) {
      return firestore.collection('annonces').doc(id).set({
        'messagesCount': messagesCount,
      });
    }

    test('régression : contacter le même vendeur avec puis sans listingId '
        'retombe sur le même fil (jamais un doublon)', () async {
      final withListing = await service.getOrCreateChat(
        buyerId: 'buyer1',
        sellerId: 'seller1',
        buyerName: 'Acheteur',
        sellerName: 'Vendeur',
        listingId: 'annonce1',
      );
      final withoutListing = await service.getOrCreateChat(
        buyerId: 'buyer1',
        sellerId: 'seller1',
        buyerName: 'Acheteur',
        sellerName: 'Vendeur',
      );

      expect(withoutListing.id, withListing.id);
      final all = await firestore.collection('chats').get();
      expect(all.docs, hasLength(1));
    });

    test(
      'régression : deux listingId différents successifs restent un seul fil',
      () async {
        final first = await service.getOrCreateChat(
          buyerId: 'buyer1',
          sellerId: 'seller1',
          buyerName: 'Acheteur',
          sellerName: 'Vendeur',
          listingId: 'annonceA',
        );
        final second = await service.getOrCreateChat(
          buyerId: 'buyer1',
          sellerId: 'seller1',
          buyerName: 'Acheteur',
          sellerName: 'Vendeur',
          listingId: 'annonceB',
        );

        expect(second.id, first.id);
        final all = await firestore.collection('chats').get();
        expect(all.docs, hasLength(1));
        expect(second.listingId, 'annonceB');
      },
    );

    test('l\'ordre acheteur/vendeur inversé donne le même id de fil', () async {
      final chat1 = await service.getOrCreateChat(
        buyerId: 'buyer1',
        sellerId: 'seller1',
        buyerName: 'Acheteur',
        sellerName: 'Vendeur',
      );

      final serviceAsSeller = ChatService(firestore);
      final chat2 = await serviceAsSeller.getOrCreateChat(
        buyerId: 'seller1',
        sellerId: 'buyer1',
        buyerName: 'Vendeur',
        sellerName: 'Acheteur',
      );

      expect(chat2.id, chat1.id);
    });

    test(
      'la création d\'un nouveau fil avec listingId incrémente messagesCount',
      () async {
        await seedAnnonce('annonce1');

        await service.getOrCreateChat(
          buyerId: 'buyer1',
          sellerId: 'seller1',
          buyerName: 'Acheteur',
          sellerName: 'Vendeur',
          listingId: 'annonce1',
        );

        final snap = await firestore
            .collection('annonces')
            .doc('annonce1')
            .get();
        expect(snap.data()!['messagesCount'], 1);
      },
    );

    test(
      'régression : un changement de listingId sur un fil déjà existant '
      'incrémente aussi messagesCount (nouvel intérêt pour un autre produit)',
      () async {
        await seedAnnonce('annonceA');
        await seedAnnonce('annonceB');

        await service.getOrCreateChat(
          buyerId: 'buyer1',
          sellerId: 'seller1',
          buyerName: 'Acheteur',
          sellerName: 'Vendeur',
          listingId: 'annonceA',
        );
        await service.getOrCreateChat(
          buyerId: 'buyer1',
          sellerId: 'seller1',
          buyerName: 'Acheteur',
          sellerName: 'Vendeur',
          listingId: 'annonceB',
        );

        final snapA = await firestore
            .collection('annonces')
            .doc('annonceA')
            .get();
        final snapB = await firestore
            .collection('annonces')
            .doc('annonceB')
            .get();
        expect(snapA.data()!['messagesCount'], 1);
        expect(snapB.data()!['messagesCount'], 1);
      },
    );

    test('régression : repasser le même listingId ne réincrémente jamais '
        'messagesCount (jamais de double comptage)', () async {
      await seedAnnonce('annonce1');

      await service.getOrCreateChat(
        buyerId: 'buyer1',
        sellerId: 'seller1',
        buyerName: 'Acheteur',
        sellerName: 'Vendeur',
        listingId: 'annonce1',
      );
      await service.getOrCreateChat(
        buyerId: 'buyer1',
        sellerId: 'seller1',
        buyerName: 'Acheteur',
        sellerName: 'Vendeur',
        listingId: 'annonce1',
      );

      final snap = await firestore.collection('annonces').doc('annonce1').get();
      expect(snap.data()!['messagesCount'], 1);
    });

    test(
      'omettre listingId sur un appel ultérieur ne touche ni ne réinitialise '
      'le listingId déjà stocké, et n\'incrémente rien',
      () async {
        await seedAnnonce('annonce1');

        await service.getOrCreateChat(
          buyerId: 'buyer1',
          sellerId: 'seller1',
          buyerName: 'Acheteur',
          sellerName: 'Vendeur',
          listingId: 'annonce1',
        );
        final result = await service.getOrCreateChat(
          buyerId: 'buyer1',
          sellerId: 'seller1',
          buyerName: 'Acheteur',
          sellerName: 'Vendeur',
        );

        expect(result.listingId, 'annonce1');
        final snap = await firestore
            .collection('annonces')
            .doc('annonce1')
            .get();
        expect(snap.data()!['messagesCount'], 1);
      },
    );
  });
}
