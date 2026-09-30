import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

/// Statut de présence d'un utilisateur, tel qu'exposé aux écrans.
class PresenceStatus {
  const PresenceStatus({required this.isOnline});

  final bool isOnline;

  static const offline = PresenceStatus(isOnline: false);
}

/// Présence "en ligne/hors ligne" et "en train d'écrire", via Firebase
/// Realtime Database — le seul service Firebase avec un `onDisconnect()`
/// fiable (Firestore ne peut pas détecter une déconnexion brutale : app
/// tuée, réseau coupé). Portée volontairement minimale, cohérente avec ce
/// qui a été décidé : affiché UNIQUEMENT dans une conversation déjà
/// ouverte (jamais dans le répertoire ni la liste de conversations), donc
/// un simple `/presence/{uid}` global suffit — pas besoin de le scoper par
/// conversation.
class PresenceService {
  PresenceService({FirebaseDatabase? database})
    : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;
  String? _startedForUid;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;

  DatabaseReference _presenceRef(String uid) => _db.ref('presence/$uid');
  DatabaseReference _typingRef(String chatId, String uid) =>
      _db.ref('typing/$chatId/$uid');

  /// Annonce "en ligne" et engage le retour automatique à "hors ligne" dès
  /// que la connexion tombe — à ré-engager à CHAQUE reconnexion, un ancien
  /// `onDisconnect()` ne survit pas à une coupure (comportement documenté
  /// de Realtime Database, pas un oubli). Idempotent par [uid] : un second
  /// appel pour le même utilisateur (ex. le widget racine qui se
  /// reconstruit) ne réabonne rien.
  void start(String uid) {
    if (_startedForUid == uid) return;
    _startedForUid = uid;
    unawaited(_connectionSubscription?.cancel());

    _connectionSubscription = _db.ref('.info/connected').onValue.listen((
      event,
    ) {
      if (event.snapshot.value != true) return;
      final ref = _presenceRef(uid);
      unawaited(
        ref
            .onDisconnect()
            .set({'state': 'offline'})
            .then((_) => ref.set({'state': 'online'}))
            .catchError((_) {
              // Best-effort : une présence qui échoue à s'écrire ne doit
              // jamais faire planter le reste de l'app.
            }),
      );
    });
  }

  /// Arrête le suivi de présence de l'utilisateur courant (déconnexion
  /// volontaire) — bascule tout de suite à "hors ligne" au lieu d'attendre
  /// la détection de coupure, meilleure UX qu'une simple fermeture d'app.
  Future<void> stop(String uid) async {
    unawaited(_connectionSubscription?.cancel());
    _connectionSubscription = null;
    _startedForUid = null;
    try {
      final ref = _presenceRef(uid);
      await ref.onDisconnect().cancel();
      await ref.set({'state': 'offline'});
    } catch (_) {
      // Best-effort.
    }
  }

  /// Flux de présence d'UN utilisateur donné (celui avec qui on discute).
  Stream<PresenceStatus> watch(String uid) {
    return _presenceRef(uid).onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) return PresenceStatus.offline;
      return PresenceStatus(isOnline: data['state'] == 'online');
    });
  }

  /// Marque/efface "en train d'écrire" pour CE chat précis. Auto-nettoyé
  /// en cas de déconnexion brutale (`onDisconnect().remove()`), et par
  /// l'appelant après un court délai d'inactivité ou à l'envoi (voir
  /// `chat_screen.dart`).
  Future<void> setTyping({
    required String chatId,
    required String uid,
    required bool isTyping,
  }) async {
    final ref = _typingRef(chatId, uid);
    try {
      if (isTyping) {
        await ref.onDisconnect().remove();
        await ref.set(true);
      } else {
        await ref.onDisconnect().cancel();
        await ref.remove();
      }
    } catch (_) {
      // Best-effort : ne doit jamais empêcher l'envoi du message lui-même.
    }
  }

  /// Flux "l'autre personne est en train d'écrire dans CE chat".
  Stream<bool> watchTyping({required String chatId, required String otherUid}) {
    return _typingRef(
      chatId,
      otherUid,
    ).onValue.map((event) => event.snapshot.value == true);
  }
}
