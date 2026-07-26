// ignore_for_file: avoid_print
//
// Migration : recalcule buyerUnreadCount/sellerUnreadCount pour chaque
// conversation existante, à partir du statut réel des messages, afin de
// remplacer l'ancien compteur unreadCount partagé.
//
// Idempotent : relancer ce script recalcule les mêmes valeurs à partir des
// messages (pas un delta), donc l'exécuter plusieurs fois ne change rien de
// plus après la première migration réussie.
//
// Usage :
//   dart run tool/migrate_chat_unread_counts.dart --project=occasion-10cdb
//   dart run tool/migrate_chat_unread_counts.dart --project=occasion-10cdb --apply
//
// Sans --apply : dry-run, affiche ce qui serait écrit sans rien modifier.
// Avec --apply : écrit réellement buyerUnreadCount/sellerUnreadCount sur
// chaque document chats/{chatId} (updateMask ciblé, ne touche à rien
// d'autre — l'ancien champ unreadCount n'est ni lu ni supprimé ici).
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
      'Usage: dart run tool/migrate_chat_unread_counts.dart --project=<id> [--apply] [--page-size=100]',
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

  var processed = 0;
  var wouldChange = 0;
  var applied = 0;
  var errors = 0;

  print(
    apply
        ? '=== MODE APPLICATION ==='
        : '=== MODE DRY-RUN (aucune écriture) ===',
  );

  String? pageToken;
  do {
    final uri = Uri.parse(
      '$base/chats?pageSize=$pageSize${pageToken != null ? '&pageToken=$pageToken' : ''}',
    );
    final res = await client.get(uri, headers: _headers(token));
    if (res.statusCode != 200) {
      stderr.writeln('Échec liste chats (${res.statusCode}): ${res.body}');
      errors++;
      break;
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final documents = (body['documents'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    pageToken = body['nextPageToken'] as String?;

    for (final doc in documents) {
      processed++;
      final name = doc['name'] as String;
      final chatId = name.split('/').last;
      final fields = (doc['fields'] as Map<String, dynamic>? ?? const {});
      final buyerId = _stringField(fields, 'buyerId');
      final sellerId = _stringField(fields, 'sellerId');
      final existingBuyerCount = _intField(fields, 'buyerUnreadCount');
      final existingSellerCount = _intField(fields, 'sellerUnreadCount');

      if (buyerId == null || sellerId == null) {
        stderr.writeln('Chat $chatId sans buyerId/sellerId, ignoré.');
        continue;
      }

      final counts = await _countUnread(
        client: client,
        token: token,
        base: base,
        chatId: chatId,
        buyerId: buyerId,
        sellerId: sellerId,
      );

      final changed =
          counts.buyerUnread != (existingBuyerCount ?? -1) ||
          counts.sellerUnread != (existingSellerCount ?? -1);
      if (changed) wouldChange++;

      print(
        'Chat $chatId : buyerUnreadCount=${counts.buyerUnread} '
        '(actuel: ${existingBuyerCount ?? "absent"}), '
        'sellerUnreadCount=${counts.sellerUnread} '
        '(actuel: ${existingSellerCount ?? "absent"})'
        '${changed ? "" : " — déjà à jour"}',
      );

      if (apply && changed) {
        final patchUri = Uri.parse(
          '$base/chats/$chatId?updateMask.fieldPaths=buyerUnreadCount&updateMask.fieldPaths=sellerUnreadCount',
        );
        final patchRes = await client.patch(
          patchUri,
          headers: {..._headers(token), 'Content-Type': 'application/json'},
          body: jsonEncode({
            'fields': {
              'buyerUnreadCount': {
                'integerValue': counts.buyerUnread.toString(),
              },
              'sellerUnreadCount': {
                'integerValue': counts.sellerUnread.toString(),
              },
            },
          }),
        );
        if (patchRes.statusCode == 200) {
          applied++;
        } else {
          errors++;
          stderr.writeln(
            'Échec écriture chat $chatId (${patchRes.statusCode}): ${patchRes.body}',
          );
        }
      }
    }
  } while (pageToken != null);

  client.close();

  print('--- Rapport final ---');
  print('Conversations traitées : $processed');
  print('Conversations à corriger : $wouldChange');
  if (apply) print('Conversations effectivement mises à jour : $applied');
  print('Erreurs : $errors');
  if (!apply && wouldChange > 0) {
    print('Relancer avec --apply pour appliquer ces changements.');
  }
}

class _UnreadCounts {
  const _UnreadCounts(this.buyerUnread, this.sellerUnread);
  final int buyerUnread;
  final int sellerUnread;
}

Future<_UnreadCounts> _countUnread({
  required http.Client client,
  required String token,
  required String base,
  required String chatId,
  required String buyerId,
  required String sellerId,
}) async {
  var buyerUnread = 0;
  var sellerUnread = 0;
  String? pageToken;
  do {
    final uri = Uri.parse(
      '$base/chats/$chatId/messages?pageSize=200${pageToken != null ? '&pageToken=$pageToken' : ''}',
    );
    final res = await client.get(uri, headers: _headers(token));
    if (res.statusCode != 200) break;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final documents = (body['documents'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    pageToken = body['nextPageToken'] as String?;

    for (final doc in documents) {
      final fields = (doc['fields'] as Map<String, dynamic>? ?? const {});
      final receiverId = _stringField(fields, 'receiverId');
      final status = _stringField(fields, 'status');
      if (status == 'read') continue;
      if (receiverId == buyerId) buyerUnread++;
      if (receiverId == sellerId) sellerUnread++;
    }
  } while (pageToken != null);

  return _UnreadCounts(buyerUnread, sellerUnread);
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
