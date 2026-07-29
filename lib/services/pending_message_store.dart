import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pending_chat_message.dart';

/// Boîte d'envoi locale persistante : seule source de vérité pour les
/// messages qu'un utilisateur a essayé d'envoyer mais dont l'issue n'est pas
/// encore confirmée par Firestore (`queued`/`sending`/`failed`). Survit à la
/// fermeture complète de l'application et au redémarrage de l'appareil
/// (`SharedPreferences`, déjà utilisé ailleurs dans l'app — voir
/// `notification_service.dart` — fonctionne nativement sur Android/iOS/Web ;
/// aucune nouvelle dépendance n'est nécessaire vu le volume toujours faible
/// de cette boîte : les messages confirmés en sont retirés dès
/// réconciliation, elle ne grossit jamais indéfiniment).
///
/// Une entrée par utilisateur connecté : la clé de stockage
/// (`pending_messages_v1_$userId`) isole déjà les données par compte, aucun
/// mélange possible entre acheteur/vendeur ou entre deux comptes qui se
/// succèdent sur le même appareil. Le contenu des messages ([PendingChatMessage.content])
/// n'est jamais journalisé par cette classe.
///
/// Écritures sérialisées : [upsert]/[remove]/[clear] font chacune une
/// lecture-modification-écriture (charge la liste entière, la modifie,
/// la réécrit) — sans verrou, deux appels concurrents sur la même instance
/// (deux envois rapprochés, ou un envoi et une purge de réconciliation en
/// même temps) liraient tous deux l'ancien état puis la seconde écriture
/// écraserait la première (perte silencieuse d'une entrée jamais confirmée).
/// [_enqueue] fait exécuter chaque écriture seulement après que la
/// précédente, sur cette même instance, soit terminée.
class PendingMessageStore {
  PendingMessageStore();

  Future<void> _writeQueue = Future<void>.value();

  static String _keyFor(String userId) => 'pending_messages_v1_$userId';

  Future<List<PendingChatMessage>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(userId));
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(PendingChatMessage.fromJson)
        .toList();
  }

  Future<void> upsert(String userId, PendingChatMessage entry) {
    return _enqueue(() async {
      final current = await load(userId);
      final next = [
        for (final existing in current)
          if (!(existing.chatId == entry.chatId &&
              existing.clientMessageId == entry.clientMessageId))
            existing,
        entry,
      ];
      await _save(userId, next);
    });
  }

  Future<void> remove(String userId, String chatId, String clientMessageId) {
    return _enqueue(() async {
      final current = await load(userId);
      final next = current
          .where(
            (e) =>
                !(e.chatId == chatId && e.clientMessageId == clientMessageId),
          )
          .toList();
      if (next.length == current.length) return;
      await _save(userId, next);
    });
  }

  Future<void> clear(String userId) {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFor(userId));
    });
  }

  /// Chaîne [action] après la fin de toute écriture déjà en attente sur
  /// cette instance — jamais deux écritures en vol en même temps, quel que
  /// soit l'ordre dans lequel les appelants ont été invoqués. Une erreur
  /// dans [action] est bien propagée à SON appelant, mais n'empêche jamais
  /// les écritures suivantes de s'exécuter (la chaîne interne ne reste
  /// jamais bloquée sur un échec passé).
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _save(String userId, List<PendingChatMessage> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyFor(userId),
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
