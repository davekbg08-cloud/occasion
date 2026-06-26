import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/annonce.dart';
import 'package:occasion/models/firestore/occasion_models.dart';
import 'package:occasion/repositories/occasion_firestore_repositories.dart';

void main() {
  group('AnnoncesCrudRepository', () {
    test(
      'ecrit et relit une annonce avec le schema Firestore francais',
      () async {
        final repository = AnnoncesCrudRepository(FakeFirebaseFirestore());

        final id = await repository.create(
          Annonce(
            id: '',
            title: 'Telephone',
            description: 'Tres bon etat',
            price: 120,
            currency: 'USD',
            category: 'Electronique',
            userId: 'vendeur-1',
            location: 'Kinshasa',
            phone: '+243000000000',
            status: 'active',
          ),
        );

        final annonce = await repository.get(id);

        expect(annonce, isNotNull);
        expect(annonce!.title, 'Telephone');
        expect(annonce.price, 120);
        expect(annonce.userId, 'vendeur-1');
      },
    );
  });

  group('MessagesOccasionRepository', () {
    test('ecrit et relit un message', () async {
      final repository = MessagesOccasionRepository(FakeFirebaseFirestore());

      final id = await repository.create(
        MessageOccasion(
          id: '',
          conversationId: 'conv-1',
          expediteurId: 'user-1',
          destinataireId: 'user-2',
          contenu: 'Bonjour',
          lu: false,
          dateEnvoi: DateTime.utc(2026, 6, 26),
        ),
      );

      final message = await repository.get(id);

      expect(message, isNotNull);
      expect(message!.conversationId, 'conv-1');
      expect(message.contenu, 'Bonjour');
      expect(message.lu, isFalse);
    });
  });
}
