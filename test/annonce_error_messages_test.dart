import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/annonce/screens/create_annonce_screen.dart';
import 'package:occasion/models/annonce.dart';

void main() {
  group('friendlyAnnonceError', () {
    test('un refus serveur ne parle plus de « compte propriétaire » mais '
        'de session / compte vendeur', () {
      final message = friendlyAnnonceError(
        Exception('[cloud_firestore/permission-denied] Missing permissions'),
      );
      expect(message, isNot(contains('propriétaire')));
      expect(message, contains('compte vendeur'));
    });

    test('une erreur de validation est affichée lisiblement', () {
      expect(
        friendlyAnnonceError(
          ArgumentError('titre trop long (160 caractères maximum)'),
        ),
        'Titre trop long (160 caractères maximum)',
      );
    });

    test('un échec d’envoi de photo est expliqué', () {
      expect(
        friendlyAnnonceError(Exception('[firebase_storage/unauthorized] x')),
        contains('photo'),
      );
    });
  });

  test('Annonce.validate refuse un titre trop long AVANT l’envoi (même '
      'plafond que firestore.rules)', () {
    final annonce = Annonce(
      id: 'a',
      title: 'x' * (Annonce.maxTitleLength + 1),
      description: 'd',
      price: 10,
      currency: 'USD',
      category: 'Mode',
      userId: 'u',
      imageUrls: const [],
      city: 'Likasi',
    );
    expect(
      annonce.validate,
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('titre trop long'),
        ),
      ),
    );
  });
}
