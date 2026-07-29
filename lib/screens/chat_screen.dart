import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../models/report.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/occasion_image.dart';
import '../widgets/report_block_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chat});

  final Chat chat;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  String? _lastMessageId;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = ref.read(authNotifierProvider).currentUser?.id ?? '';
      ref
          .read(chatNotifierProvider.notifier)
          .listenMessages(widget.chat.id, uid);
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 120) {
      ref.read(chatNotifierProvider.notifier).loadOlderMessages(widget.chat.id);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _inputController.dispose();
    _scrollController.dispose();
    ref.read(chatNotifierProvider.notifier).clearMessages();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    final me = ref.read(authNotifierProvider).currentUser;
    if (me == null) return;

    await ref
        .read(chatNotifierProvider.notifier)
        .sendMessage(
          chatId: widget.chat.id,
          senderId: me.id,
          receiverId: widget.chat.otherUserId(me.id),
          content: text,
        );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authNotifierProvider).currentUser;
    final myId = me?.id ?? '';
    final chat = ref.watch(
      chatNotifierProvider.select(
        (state) => state.chats.firstWhere(
          (item) => item.id == widget.chat.id,
          orElse: () => widget.chat,
        ),
      ),
    );
    final messages = ref.watch(chatMessagesProvider(widget.chat.id));
    final otherName = chat.otherUserName(myId);
    final otherImage = chat.otherUserProfileImage(myId)?.trim();
    final otherId = chat.otherUserId(myId);
    final initial = otherName.isEmpty
        ? '?'
        : otherName.characters.first.toUpperCase();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        leadingWidth: 30,
        title: Row(
          children: [
            (otherImage == null || otherImage.isEmpty)
                ? CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey[700],
                    child: Text(
                      initial,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  )
                : ClipOval(
                    child: OccasionImage.thumbnail(
                      otherImage,
                      width: 36,
                      height: 36,
                      cacheWidth: 72,
                      cacheHeight: 72,
                      semanticsLabel: 'Photo de profil de $otherName',
                    ),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                otherName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (me != null && otherId.isNotEmpty)
            IconButton(
              tooltip: 'Signaler ou bloquer',
              onPressed: () => showReportOrBlockSheet(
                context,
                currentUserId: me.id,
                targetUserId: otherId,
                targetUserName: otherName,
                targetType: ReportTargetType.user,
              ),
              icon: const Icon(Icons.more_vert, color: Colors.white),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Builder(
              builder: (context) {
                // Ne scroller automatiquement vers le bas que lors de
                // l'arrivée d'un nouveau message à la fin (jamais quand on
                // vient de charger des messages plus anciens en tête de
                // liste, sinon la pagination vers le haut serait annulée).
                final newestId = messages.isEmpty ? null : messages.last.id;
                if (!_didInitialScroll && messages.isNotEmpty) {
                  _didInitialScroll = true;
                  _lastMessageId = newestId;
                  _scrollToBottom();
                } else if (newestId != null && newestId != _lastMessageId) {
                  _lastMessageId = newestId;
                  _scrollToBottom();
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Démarrez la conversation',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final isLoadingOlder = ref.watch(
                  chatNotifierProvider.select(
                    (state) => state.isLoadingOlderMessages,
                  ),
                );

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  itemCount: messages.length + (isLoadingOlder ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (isLoadingOlder && index == 0) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final messageIndex = isLoadingOlder ? index - 1 : index;
                    final message = messages[messageIndex];
                    final isMe = message.senderId == myId;
                    final showDate =
                        messageIndex == 0 ||
                        !_sameDay(
                          messages[messageIndex - 1].sentAt,
                          message.sentAt,
                        );

                    return Column(
                      children: [
                        if (showDate) _DateDivider(date: message.sentAt),
                        _Bubble(
                          message: message,
                          isMe: isMe,
                          onRetry: message.status == MessageStatus.failed
                              ? () => ref
                                    .read(chatNotifierProvider.notifier)
                                    .retryMessage(widget.chat.id, message.id)
                              : null,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _InputBar(controller: _inputController, onSend: _send),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isMe, this.onRetry});

  final Message message;
  final bool isMe;

  /// Non-null uniquement si [message.status] est `failed` — tapable pour
  /// retenter l'envoi avec le même `clientMessageId` (voir
  /// `ChatNotifier.retryMessage`), jamais de retry automatique.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = message.status == MessageStatus.failed;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          decoration: BoxDecoration(
            color: failed
                ? Colors.red[900]
                : isMe
                ? Colors.blue[700]
                : Colors.grey[800],
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.content,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failed) ...[
                    const Text(
                      'Échec de l\'envoi — Réessayer',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.error_outline,
                      size: 13,
                      color: Colors.white,
                    ),
                  ] else ...[
                    Text(
                      DateFormat('HH:mm').format(message.sentAt),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 10,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      _StatusIcon(status: message.status),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icône de statut d'un message envoyé par l'utilisateur courant :
/// horloge (en cours d'envoi), coche simple (envoyé), coche double grise
/// (livré à un appareil du destinataire), coche double bleue (lu).
/// `failed` est géré séparément par `_Bubble` (bulle rouge + texte),
/// jamais affiché ici.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time, size: 12, color: Colors.white54);
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 13, color: Colors.white54);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 13, color: Colors.white54);
      case MessageStatus.read:
        return const Icon(
          Icons.done_all,
          size: 13,
          color: Colors.lightBlueAccent,
        );
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 13, color: Colors.white54);
    }
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(date).inDays;
    final label = diff == 0
        ? "Aujourd'hui"
        : diff == 1
        ? 'Hier'
        : DateFormat('dd MMM yyyy').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Écrire un message...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSend,
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
