import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Messages',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[800]),
        ),
      ),
      body: chatState.isLoading && chatState.chats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : chatState.error != null && chatState.chats.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Impossible de charger les messages : ${chatState.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          : chatState.chats.isEmpty
          ? const _EmptyChats()
          : ListView.separated(
              itemCount: chatState.chats.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: Colors.grey[850], indent: 72),
              itemBuilder: (context, index) {
                final chat = chatState.chats[index];
                return _ChatTile(
                  chat: chat,
                  currentUserId: me?.id ?? '',
                  onTap: () => context.push('/chat-room', extra: chat),
                );
              },
            ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.currentUserId,
    required this.onTap,
  });

  final Chat chat;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = chat.otherUserName(currentUserId);
    final image = chat.otherUserProfileImage(currentUserId);
    final unread = chat.unreadCount > 0;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
      title: Text(
        name,
        style: TextStyle(
          color: Colors.white,
          fontWeight: unread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        chat.lastMessage ?? 'Démarrer la conversation',
        style: TextStyle(
          color: unread ? Colors.blue[300] : Colors.grey[500],
          fontSize: 13,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (chat.lastMessageAt != null)
            Text(
              _formatDate(chat.lastMessageAt!),
              style: TextStyle(
                color: unread ? Colors.blue : Colors.grey[600],
                fontSize: 11,
              ),
            ),
          if (unread) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${chat.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date).inDays;
    if (diff == 0) return DateFormat('HH:mm').format(date);
    if (diff == 1) return 'Hier';
    return DateFormat('dd/MM').format(date);
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

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
            'Contactez un vendeur depuis le feed',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
