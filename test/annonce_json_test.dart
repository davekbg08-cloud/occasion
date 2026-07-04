import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/annonce.dart';

void main() {
  group('Annonce JSON round-trip', () {
    test('toJson -> fromJson préserve les champs', () {
      final original = Annonce(
        id: 'a1',
        title: 'iPhone 13',
        description: 'Bon état, boîte incluse',
        price: 450.5,
        currency: 'USD',
        category: 'Téléphones',
        userId: 'user1',
        imageUrls: const ['https://example.com/1.jpg'],
        location: 'Kinshasa, Gombe',
        city: 'Kinshasa',
        district: 'Gombe',
        brand: 'Apple',
        model: '13',
        year: 2021,
        condition: 'Bon état',
        phone: '+243800000000',
        status: 'published',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        isActive: true,
        views: 10,
        favoritesCount: 3,
        messagesCount: 1,
      );

      final roundTripped = Annonce.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.title, original.title);
      expect(roundTripped.description, original.description);
      expect(roundTripped.price, original.price);
      expect(roundTripped.currency, original.currency);
      expect(roundTripped.category, original.category);
      expect(roundTripped.userId, original.userId);
      expect(roundTripped.imageUrls, original.imageUrls);
      expect(roundTripped.location, original.location);
      expect(roundTripped.city, original.city);
      expect(roundTripped.district, original.district);
      expect(roundTripped.brand, original.brand);
      expect(roundTripped.model, original.model);
      expect(roundTripped.year, original.year);
      expect(roundTripped.condition, original.condition);
      expect(roundTripped.phone, original.phone);
      expect(roundTripped.status, original.status);
      expect(roundTripped.createdAt, original.createdAt);
      expect(roundTripped.updatedAt, original.updatedAt);
      expect(roundTripped.isActive, original.isActive);
      expect(roundTripped.views, original.views);
      expect(roundTripped.favoritesCount, original.favoritesCount);
      expect(roundTripped.messagesCount, original.messagesCount);
    });

    test('fromJson accepte les champs hérités en français', () {
      final annonce = Annonce.fromJson({
        'id': 'a2',
        'titre': 'Vélo',
        'description': 'Vélo de ville',
        'prix': 120,
        'devise': 'USD',
        'categorie': 'Vélos',
        'vendeurId': 'user2',
        'images': ['https://example.com/2.jpg'],
        'ville': 'Lubumbashi',
        'quartier': 'Centre',
        'statut': 'active',
      });

      expect(annonce.title, 'Vélo');
      expect(annonce.price, 120.0);
      expect(annonce.category, 'Vélos');
      expect(annonce.userId, 'user2');
      expect(annonce.city, 'Lubumbashi');
      expect(annonce.district, 'Centre');
      expect(annonce.isActive, true);
    });
  });
}
