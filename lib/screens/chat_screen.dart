import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../models/report.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = ref.read(authNotifierProvider).currentUser?.id ?? '';
      ref
          .read(chatNotifierProvider.notifier)
          .listenMessages(widget.chat.id, uid);
    });
  }

  @override
  void dispose() {
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
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[700],
              child: Text(
                initial,
                style: const TextStyle(color: Colors.white, fontSize: 14),
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
                _scrollToBottom();

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Démarrez la conversation',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == myId;
                    final showDate =
                        index == 0 ||
                        !_sameDay(messages[index - 1].sentAt, message.sentAt);

                    return Column(
                      children: [
                        if (showDate) _DateDivider(date: message.sentAt),
                        _Bubble(message: message, isMe: isMe),
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
  const _Bubble({required this.message, required this.isMe});

  final Message message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[700] : Colors.grey[800],
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
                Text(
                  DateFormat('HH:mm').format(message.sentAt),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 3),
                  Icon(
                    message.status == MessageStatus.read
                        ? Icons.done_all
                        : Icons.done,
                    size: 13,
                    color: message.status == MessageStatus.read
                        ? Colors.lightBlueAccent
                        : Colors.white54,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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
