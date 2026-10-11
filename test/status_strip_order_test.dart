import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/status.dart';
import 'package:occasion/widgets/status_strip.dart';

Status _status(String sellerId) => Status(
  id: 'st_$sellerId',
  sellerId: sellerId,
  sellerName: sellerId,
  mediaUrl: '',
  type: StatusType.image,
  createdAt: DateTime(2026, 10, 11),
);

void main() {
  test('les vendeurs les plus populaires passent en premier', () {
    final ordered = orderSellersByPopularity(
      [_status('a'), _status('b'), _status('c'), _status('d')],
      {'a': 2, 'b': 40, 'c': 0, 'd': 7},
    );
    expect(ordered.map((s) => s.sellerId), ['b', 'd', 'a', 'c']);
  });

  test('à égalité de points, l’ordre du fil (plus récent) est conservé', () {
    final ordered = orderSellersByPopularity(
      [_status('a'), _status('b'), _status('c')],
      {'b': 3},
    );
    expect(ordered.map((s) => s.sellerId), ['b', 'a', 'c']);
  });
}
