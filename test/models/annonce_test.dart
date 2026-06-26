import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/shared/models/annonce.dart';

void main() {
  test('Annonce creation with images', () {
    const annonce = Annonce(
      id: '123',
      title: 'iPhone 12',
      description: 'Très bon état',
      price: 450,
      category: 'Téléphones',
      userId: 'user1',
      imageUrls: ['img1.jpg', 'img2.jpg'],
    );

    expect(annonce.title, 'iPhone 12');
    expect(annonce.imageUrls.length, 2);
    expect(annonce.price, 450);
    expect(annonce.currency, 'USD');
    expect(annonce.isActive, isTrue);
  });

  test('Annonce copyWith updates values safely', () {
    const annonce = Annonce(
      id: '123',
      title: 'iPhone 12',
      description: 'Très bon état',
      price: 450,
      category: 'Téléphones',
      userId: 'user1',
    );

    final updated = annonce.copyWith(price: 430, currency: 'FC');

    expect(updated.id, annonce.id);
    expect(updated.price, 430);
    expect(updated.currency, 'FC');
  });
}
