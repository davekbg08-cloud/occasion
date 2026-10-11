import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/screens/product_list_screen.dart';

void main() {
  test('suggestions : titres réels, sans doublons ni vides, 8 au plus', () {
    final hints = homeSearchSuggestions([
      'pc',
      ' PC ',
      '',
      'chaussures',
      for (var i = 0; i < 20; i++) 'article $i',
    ]);
    expect(hints.first, 'pc');
    expect(hints[1], 'chaussures');
    expect(hints, hasLength(8));
  });

  test('sans annonce, des exemples par défaut', () {
    expect(homeSearchSuggestions(const []), isNotEmpty);
  });
}
