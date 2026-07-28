// ignore_for_file: avoid_print
//
// Migration : recalcule `users/{uid}.unreadMessageCount` (source unique du
// badge natif de l'icône, voir `functions/index.js::badgeCountForUser`) à
// partir de la somme réelle des compteurs par conversation
// (`buyerUnreadCount`/`sellerUnreadCount`) de chaque chat où l'utilisateur
// participe.
//
// Idempotent : relancer ce script recalcule la même somme à partir des
// chats (pas un delta), donc l'exécuter plusieurs fois ne change rien de
// plus après la première migration réussie.
//
// Usage :
//   dart run tool/migrate_user_unread_message_count.dart --project=occasion-10cdb
//   dart run tool/migrate_user_unread_message_count.dart --project=occasion-10cdb --apply
//
// Sans --apply : dry-run, affiche ce qui serait écrit sans rien modifier.
// Avec --apply : écrit réellement `unreadMessageCount` sur chaque document
// `users/{uid}` concerné (updateMask ciblé, ne touche à rien d'autre).
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
      'Usage: dart run tool/migrate_user_unread_message_count.dart --project=<id> [--apply] [--page-size=100]',
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
  final totals = <String, int>{};

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
      break;
    }
    final chatBody = jsonDecode(chatRes.body) as Map<String, dynamic>;
    final chatDocs = (chatBody['documents'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    chatPageToken = chatBody['nextPageToken'] as String?;

    for (final chatDoc in chatDocs) {
      chatsProcessed++;
      final fields = (chatDoc['fields'] as Map<String, dynamic>? ?? const {});
      final buyerId = _stringField(fields, 'buyerId');
      final sellerId = _stringField(fields, 'sellerId');
      final buyerUnread = _intField(fields, 'buyerUnreadCount') ?? 0;
      final sellerUnread = _intField(fields, 'sellerUnreadCount') ?? 0;

      if (buyerId != null) {
        totals[buyerId] = (totals[buyerId] ?? 0) + buyerUnread;
      }
      if (sellerId != null) {
        totals[sellerId] = (totals[sellerId] ?? 0) + sellerUnread;
      }
    }
  } while (chatPageToken != null);

  var usersChecked = 0;
  var usersWithChange = 0;
  var usersUpdated = 0;
  var errors = 0;

  for (final entry in totals.entries) {
    final uid = entry.key;
    final recomputed = entry.value;
    usersChecked++;

    final userUri = Uri.parse('$base/users/$uid');
    final userRes = await client.get(userUri, headers: _headers(token));
    if (userRes.statusCode != 200) {
      // Utilisateur possiblement supprimé depuis : ignoré, pas une erreur
      // bloquante pour le reste de la migration.
      continue;
    }
    final userBody = jsonDecode(userRes.body) as Map<String, dynamic>;
    final userFields =
        (userBody['fields'] as Map<String, dynamic>? ?? const {});
    final existing = _intField(userFields, 'unreadMessageCount') ?? 0;
    final changed = existing != recomputed;
    if (changed) usersWithChange++;

    print(
      'Utilisateur $uid : unreadMessageCount=$recomputed (actuel: $existing)'
      '${changed ? "" : " — déjà à jour"}',
    );

    if (apply && changed) {
      final patchUri = Uri.parse(
        '$base/users/$uid?updateMask.fieldPaths=unreadMessageCount',
      );
      final patchRes = await client.patch(
        patchUri,
        headers: {..._headers(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'fields': {
            'unreadMessageCount': {'integerValue': recomputed.toString()},
          },
        }),
      );
      if (patchRes.statusCode == 200) {
        usersUpdated++;
      } else {
        errors++;
        stderr.writeln(
          'Échec écriture utilisateur $uid (${patchRes.statusCode}): ${patchRes.body}',
        );
      }
    }
  }

  client.close();

  print('--- Rapport final ---');
  print('Chats traités : $chatsProcessed');
  print('Utilisateurs distincts vérifiés : $usersChecked');
  print('Utilisateurs dont le compteur diffère du recalcul : $usersWithChange');
  if (apply) print('Utilisateurs effectivement mis à jour : $usersUpdated');
  print('Erreurs : $errors');
  if (!apply && usersWithChange > 0) {
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
