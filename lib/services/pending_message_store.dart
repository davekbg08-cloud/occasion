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
class PendingMessageStore {
  const PendingMessageStore();

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

  /// Ajoute ou remplace l'entrée portant le même `chatId`+`clientMessageId`
  /// (jamais de doublon pour la même clé logique). Le futur ne se termine
  /// qu'une fois l'écriture disque effectuée — l'appelant peut donc
  /// attendre cette confirmation avant d'afficher la bulle optimiste.
  Future<void> upsert(String userId, PendingChatMessage entry) async {
    final current = await load(userId);
    final next = [
      for (final existing in current)
        if (!(existing.chatId == entry.chatId &&
            existing.clientMessageId == entry.clientMessageId))
          existing,
      entry,
    ];
    await _save(userId, next);
  }

  Future<void> remove(
    String userId,
    String chatId,
    String clientMessageId,
  ) async {
    final current = await load(userId);
    final next = current
        .where(
          (e) => !(e.chatId == chatId && e.clientMessageId == clientMessageId),
        )
        .toList();
    if (next.length == current.length) return;
    await _save(userId, next);
  }

  Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(userId));
  }

  Future<void> _save(String userId, List<PendingChatMessage> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyFor(userId),
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
