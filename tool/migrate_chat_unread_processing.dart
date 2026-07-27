// ignore_for_file: avoid_print
//
// Migration : initialise les marqueurs `unreadProcessed`/
// `unreadIncrementApplied` sur les anciens messages qui n'en disposent pas
// encore (créés avant l'introduction de ces marqueurs par `onNewMessage`),
// et recalcule `buyerUnreadCount`/`sellerUnreadCount` à partir de l'état
// réel des messages non lus. Ne supprime ni ne modifie jamais un message
// qui possède déjà `unreadProcessed` (déjà traité par la Cloud Function ou
// une exécution précédente de cette migration).
//
// Pour un message sans `unreadProcessed` :
//   - `status == 'read'`  -> unreadProcessed: true, unreadIncrementApplied: false
//   - sinon (non lu)      -> unreadProcessed: true, unreadIncrementApplied: true
// (même règle que `incrementChatUnread` dans `functions/index.js` : un
// message déjà lu ne doit jamais compter comme ayant incrémenté le
// compteur).
//
// Le compteur corrigé de chaque chat est le nombre de messages dont le
// destinataire est ce participant et dont le statut n'est pas `read` —
// jamais négatif par construction (c'est un compte). L'ancienne valeur du
// compteur est conservée pour audit dans
// `buyerUnreadCountPreMigration`/`sellerUnreadCountPreMigration` (écrite
// une seule fois : un deuxième passage ne l'écrase pas, ce qui rend le
// script idempotent).
//
// Usage :
//   dart run tool/migrate_chat_unread_processing.dart --project=occasion-10cdb
//   dart run tool/migrate_chat_unread_processing.dart --project=occasion-10cdb --apply
//
// Sans --apply : DRY-RUN (mode par défaut, obligatoire pour une première
// lecture) — affiche ce qui serait écrit sans rien modifier.
// Avec --apply : écrit réellement les marqueurs sur les messages
// concernés et les compteurs corrigés sur `chats/{chatId}` (updateMask
// ciblé, ne touche à rien d'autre).
//
// Ne pas exécuter --apply automatiquement en production : lancer d'abord
// en dry-run, faire relire le rapport, puis exécuter --apply
// manuellement.
//
// Nécessite un compte authentifié avec accès Firestore sur le projet
// (`gcloud auth application-default login` ou `gcloud auth login`).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final project = _argValue(args, 'project');
  if (project == null || project.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/migrate_chat_unread_processing.dart --project=<id> [--apply] [--page-size=100]',
    );
    exitCode = 64;
    return;
  }
  final apply = args.contains('--apply');
  final pageSize = int.tryParse(_argValue(args, 'page-size') ?? '100') ?? 100;

  final token = await _accessToken();
  final client = http.Client();
  final base =
      'https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents';

  var chatsProcessed = 0;
  var messagesProcessed = 0;
  var messagesMigrated = 0;
  var chatsWithCounterChange = 0;
  var chatsUpdated = 0;
  var errors = 0;

  print(
    apply
        ? '=== MODE APPLICATION ==='
        : '=== MODE DRY-RUN (aucune écriture) ===',
  );

  String? chatPageToken;
  do {
    final chatUri = Uri.parse(
      '$base/chats?pageSize=$pageSize${chatPageToken != null ? '&pageToken=$chatPageToken' : ''}',
    );
    final chatRes = await client.get(chatUri, headers: _headers(token));
    if (chatRes.statusCode != 200) {
      stderr.writeln(
        'Échec liste chats (${chatRes.statusCode}): ${chatRes.body}',
      );
      errors++;
      break;
    }
    final chatBody = jsonDecode(chatRes.body) as Map<String, dynamic>;
    final chatDocs = (chatBody['documents'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    chatPageToken = chatBody['nextPageToken'] as String?;

    for (final chatDoc in chatDocs) {
      chatsProcessed++;
      final chatName = chatDoc['name'] as String;
      final chatId = chatName.split('/').last;
      final chatFields =
          (chatDoc['fields'] as Map<String, dynamic>? ?? const {});
      final buyerId = _stringField(chatFields, 'buyerId');
      final sellerId = _stringField(chatFields, 'sellerId');
      final existingBuyerCount = _intField(chatFields, 'buyerUnreadCount') ?? 0;
      final existingSellerCount =
          _intField(chatFields, 'sellerUnreadCount') ?? 0;
      final hasPreMigrationSnapshot =
          chatFields.containsKey('buyerUnreadCountPreMigration') ||
          chatFields.containsKey('sellerUnreadCountPreMigration');

      if (buyerId == null || sellerId == null) {
        stderr.writeln('Chat $chatId sans buyerId/sellerId, ignoré.');
        continue;
      }

      var buyerUnread = 0;
      var sellerUnread = 0;
      String? msgPageToken;
      do {
        final msgUri = Uri.parse(
          '$base/chats/$chatId/messages?pageSize=200${msgPageToken != null ? '&pageToken=$msgPageToken' : ''}',
        );
        final msgRes = await client.get(msgUri, headers: _headers(token));
        if (msgRes.statusCode != 200) {
          stderr.writeln(
            'Échec liste messages chat $chatId (${msgRes.statusCode}): ${msgRes.body}',
          );
          errors++;
          break;
        }
        final msgBody = jsonDecode(msgRes.body) as Map<String, dynamic>;
        final msgDocs = (msgBody['documents'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        msgPageToken = msgBody['nextPageToken'] as String?;

        for (final msgDoc in msgDocs) {
          messagesProcessed++;
          final msgFields =
              (msgDoc['fields'] as Map<String, dynamic>? ?? const {});
          final receiverId = _stringField(msgFields, 'receiverId');
          final status = _stringField(msgFields, 'status');
          final isUnread = status != 'read';
          if (receiverId == buyerId && isUnread) buyerUnread++;
          if (receiverId == sellerId && isUnread) sellerUnread++;

          // Ne touche jamais un message déjà traité (par `onNewMessage` ou
          // un passage précédent de cette migration) : ni suppression, ni
          // écrasement.
          if (msgFields.containsKey('unreadProcessed')) continue;

          messagesMigrated++;
          final msgName = msgDoc['name'] as String;
          final msgId = msgName.split('/').last;
          final unreadIncrementApplied = isUnread;

          print(
            '  Message $chatId/$msgId : unreadProcessed=true, '
            'unreadIncrementApplied=$unreadIncrementApplied (status=${status ?? "absent"})',
          );

          if (apply) {
            final patchUri = Uri.parse(
              '$base/chats/$chatId/messages/$msgId'
              '?updateMask.fieldPaths=unreadProcessed'
              '&updateMask.fieldPaths=unreadIncrementApplied'
              '&updateMask.fieldPaths=unreadProcessedAt',
            );
            final patchRes = await client.patch(
              patchUri,
              headers: {..._headers(token), 'Content-Type': 'application/json'},
              body: jsonEncode({
                'fields': {
                  'unreadProcessed': {'booleanValue': true},
                  'unreadIncrementApplied': {
                    'booleanValue': unreadIncrementApplied,
                  },
                  'unreadProcessedAt': {
                    'timestampValue': DateTime.now().toUtc().toIso8601String(),
                  },
                },
              }),
            );
            if (patchRes.statusCode != 200) {
              errors++;
              stderr.writeln(
                'Échec écriture message $chatId/$msgId (${patchRes.statusCode}): ${patchRes.body}',
              );
            }
          }
        }
      } while (msgPageToken != null);

      // Jamais négatif : `buyerUnread`/`sellerUnread` sont des compteurs
      // d'occurrences, structurellement >= 0.
      final counterChanged =
          buyerUnread != existingBuyerCount ||
          sellerUnread != existingSellerCount;
      if (counterChanged) chatsWithCounterChange++;

      print(
        'Chat $chatId : buyerUnreadCount=$buyerUnread (actuel: $existingBuyerCount), '
        'sellerUnreadCount=$sellerUnread (actuel: $existingSellerCount)'
        '${counterChanged ? "" : " — déjà à jour"}',
      );

      if (apply && counterChanged) {
        final fieldPaths = StringBuffer(
          '?updateMask.fieldPaths=buyerUnreadCount&updateMask.fieldPaths=sellerUnreadCount',
        );
        final fields = <String, dynamic>{
          'buyerUnreadCount': {'integerValue': buyerUnread.toString()},
          'sellerUnreadCount': {'integerValue': sellerUnread.toString()},
        };
        // N'écrit le snapshot d'audit qu'une seule fois (idempotence : un
        // deuxième passage ne doit pas écraser la valeur pré-migration
        // d'origine par une valeur déjà corrigée).
        if (!hasPreMigrationSnapshot) {
          fieldPaths.write(
            '&updateMask.fieldPaths=buyerUnreadCountPreMigration'
            '&updateMask.fieldPaths=sellerUnreadCountPreMigration',
          );
          fields['buyerUnreadCountPreMigration'] = {
            'integerValue': existingBuyerCount.toString(),
          };
          fields['sellerUnreadCountPreMigration'] = {
            'integerValue': existingSellerCount.toString(),
          };
        }

        final patchUri = Uri.parse('$base/chats/$chatId$fieldPaths');
        final patchRes = await client.patch(
          patchUri,
          headers: {..._headers(token), 'Content-Type': 'application/json'},
          body: jsonEncode({'fields': fields}),
        );
        if (patchRes.statusCode == 200) {
          chatsUpdated++;
        } else {
          errors++;
          stderr.writeln(
            'Échec écriture chat $chatId (${patchRes.statusCode}): ${patchRes.body}',
          );
        }
      }
    }
  } while (chatPageToken != null);

  client.close();

  print('--- Rapport final ---');
  print('Chats traités : $chatsProcessed');
  print('Messages examinés : $messagesProcessed');
  print('Messages migrés (marqueurs initialisés) : $messagesMigrated');
  print('Chats dont le compteur diffère du recalcul : $chatsWithCounterChange');
  if (apply) print('Chats effectivement mis à jour : $chatsUpdated');
  print('Erreurs : $errors');
  if (!apply && (messagesMigrated > 0 || chatsWithCounterChange > 0)) {
    print('Relancer avec --apply pour appliquer ces changements.');
  }
}

Map<String, String> _headers(String token) => {
  'Authorization': 'Bearer $token',
};

String? _stringField(Map<String, dynamic> fields, String key) {
  final value = fields[key] as Map<String, dynamic>?;
  return value?['stringValue'] as String?;
}

int? _intField(Map<String, dynamic> fields, String key) {
  final value = fields[key] as Map<String, dynamic>?;
  final raw = value?['integerValue'] as String?;
  return raw == null ? null : int.tryParse(raw);
}

String? _argValue(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

Future<String> _accessToken() async {
  final result = await Process.run('gcloud', ['auth', 'print-access-token']);
  if (result.exitCode != 0) {
    stderr.writeln(
      'Impossible d\'obtenir un token gcloud. Lance '
      '"gcloud auth application-default login" ou "gcloud auth login" au préalable.',
    );
    exit(1);
  }
  return (result.stdout as String).trim();
}
