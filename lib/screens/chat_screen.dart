import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../models/report.dart';
import '../models/status.dart' show StatusType;
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/forward_message_sheet.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../widgets/fullscreen_video_viewer.dart';
import '../widgets/occasion_image.dart';
import '../widgets/report_block_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chat});

  final Chat chat;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  String? _lastMessageId;
  bool _didInitialScroll = false;
  bool _isUploadingMedia = false;
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = ref.read(authNotifierProvider).currentUser?.id ?? '';
      ref
          .read(chatNotifierProvider.notifier)
          .listenMessages(widget.chat.id, uid);
      // Réouverture de la conversation : retente automatiquement, de façon
      // bornée, les messages restés `failed`/en attente depuis une session
      // précédente (voir `retryAllPending`) — jamais de nouvel id généré.
      ref.read(chatNotifierProvider.notifier).retryAllPending(widget.chat.id);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour au premier plan : retente les messages en échec/en attente de
    // cette conversation, toujours borné (voir `retryAllPending`) — le
    // résultat réel de l'appel serveur reste la seule preuve de succès, pas
    // la simple présence d'une connexion.
    if (state == AppLifecycleState.resumed) {
      ref.read(chatNotifierProvider.notifier).retryAllPending(widget.chat.id);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 120) {
      ref.read(chatNotifierProvider.notifier).loadOlderMessages(widget.chat.id);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    // 1. Connexion vérifiée AVANT toute lecture/nettoyage du texte : le
    // champ ne doit jamais être vidé si l'utilisateur n'est plus connecté.
    final me = ref.read(authNotifierProvider).currentUser;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous devez être connecté pour envoyer un message.'),
        ),
      );
      return;
    }

    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    await ref
        .read(chatNotifierProvider.notifier)
        .sendMessage(
          chatId: widget.chat.id,
          senderId: me.id,
          receiverId: widget.chat.otherUserId(me.id),
          content: text,
          // Ne vider le champ qu'une fois la persistance locale confirmée
          // et la bulle optimiste affichée — jamais avant, jamais si la
          // sauvegarde locale échoue (voir ChatNotifier.sendMessage).
          onQueued: () {
            _inputController.clear();
            _scrollToBottom();
          },
        );
  }

  Future<void> _pickAndSendMedia(StatusType kind, ImageSource source) async {
    final me = ref.read(authNotifierProvider).currentUser;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous devez être connecté pour envoyer un message.'),
        ),
      );
      return;
    }

    final XFile? picked = kind == StatusType.video
        ? await _picker.pickVideo(
            source: source,
            maxDuration: const Duration(seconds: 30),
          )
        : await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      _isUploadingMedia = true;
      _uploadProgress = 0;
    });

    // La légende reprend le texte déjà saisi (le cas échéant), vidé
    // seulement une fois la bulle optimiste affichée — même principe que
    // `_send()` pour le texte pur.
    final caption = _inputController.text;

    try {
      await ref
          .read(chatNotifierProvider.notifier)
          .sendMediaMessage(
            chatId: widget.chat.id,
            senderId: me.id,
            receiverId: widget.chat.otherUserId(me.id),
            mediaFile: picked,
            mediaKind: kind,
            caption: caption,
            onUploadProgress: (progress) {
              if (!mounted) return;
              setState(() => _uploadProgress = progress);
            },
          );
      if (!mounted) return;
      _inputController.clear();
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Échec de l'envoi : ${kind == StatusType.video ? 'vidéo' : 'photo'} non envoyée (${_describeUploadError(error)}). Réessaie.",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  /// Détail court de l'erreur d'upload à afficher à l'utilisateur — sans
  /// ça, tout échec (règles Storage non déployées, non-authentification,
  /// fichier trop lourd...) affichait le même message générique, sans
  /// aucun moyen de savoir laquelle de ces causes est réellement en jeu.
  String _describeUploadError(Object error) {
    if (error is FirebaseException) {
      return error.message == null
          ? error.code
          : '${error.code} : ${error.message}';
    }
    return error.toString();
  }

  void _showAttachmentSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_outlined, color: Colors.white),
                title: const Text(
                  'Photo depuis la galerie',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndSendMedia(StatusType.image, ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Prendre une photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndSendMedia(StatusType.image, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.videocam_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Vidéo depuis la galerie',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndSendMedia(StatusType.video, ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showForwardSheet(Message message) async {
    final me = ref.read(authNotifierProvider).currentUser;
    if (me == null) return;

    final target = await showForwardMessageSheet(
      context,
      ref,
      excludeChatId: widget.chat.id,
    );
    if (target == null || !mounted) return;

    await ref
        .read(chatNotifierProvider.notifier)
        .forwardMessage(
          source: message,
          targetChatId: target.id,
          senderId: me.id,
          receiverId: target.otherUserId(me.id),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Transféré à ${target.otherUserName(me.id)}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Une erreur de persistance locale (ChatState.error, ex. l'écriture
    // SharedPreferences de la boîte d'envoi échoue) faisait échouer
    // silencieusement l'envoi : le texte restait dans le champ, aucune
    // bulle n'apparaissait, et rien n'indiquait pourquoi — l'utilisateur
    // devait retaper Envoyer sans savoir que le premier appui avait
    // réellement échoué. `ref.listen` ne se déclenche que sur un vrai
    // changement d'état (jamais à chaque rebuild), donc jamais de
    // SnackBar répétée pour la même erreur.
    ref.listen<ChatState>(chatNotifierProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Échec de l'envoi : ${next.error}. Réessaie."),
          ),
        );
      }
    });

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
                          // Transférer un message pas encore confirmé par
                          // le serveur échouerait (`forwardChatMessage` ne
                          // trouverait pas encore le document source) —
                          // uniquement disponible une fois envoyé/livré/lu.
                          onForward:
                              message.status != MessageStatus.sending &&
                                  message.status != MessageStatus.failed
                              ? () => _showForwardSheet(message)
                              : null,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _InputBar(
            controller: _inputController,
            onSend: _send,
            onAttach: _isUploadingMedia ? null : _showAttachmentSheet,
            isUploading: _isUploadingMedia,
            uploadProgress: _uploadProgress,
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMe,
    this.onRetry,
    this.onForward,
  });

  final Message message;
  final bool isMe;

  /// Non-null uniquement si [message.status] est `failed` — tapable pour
  /// retenter l'envoi avec le même `clientMessageId` (voir
  /// `ChatNotifier.retryMessage`), jamais de retry automatique.
  final VoidCallback? onRetry;

  /// Non-null uniquement pour un message déjà confirmé par le serveur
  /// (jamais `sending`/`failed`, voir `chat_screen.dart::build`) — appui
  /// long pour ouvrir le choix de conversation cible.
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    final failed = message.status == MessageStatus.failed;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
        onLongPress: onForward,
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
              if (message.isForwarded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shortcut,
                        size: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Transféré',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              if (message.hasMedia) _MediaContent(message: message),
              if (message.content.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: message.hasMedia ? 6 : 0),
                  child: Text(
                    message.content,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
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

/// Photo/vidéo d'une bulle : image tapable (plein écran, zoom) ou aperçu
/// vidéo tapable (lecture plein écran) — jamais de retry ici, réservé au
/// tap sur la bulle entière (voir `_Bubble.onTap`, `null` sauf `failed`).
class _MediaContent extends StatelessWidget {
  const _MediaContent({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl;
    if (url == null) return const SizedBox.shrink();

    final ratio =
        (message.mediaWidth != null &&
            message.mediaHeight != null &&
            message.mediaHeight! > 0)
        ? message.mediaWidth! / message.mediaHeight!
        : 4 / 3;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: () {
          if (message.mediaType == StatusType.video) {
            FullscreenVideoViewer.open(context, videoUrl: url);
          } else {
            FullscreenImageViewer.open(context, imageUrls: [url]);
          }
        },
        child: AspectRatio(
          aspectRatio: ratio.clamp(0.5, 2.0),
          child: message.mediaType == StatusType.video
              ? Container(
                  color: Colors.black,
                  child: const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                      size: 42,
                    ),
                  ),
                )
              : OccasionImage.thumbnail(
                  url,
                  width: double.infinity,
                  height: double.infinity,
                  cacheWidth: 600,
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
  const _InputBar({
    required this.controller,
    required this.onSend,
    this.onAttach,
    this.isUploading = false,
    this.uploadProgress = 0,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  /// `null` pendant un upload déjà en cours (voir `_ChatScreenState`) —
  /// jamais deux uploads simultanés depuis le même écran.
  final VoidCallback? onAttach;
  final bool isUploading;
  final double uploadProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUploading)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: uploadProgress > 0 ? uploadProgress : null,
                    minHeight: 3,
                    backgroundColor: Colors.grey[800],
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed: onAttach,
                  tooltip: 'Envoyer une photo ou une vidéo',
                  icon: Icon(
                    Icons.attach_file,
                    color: onAttach == null ? Colors.grey[600] : Colors.white,
                  ),
                ),
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
                    child: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
