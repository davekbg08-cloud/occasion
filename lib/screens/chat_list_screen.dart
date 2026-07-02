import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/moderation_provider.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({
    super.key,
    this.title = 'Messages',
    this.emptySubtitle = 'Contactez un vendeur depuis une annonce',
  });

  final String title;
  final String emptySubtitle;

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = ref.read(authNotifierProvider).currentUser?.id;
      if (uid != null) {
        ref.read(chatNotifierProvider.notifier).listenChats(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final me = ref.watch(authNotifierProvider).currentUser;
    final blockedIds = me == null
        ? const <String>{}
        : ref
              .watch(blockedUserIdsProvider(me.id))
              .maybeWhen(data: (ids) => ids, orElse: () => const <String>{});
    final visibleChats = me == null
        ? chatState.chats
        : chatState.chats
              .where((chat) => !blockedIds.contains(chat.otherUserId(me.id)))
              .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[800]),
        ),
      ),
      body: chatState.isLoading && visibleChats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : chatState.error != null && visibleChats.isEmpty
          ? const _MessageLoadError()
          : visibleChats.isEmpty
          ? _EmptyChats(subtitle: widget.emptySubtitle)
          : ListView.separated(
              itemCount: visibleChats.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: Colors.grey[850], indent: 72),
              itemBuilder: (context, index) {
                final chat = visibleChats[index];
                return _ChatTile(
                  chat: chat,
                  currentUserId: me?.id ?? '',
                  onOpen: () => context.push('/chat-room', extra: chat),
                  onDelete: () => _confirmDelete(chat),
                  onShareInfo: () => _shareInfo(chat),
                );
              },
            ),
    );
  }

  Future<void> _confirmDelete(Chat chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la conversation ?'),
        content: const Text('Elle disparaîtra de votre liste de messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(chatNotifierProvider.notifier).deleteChat(chat.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Conversation supprimée.')));
  }

  void _shareInfo(Chat chat) {
    final title = chat.listingTitle?.trim();
    final message = title == null || title.isEmpty
        ? 'Informations utiles prêtes à être partagées.'
        : 'Informations de l’annonce "$title" prêtes à être partagées.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.currentUserId,
    required this.onOpen,
    required this.onDelete,
    required this.onShareInfo,
  });

  final Chat chat;
  final String currentUserId;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onShareInfo;

  @override
  Widget build(BuildContext context) {
    final name = chat.otherUserName(currentUserId);
    final image = chat.otherUserProfileImage(currentUserId);
    final unread = chat.unreadCount > 0;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final listingTitle = chat.listingTitle?.trim();

    return ListTile(
      onTap: onOpen,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey[800],
        backgroundImage: image == null
            ? null
            : CachedNetworkImageProvider(image),
        child: image == null
            ? Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: Colors.white,
                fontWeight: unread ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _ReadStatus(unread: unread),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listingTitle != null && listingTitle.isNotEmpty)
            Text(
              listingTitle,
              style: TextStyle(color: Colors.blue[200], fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            chat.lastMessage ?? 'Écrire un message',
            style: TextStyle(
              color: unread ? Colors.blue[300] : Colors.grey[500],
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (chat.lastMessageAt != null)
            Text(
              _formatDate(chat.lastMessageAt!),
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Écrire un message',
            onPressed: onOpen,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Actions conversation',
            onSelected: (value) {
              if (value == 'delete') onDelete();
              if (value == 'share') onShareInfo();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.ios_share_outlined),
                  title: Text('Partager infos utiles'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Supprimer conversation'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (diff == 0) return DateFormat('HH:mm').format(date);
    if (diff == 1) return 'Hier';
    return DateFormat('dd/MM/yyyy').format(date);
  }
}

class _ReadStatus extends StatelessWidget {
  const _ReadStatus({required this.unread});

  final bool unread;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: unread
            ? Colors.blue.withValues(alpha: 0.16)
            : Colors.grey.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        unread ? 'Non lu' : 'Lu',
        style: TextStyle(
          color: unread ? Colors.blue[200] : Colors.grey[400],
          fontSize: 11,
          fontWeight: unread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Aucune conversation',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MessageLoadError extends StatelessWidget {
  const _MessageLoadError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Impossible de charger les messages. Vérifiez votre connexion ou vos droits d’accès.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
