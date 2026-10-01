import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/services/app_update_service.dart';

void main() {
  group('AppUpdateService.minAndroidVersionCode', () {
    late FakeFirebaseFirestore firestore;
    late AppUpdateService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = AppUpdateService(firestore);
    });

    test(
      'aucun document configuré : émet null (jamais bloquant par défaut)',
      () async {
        final value = await service.minAndroidVersionCode().first;
        expect(value, isNull);
      },
    );

    test('lit minVersionCode depuis appConfig/androidVersion', () async {
      await firestore.collection('appConfig').doc('androidVersion').set({
        'minVersionCode': 17,
      });

      final value = await service.minAndroidVersionCode().first;
      expect(value, 17);
    });

    test(
      'un document existant mais sans le champ minVersionCode émet null',
      () async {
        await firestore.collection('appConfig').doc('androidVersion').set({
          'other': 'valeur',
        });

        final value = await service.minAndroidVersionCode().first;
        expect(value, isNull);
      },
    );

    test('suit les mises à jour en temps réel du seuil', () async {
      final docRef = firestore.collection('appConfig').doc('androidVersion');
      final values = <int?>[];
      final sub = service.minAndroidVersionCode().listen(values.add);

      await docRef.set({'minVersionCode': 17});
      await docRef.set({'minVersionCode': 18});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(values, [null, 17, 18]);
    });
  });
}
