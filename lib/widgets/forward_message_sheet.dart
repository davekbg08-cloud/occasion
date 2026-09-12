import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';

/// Feuille de sélection de la conversation cible d'un transfert de message.
/// S'assure d'abord que la liste des conversations de l'utilisateur est
/// bien écoutée (`listenChats` — idempotent, sans effet si déjà en cours) :
/// un chat ouvert directement depuis une notification n'a jamais déclenché
/// ce chargement autrement (voir `chat_list_screen.dart`, seul autre
/// appelant de `listenChats`).
///
/// Retourne le [Chat] choisi, ou `null` si l'utilisateur annule.
Future<Chat?> showForwardMessageSheet(
  BuildContext context,
  WidgetRef ref, {
  required String excludeChatId,
}) {
  final myId = ref.read(authNotifierProvider).currentUser?.id ?? '';
  if (myId.isNotEmpty) {
    ref.read(chatNotifierProvider.notifier).listenChats(myId);
  }

  return showModalBottomSheet<Chat>(
    context: context,
    backgroundColor: Colors.grey[900],
    isScrollControlled: true,
    builder: (context) {
      return _ForwardMessageSheetBody(myId: myId, excludeChatId: excludeChatId);
    },
  );
}

class _ForwardMessageSheetBody extends ConsumerWidget {
  const _ForwardMessageSheetBody({
    required this.myId,
    required this.excludeChatId,
  });

  final String myId;
  final String excludeChatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(
      chatNotifierProvider.select((state) => state.chats),
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Transférer vers...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (chats.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune autre conversation.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final name = chat.otherUserName(myId);
                    final initial = name.isEmpty
                        ? '?'
                        : name.substring(0, 1).toUpperCase();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[700],
                        child: Text(
                          initial,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: chat.id == excludeChatId
                          ? const Text(
                              'Conversation actuelle',
                              style: TextStyle(color: Colors.grey),
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(chat),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
