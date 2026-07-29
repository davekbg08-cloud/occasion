import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/models/pending_chat_message.dart';
import 'package:occasion/services/pending_message_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

PendingChatMessage _entry({
  String chatId = 'chat1',
  String clientMessageId = 'local-1',
  PendingMessageState state = PendingMessageState.queued,
  int attemptCount = 0,
}) {
  return PendingChatMessage(
    clientMessageId: clientMessageId,
    chatId: chatId,
    senderId: 'buyer1',
    receiverId: 'seller1',
    content: 'Bonjour',
    localCreatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    state: state,
    attemptCount: attemptCount,
  );
}

void main() {
  final store = PendingMessageStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PendingMessageStore', () {
    test(
      'load() renvoie une liste vide tant que rien n\'a été persisté',
      () async {
        expect(await store.load('buyer1'), isEmpty);
      },
    );

    test(
      'upsert() persiste réellement (relecture après un nouvel appel à load)',
      () async {
        await store.upsert('buyer1', _entry());
        final loaded = await store.load('buyer1');
        expect(loaded, hasLength(1));
        expect(loaded.single.clientMessageId, 'local-1');
        expect(loaded.single.content, 'Bonjour');
        expect(loaded.single.state, PendingMessageState.queued);
      },
    );

    test(
      'upsert() sur la même clé (chatId+clientMessageId) remplace, jamais un doublon',
      () async {
        await store.upsert('buyer1', _entry());
        await store.upsert(
          'buyer1',
          _entry(state: PendingMessageState.failed, attemptCount: 2),
        );
        final loaded = await store.load('buyer1');
        expect(loaded, hasLength(1));
        expect(loaded.single.state, PendingMessageState.failed);
        expect(loaded.single.attemptCount, 2);
      },
    );

    test(
      'deux clientMessageId différents dans le même chat cohabitent',
      () async {
        await store.upsert('buyer1', _entry(clientMessageId: 'local-1'));
        await store.upsert('buyer1', _entry(clientMessageId: 'local-2'));
        final loaded = await store.load('buyer1');
        expect(loaded, hasLength(2));
      },
    );

    test('remove() ne supprime que l\'entrée exacte demandée', () async {
      await store.upsert('buyer1', _entry(clientMessageId: 'local-1'));
      await store.upsert('buyer1', _entry(clientMessageId: 'local-2'));
      await store.remove('buyer1', 'chat1', 'local-1');
      final loaded = await store.load('buyer1');
      expect(loaded, hasLength(1));
      expect(loaded.single.clientMessageId, 'local-2');
    });

    test('clear() vide entièrement la boîte d\'un utilisateur', () async {
      await store.upsert('buyer1', _entry());
      await store.clear('buyer1');
      expect(await store.load('buyer1'), isEmpty);
    });

    test(
      'les entrées de deux utilisateurs différents sont totalement isolées (clé de stockage par userId)',
      () async {
        await store.upsert('buyer1', _entry(chatId: 'chat-buyer'));
        await store.upsert('seller1', _entry(chatId: 'chat-seller'));

        final buyerEntries = await store.load('buyer1');
        final sellerEntries = await store.load('seller1');
        expect(buyerEntries, hasLength(1));
        expect(sellerEntries, hasLength(1));
        expect(buyerEntries.single.chatId, 'chat-buyer');
        expect(sellerEntries.single.chatId, 'chat-seller');
      },
    );

    test(
      'survit à une nouvelle instance du store (simule la fermeture complète de l\'application)',
      () async {
        await store.upsert('buyer1', _entry());
        // Nouvelle instance : SharedPreferences.getInstance() relit le même
        // stockage sous-jacent, jamais une instance en mémoire du store.
        final freshStore = PendingMessageStore();
        final loaded = await freshStore.load('buyer1');
        expect(loaded, hasLength(1));
      },
    );

    test(
      'deux upsert() strictement CONCURRENTS (sans attendre le premier) ne se perdent jamais l\'un l\'autre',
      () async {
        // Sans sérialisation, les deux liraient le même état initial vide
        // puis la seconde écriture écraserait la première (perte
        // silencieuse d'un message jamais confirmé). `Future.wait` sans
        // `await` entre les deux appels simule ce cas réel (deux envois
        // rapprochés dans deux chats différents, ou un envoi + une purge
        // de réconciliation en même temps).
        final first = store.upsert(
          'buyer1',
          _entry(clientMessageId: 'local-1'),
        );
        final second = store.upsert(
          'buyer1',
          _entry(clientMessageId: 'local-2'),
        );
        await Future.wait([first, second]);

        final loaded = await store.load('buyer1');
        expect(
          loaded.map((e) => e.clientMessageId).toSet(),
          {'local-1', 'local-2'},
          reason: 'aucune des deux entrées ne doit être perdue',
        );
      },
    );

    test(
      'un upsert() concurrent à un remove() sur des clés différentes ne perd rien',
      () async {
        await store.upsert('buyer1', _entry(clientMessageId: 'to-remove'));

        final removeFuture = store.remove('buyer1', 'chat1', 'to-remove');
        final upsertFuture = store.upsert(
          'buyer1',
          _entry(clientMessageId: 'to-keep'),
        );
        await Future.wait([removeFuture, upsertFuture]);

        final loaded = await store.load('buyer1');
        expect(loaded.map((e) => e.clientMessageId).toList(), ['to-keep']);
      },
    );

    test(
      'toJson/fromJson préserve tous les champs y compris les optionnels',
      () {
        final entry = PendingChatMessage(
          clientMessageId: 'local-1',
          chatId: 'chat1',
          senderId: 'buyer1',
          receiverId: 'seller1',
          content: 'Bonjour',
          localCreatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
          state: PendingMessageState.failed,
          attemptCount: 3,
          lastAttemptAt: DateTime.fromMillisecondsSinceEpoch(2000),
          lastErrorCode: 'unavailable',
        );
        final restored = PendingChatMessage.fromJson(entry.toJson());
        expect(restored.clientMessageId, entry.clientMessageId);
        expect(restored.attemptCount, 3);
        expect(restored.lastAttemptAt, entry.lastAttemptAt);
        expect(restored.lastErrorCode, 'unavailable');
      },
    );
  });
}
