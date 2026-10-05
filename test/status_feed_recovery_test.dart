import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/providers/status_provider.dart';
import 'package:occasion/services/status_service.dart';

/// Chaque appel à `feed()` ouvre un NOUVEAU flux (comme un nouveau listener
/// Firestore) : le 1er peut être mis en erreur, les suivants servent la
/// vraie collection.
class _RecoverableStatusService extends StatusService {
  // ignore: use_super_parameters
  _RecoverableStatusService(FirebaseFirestore firestore) : super(firestore);

  final firstFeed =
      StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>();
  int feedCalls = 0;

  @override
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> feed({
    int pageSize = StatusService.feedPageSize,
  }) {
    feedCalls++;
    if (feedCalls == 1) return firstFeed.stream;
    return super.feed(pageSize: pageSize);
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late FakeFirebaseFirestore firestore;
  late _RecoverableStatusService service;
  late StatusNotifier notifier;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('statuses').doc('s1').set({
      'id': 's1',
      'sellerId': 'vendeur',
      'sellerName': 'Occasion',
      'mediaUrl': 'https://example.com/s1.jpg',
      'type': 'image',
      'active': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    service = _RecoverableStatusService(firestore);
    notifier = StatusNotifier(
      service: service,
      retryDelay: (_) => Duration.zero,
    );
  });

  tearDown(() => notifier.dispose());

  test('régression : un fil coupé (ex. déconnexion du vendeur) se relance '
      'tout seul au lieu de rester vide toute la session', () async {
    notifier.loadFeed();
    service.firstFeed.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await settle();

    expect(service.feedCalls, 2);
    expect(notifier.state.statuses.map((s) => s.id), ['s1']);
  });

  test('régression : au changement de compte, le fil est vidé puis rechargé '
      'pour le nouveau compte (plus « déjà chargé »)', () async {
    notifier.loadFeed();
    service.firstFeed.add(const []);
    await settle();
    expect(notifier.state.statuses, isEmpty);

    notifier.resetForUserChange();
    expect(notifier.state.statuses, isEmpty);

    notifier.loadFeed();
    await settle();
    expect(service.feedCalls, 2, reason: 'un nouveau flux est ouvert');
    expect(notifier.state.statuses.map((s) => s.id), ['s1']);
  });
}
