import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/presence_service.dart';

final presenceServiceProvider = Provider<PresenceService>((ref) {
  return PresenceService();
});

/// Statut de présence d'un utilisateur donné, en temps réel.
final presenceStatusProvider = StreamProvider.autoDispose
    .family<PresenceStatus, String>((ref, uid) {
      return ref.watch(presenceServiceProvider).watch(uid);
    });

/// "L'autre personne est en train d'écrire" dans un chat donné.
final typingProvider = StreamProvider.autoDispose
    .family<bool, ({String chatId, String otherUid})>((ref, args) {
      return ref
          .watch(presenceServiceProvider)
          .watchTyping(chatId: args.chatId, otherUid: args.otherUid);
    });
