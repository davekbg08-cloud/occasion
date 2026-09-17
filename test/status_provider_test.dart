import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/providers/status_provider.dart';
import 'package:occasion/services/status_service.dart';

/// Simule le comportement réel de Firestore `snapshots()` sur une
/// connexion instable : ni données, ni erreur, jamais — exactement le
/// symptôme observé en prod (`ERR_NAME_NOT_RESOLVED` récurrent) qui
/// laissait auparavant le feed bloqué en chargement infini.
class _NeverEmittingStatusService extends StatusService {
  @override
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> feed({
    int pageSize = StatusService.feedPageSize,
  }) {
    return const Stream.empty();
  }
}

void main() {
  group('StatusNotifier.loadFeed', () {
    test('régression : un flux qui ne livre jamais rien ne laisse plus '
        'isLoading bloqué à true indéfiniment (bascule sur une erreur '
        'après le délai configuré)', () async {
      final notifier = StatusNotifier(
        service: _NeverEmittingStatusService(),
        loadTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(notifier.dispose);

      notifier.loadFeed();
      expect(notifier.state.isLoading, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.statuses, isEmpty);
    });

    test('retryLoadFeed relance le chargement après un timeout', () async {
      final notifier = StatusNotifier(
        service: _NeverEmittingStatusService(),
        loadTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(notifier.dispose);

      notifier.loadFeed();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(notifier.state.isLoading, isFalse);

      notifier.retryLoadFeed();
      expect(notifier.state.isLoading, isTrue);
    });
  });
}
