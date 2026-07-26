import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/annonce.dart';
import 'package:occasion/models/user.dart';
import 'package:occasion/providers/product_provider.dart';

Annonce _annonce({List<String> imageUrls = const ['a.jpg', 'b.jpg']}) {
  return Annonce(
    id: 'annonce1',
    title: 'Vélo',
    description: 'Vélo en bon état',
    price: 100,
    currency: 'USD',
    category: 'Sport',
    userId: 'seller1',
    imageUrls: imageUrls,
    phone: '+243800000000',
  );
}

void main() {
  group('annonceToProductModel', () {
    test('sans profil vendeur : valeurs par défaut honnêtes', () {
      final product = annonceToProductModel(_annonce(), null);

      expect(product.id, 'annonce1');
      expect(product.name, 'Vélo');
      expect(product.currency, 'USD');
      expect(product.imageUrl, 'a.jpg');
      expect(product.sellerId, 'seller1');
      expect(product.sellerName, 'Vendeur');
      expect(product.isSellerVerified, isFalse);
      expect(product.isSellerPhoneVerified, isFalse);
      expect(product.sellerCreatedAt, isNull);
    });

    test(
      'avec profil vendeur : reprend les vraies infos (badges vérifiés)',
      () {
        final seller = UserModel(
          id: 'seller1',
          name: 'Awa',
          phone: '+243800000000',
          role: UserRole.seller,
          createdAt: DateTime(2024, 1, 1),
          identityStatus: SellerIdentityStatus.verified,
          phoneVerified: true,
        );

        final product = annonceToProductModel(_annonce(), seller);

        expect(product.sellerName, 'Awa');
        expect(product.isSellerVerified, isTrue);
        expect(product.isSellerPhoneVerified, isTrue);
        expect(product.sellerCreatedAt, DateTime(2024, 1, 1));
      },
    );

    test('annonce sans photo : imageUrl est null', () {
      final product = annonceToProductModel(_annonce(imageUrls: []), null);
      expect(product.imageUrl, isNull);
      expect(product.imageUrls, isEmpty);
    });
  });
}
