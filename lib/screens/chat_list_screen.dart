import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../l10n/app_language.dart';
import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/moderation_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/occasion_image.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({
    super.key,
    this.title = 'Messages',
    this.emptySubtitle =
        'Trouvez un article qui vous plaît et écrivez au vendeur : vos échanges apparaîtront ici.',
  });

  final String title;
  final String emptySubtitle;

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

/// Filtre de la boîte unique : toutes les conversations, celles où je suis
/// l'acheteur, ou celles où je suis le vendeur.
enum _ChatFilter { all, purchases, sales }

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  _ChatFilter _filter = _ChatFilter.all;

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
    final unblockedChats = me == null
        ? chatState.chats
        : chatState.chats
              .where((chat) => !blockedIds.contains(chat.otherUserId(me.id)))
              .toList();
    // Les filtres n'apparaissent que si l'utilisateur a réellement les deux
    // types de conversations (acheteur ET vendeur).
    final myId = me?.id;
    final hasPurchases =
        myId != null && unblockedChats.any((chat) => chat.buyerId == myId);
    final hasSales =
        myId != null && unblockedChats.any((chat) => chat.sellerId == myId);
    final showFilters = hasPurchases && hasSales;
    final visibleChats = !showFilters || _filter == _ChatFilter.all
        ? unblockedChats
        : unblockedChats
              .where(
                (chat) => _filter == _ChatFilter.purchases
                    ? chat.buyerId == myId
                    : chat.sellerId == myId,
              )
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
          preferredSize: Size.fromHeight(showFilters ? 49 : 1),
          child: Column(
            children: [
              if (showFilters)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final entry in const {
                        _ChatFilter.all: 'Tout',
                        _ChatFilter.purchases: 'Achats',
                        _ChatFilter.sales: 'Ventes',
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected: _filter == entry.key,
                            onSelected: (_) =>
                                setState(() => _filter = entry.key),
                          ),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
            ],
          ),
        ),
      ),
      body: chatState.isLoading && visibleChats.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : chatState.error != null && visibleChats.isEmpty
          ? const _MessageLoadError()
          : visibleChats.isEmpty
          ? _EmptyChats(subtitle: widget.emptySubtitle)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: visibleChats.length,
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
        title: Text(tr('Supprimer la conversation ?')),
        content: Text(tr('Elle disparaîtra de votre liste de messages.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Supprimer')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(chatNotifierProvider.notifier).deleteChat(chat.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('Conversation supprimée.'))));
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
    final image = chat.otherUserProfileImage(currentUserId)?.trim();
    final unreadCount = chat.unreadCountFor(currentUserId);
    final unread = unreadCount > 0;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final listingTitle = chat.listingTitle?.trim();

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _ChatAvatar(
              image: image,
              initial: initial,
              name: name,
              highlighted: unread,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (chat.lastMessageAt != null)
                        Text(
                          _formatDate(chat.lastMessageAt!),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  if (listingTitle != null && listingTitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.sell_outlined,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            listingTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.lastMessage ?? 'Dites bonjour 👋',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: unread
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight: unread
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      _UnreadBadge(count: unreadCount),
                      PopupMenuButton<String>(
                        tooltip: tr('Actions conversation'),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.more_horiz,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        onSelected: (value) {
                          if (value == 'delete') onDelete();
                          if (value == 'share') onShareInfo();
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'share',
                            child: ListTile(
                              leading: Icon(Icons.ios_share_outlined),
                              title: Text(tr('Partager infos utiles')),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              title: Text(tr('Supprimer conversation')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
    if (diff < 7) {
      const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
      return days[date.weekday - 1];
    }
    return DateFormat('dd/MM/yy').format(date);
  }
}

/// Texte affiché dans la pastille numérique : le compte exact jusqu'à 99,
/// `99+` au-delà (même convention que le badge natif de l'icône, voir
/// `functions/index.js::badgeCountForUser`).
String formatUnreadBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// Pastille numérique (nombre de messages non lus), masquée à 0 — remplace
/// l'ancien texte "Non lu"/"Lu" qui ne donnait aucune indication de volume.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      constraints: const BoxConstraints(minWidth: 22),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        formatUnreadBadgeLabel(count),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({
    required this.image,
    required this.initial,
    required this.name,
    required this.highlighted,
  });

  final String? image;
  final String initial;
  final String name;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final url = image;
    final Widget content = (url == null || url.isEmpty)
        ? CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.surfaceHigh,
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : ClipOval(
            child: OccasionImage.thumbnail(
              url,
              width: 52,
              height: 52,
              cacheWidth: 104,
              cacheHeight: 104,
              semanticsLabel: 'Photo de profil de $name',
            ),
          );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: highlighted ? AppColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: content,
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
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.forum_outlined,
              color: AppColors.primary,
              size: 44,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr('Pas encore de conversation'),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
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
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          tr(
            'Impossible de charger les messages. Vérifiez votre connexion ou vos droits d’accès.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
