import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/services/status_service.dart';

void main() {
  group('Quota quotidien de statuts vidéo', () {
    test('videoQuotaDayKey : même découpage que le serveur (heure de Kinshasa, '
        'UTC+1), bascule à 23h UTC', () {
      expect(
        StatusService.videoQuotaDayKey(DateTime.utc(2026, 9, 27, 22, 59)),
        '2026-09-27',
      );
      expect(
        StatusService.videoQuotaDayKey(DateTime.utc(2026, 9, 27, 23)),
        '2026-09-28',
      );
    });

    test('videoStatusesPublishedToday lit le compteur tenu par le serveur, '
        '0 si aucun statut vidéo aujourd\'hui', () async {
      final firestore = FakeFirebaseFirestore();
      final service = StatusService(firestore);
      expect(await service.videoStatusesPublishedToday('seller1'), 0);

      final dayKey = StatusService.videoQuotaDayKey(DateTime.now());
      await firestore
          .collection('statusDailyCounters')
          .doc('seller1_$dayKey')
          .set({
            'sellerId': 'seller1',
            'videoStatusIds': ['v1', 'v2', 'v3', 'v4', 'v5'],
          });
      expect(
        await service.videoStatusesPublishedToday('seller1'),
        StatusService.maxVideoStatusesPerDay,
      );
    });
  });
}
