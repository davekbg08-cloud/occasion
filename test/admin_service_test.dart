import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/services/admin_service.dart';

void main() {
  test('admin si et seulement si admins/{uid} existe', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('admins').doc('admin1').set({'since': 1});
    // Un rôle "admin" dans users ne donne aucun droit : une seule source.
    await firestore.collection('users').doc('user1').set({'role': 'admin'});
    final service = AdminService(firestore: firestore);

    expect(await service.isAdmin('admin1'), isTrue);
    expect(await service.isAdmin('user1'), isFalse);
  });
}
