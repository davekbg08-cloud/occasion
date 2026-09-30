import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../l10n/app_language.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/report.dart';
import '../models/status.dart' show StatusType;
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/presence_provider.dart';
import '../theme/app_theme.dart';
import '../utils/action_feedback.dart';
import '../utils/user_display.dart';
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
  bool _hasNotifiedTyping = false;
  Timer? _typingStopTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputController.addListener(_onInputChanged);
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

  /// Annonce "en train d'écrire" dès la première frappe non vide, puis
  /// l'efface automatiquement après un court délai d'inactivité (pas
  /// besoin d'attendre l'envoi ou la fermeture de l'écran) — même principe
  /// que la plupart des messageries. `_hasNotifiedTyping` évite de
  /// réécrire `true` à chaque frappe (une seule écriture RTDB tant qu'on
  /// continue de taper).
  void _onInputChanged() {
    final me = ref.read(authNotifierProvider).currentUser;
    if (me == null) return;
    final hasText = _inputController.text.trim().isNotEmpty;

    if (hasText) {
      if (!_hasNotifiedTyping) {
        _hasNotifiedTyping = true;
        unawaited(
          ref
              .read(presenceServiceProvider)
              .setTyping(chatId: widget.chat.id, uid: me.id, isTyping: true),
        );
      }
      _typingStopTimer?.cancel();
      _typingStopTimer = Timer(
        const Duration(seconds: 4),
        () => _stopTyping(me.id),
      );
    } else if (_hasNotifiedTyping) {
      _stopTyping(me.id);
    }
  }

  void _stopTyping(String uid) {
    _typingStopTimer?.cancel();
    if (!_hasNotifiedTyping) return;
    _hasNotifiedTyping = false;
    unawaited(
      ref
          .read(presenceServiceProvider)
          .setTyping(chatId: widget.chat.id, uid: uid, isTyping: false),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _inputController.removeListener(_onInputChanged);
    _typingStopTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    try {
      final me = ref.read(authNotifierProvider).currentUser;
      if (me != null && _hasNotifiedTyping) {
        ref
            .read(presenceServiceProvider)
            .setTyping(chatId: widget.chat.id, uid: me.id, isTyping: false);
      }
      ref.read(chatNotifierProvider.notifier).clearMessages();
    } catch (_) {
      // Best-effort : si le ProviderScope est déjà en cours de démontage
      // (ex. relance abrupte de l'app), l'état en mémoire disparaît de
      // toute façon avec lui — pas la peine de faire planter l'app pour
      // un nettoyage qui n'a plus d'effet observable.
    }
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

  /// Vérifie la connexion avant tout envoi (texte, média, transfert) —
  /// affiche le même message d'erreur partout plutôt que de le répéter à
  /// chaque appelant.
  UserModel? _requireLoggedInUser() {
    final me = ref.read(authNotifierProvider).currentUser;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Vous devez être connecté pour envoyer un message.'),
          ),
        ),
      );
    }
    return me;
  }

  Future<void> _send() async {
    // 1. Connexion vérifiée AVANT toute lecture/nettoyage du texte : le
    // champ ne doit jamais être vidé si l'utilisateur n'est plus connecté.
    final me = _requireLoggedInUser();
    if (me == null) return;

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
            playActionFeedback();
            _inputController.clear();
            _scrollToBottom();
          },
        );
  }

  Future<void> _pickAndSendMedia(StatusType kind, ImageSource source) async {
    final me = _requireLoggedInUser();
    if (me == null) return;

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
      playActionFeedback();
      _inputController.clear();
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Échec de l'envoi : ${kind == StatusType.video ? 'vidéo' : 'photo'} non envoyée (${_describeUploadError(error)}). Réessaie.",
          ),
          // Durée par défaut (4s) trop courte pour lire/capturer le détail
          // technique de l'erreur — nécessaire pour le diagnostic à
          // distance (voir le code entre parenthèses).
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
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
                title: Text(
                  tr('Photo depuis la galerie'),
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
                title: Text(
                  tr('Prendre une photo'),
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
                title: Text(
                  tr('Vidéo depuis la galerie'),
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
    final me = _requireLoggedInUser();
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

  /// Menu d'appui long sur une bulle : transférer (déjà existant), et les
  /// deux modes de suppression — "pour moi" (toujours proposé, jamais de
  /// confirmation : n'affecte que mon propre affichage, rien d'irréversible
  /// pour l'autre participant) et "pour tout le monde" (uniquement pour
  /// l'expéditeur de ce message, confirmation requise — irréversible et
  /// visible des deux côtés, même garde que `_confirmDelete` dans
  /// `chat_list_screen.dart` pour une conversation entière).
  Future<void> _showMessageActions(Message message, bool isMe) async {
    final alreadyDeletedForEveryone = message.deletedForEveryone;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!alreadyDeletedForEveryone)
                ListTile(
                  leading: const Icon(Icons.shortcut, color: Colors.white),
                  title: Text(
                    tr('Transférer'),
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('forward'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.white),
                title: Text(
                  tr('Supprimer pour moi'),
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.of(sheetContext).pop('delete_for_me'),
              ),
              if (isMe && !alreadyDeletedForEveryone)
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(
                    tr('Supprimer pour tout le monde'),
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop('delete_for_everyone'),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'forward':
        await _showForwardSheet(message);
      case 'delete_for_me':
        await _deleteMessage(message, forEveryone: false);
      case 'delete_for_everyone':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Supprimer pour tout le monde ?')),
            content: Text(
              tr(
                "L'autre personne verra que ce message a été supprimé. "
                'Action irréversible.',
              ),
            ),
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
        if (confirmed == true) {
          await _deleteMessage(message, forEveryone: true);
        }
    }
  }

  Future<void> _deleteMessage(
    Message message, {
    required bool forEveryone,
  }) async {
    try {
      await ref
          .read(chatNotifierProvider.notifier)
          .deleteMessage(
            chatId: widget.chat.id,
            messageId: message.id,
            forEveryone: forEveryone,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Impossible de supprimer ce message.'))),
      );
    }
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
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
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
    // "Supprimer pour moi" (voir `ChatNotifier.deleteMessage`) : filtré
    // uniquement de MON affichage, jamais du document Firestore lui-même
    // — l'autre participant continue de voir ce message normalement.
    final messages = ref
        .watch(chatMessagesProvider(widget.chat.id))
        .where((m) => !m.isDeletedFor(myId))
        .toList();
    final otherName = chat.otherUserName(myId);
    final otherImage = chat.otherUserProfileImage(myId)?.trim();
    final otherId = chat.otherUserId(myId);
    final initial = otherName.isEmpty
        ? '?'
        : otherName.characters.first.toUpperCase();

    final listingTitle = chat.listingTitle?.trim();

    // Présence/frappe de l'AUTRE personne uniquement — jamais la mienne
    // (aucun sens de m'auto-afficher "en train d'écrire"). `valueOrNull`
    // reste `null` tant que le flux Realtime Database n'a pas encore émis
    // (connexion en cours) : traité comme "pas d'info", pas "hors ligne",
    // pour ne pas afficher un faux "Hors ligne" pendant une fraction de
    // seconde à l'ouverture de l'écran.
    final isOtherTyping =
        ref
            .watch(typingProvider((chatId: widget.chat.id, otherUid: otherId)))
            .valueOrNull ??
        false;
    final presence = ref.watch(presenceStatusProvider(otherId)).valueOrNull;
    final String? statusText;
    final Color statusColor;
    if (isOtherTyping) {
      statusText = tr("en train d'écrire...");
      statusColor = AppColors.primary;
    } else if (presence != null) {
      statusText = presence.isOnline ? tr('En ligne') : tr('Hors ligne');
      statusColor = presence.isOnline
          ? Colors.greenAccent
          : AppColors.textSecondary;
    } else {
      statusText = null;
      statusColor = AppColors.textSecondary;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leadingWidth: 30,
        title: Row(
          children: [
            (otherImage == null || otherImage.isEmpty)
                ? CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.surfaceHigh,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayNameWithTag(otherName, otherId),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (statusText != null)
                    Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (listingTitle != null && listingTitle.isNotEmpty)
                    Text(
                      listingTitle,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (me != null && otherId.isNotEmpty)
            IconButton(
              tooltip: tr('Signaler ou bloquer'),
              onPressed: () => showReportOrBlockSheet(
                context,
                currentUserId: me.id,
                targetUserId: otherId,
                targetUserName: otherName,
                targetType: ReportTargetType.user,
              ),
              icon: const Icon(Icons.more_vert),
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
                  return _ConversationStarter(
                    otherName: otherName,
                    onSuggestion: (text) {
                      _inputController.text = text;
                      _inputController.selection = TextSelection.collapsed(
                        offset: text.length,
                      );
                    },
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
                          // Transférer/supprimer un message pas encore
                          // confirmé par le serveur échouerait (le document
                          // source n'existe pas encore) — uniquement
                          // disponible une fois envoyé/livré/lu.
                          onLongPress:
                              message.status != MessageStatus.sending &&
                                  message.status != MessageStatus.failed
                              ? () => _showMessageActions(message, isMe)
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
    this.onLongPress,
  });

  final Message message;
  final bool isMe;

  /// Non-null uniquement si [message.status] est `failed` — tapable pour
  /// retenter l'envoi avec le même `clientMessageId` (voir
  /// `ChatNotifier.retryMessage`), jamais de retry automatique.
  final VoidCallback? onRetry;

  /// Non-null uniquement pour un message déjà confirmé par le serveur
  /// (jamais `sending`/`failed`, voir `chat_screen.dart::build`) — appui
  /// long pour ouvrir le menu transférer/supprimer.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final failed = message.status == MessageStatus.failed;
    final deleted = message.deletedForEveryone;
    // Texte sombre sur la bulle turquoise (lisibilité), clair ailleurs.
    final textColor = isMe && !failed
        ? AppColors.onPrimary
        : AppColors.textPrimary;
    final metaColor = textColor.withValues(alpha: 0.6);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: failed
                ? Colors.red[900]
                : isMe
                ? AppColors.primary
                : AppColors.surfaceHigh,
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
              if (deleted)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 14, color: metaColor),
                    const SizedBox(width: 5),
                    Text(
                      tr('Message supprimé'),
                      style: TextStyle(
                        color: metaColor,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                )
              else ...[
                if (message.isForwarded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shortcut, size: 12, color: metaColor),
                        const SizedBox(width: 3),
                        Text(
                          tr('Transféré'),
                          style: TextStyle(
                            color: metaColor,
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
                      style: TextStyle(color: textColor, fontSize: 15),
                    ),
                  ),
              ],
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failed) ...[
                    Text(
                      tr('Échec de l\'envoi — Réessayer'),
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
                      style: TextStyle(color: metaColor, fontSize: 10),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      _StatusIcon(status: message.status, color: metaColor),
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
  const _StatusIcon({required this.status, required this.color});

  final MessageStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.access_time, size: 12, color: color);
      case MessageStatus.sent:
        return Icon(Icons.done, size: 13, color: color);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 13, color: color);
      case MessageStatus.read:
        // Lu : coche pleine et opaque (contraste sur la bulle turquoise).
        return const Icon(Icons.done_all, size: 14, color: AppColors.onPrimary);
      case MessageStatus.failed:
        return Icon(Icons.error_outline, size: 13, color: color);
    }
  }
}

/// Conversation vide : suggestions de premiers messages pour lancer
/// l'échange en un appui (le texte est placé dans le champ, jamais envoyé
/// automatiquement).
class _ConversationStarter extends StatelessWidget {
  const _ConversationStarter({
    required this.otherName,
    required this.onSuggestion,
  });

  final String otherName;
  final ValueChanged<String> onSuggestion;

  static const _suggestions = [
    'Bonjour, est-ce toujours disponible ?',
    'Quel est votre dernier prix ?',
    'Où peut-on se rencontrer ?',
    'Pouvez-vous envoyer plus de photos ?',
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.waving_hand_outlined,
                color: AppColors.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Dites bonjour à $otherName',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Choisissez un message pour commencer :'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final text in _suggestions)
                  ActionChip(
                    label: Text(text),
                    onPressed: () => onSuggestion(text),
                  ),
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
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
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                    backgroundColor: AppColors.surfaceHigh,
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed: onAttach,
                  tooltip: tr('Envoyer une photo ou une vidéo'),
                  icon: Icon(
                    Icons.attach_file,
                    color: onAttach == null
                        ? AppColors.outline
                        : AppColors.textSecondary,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(color: AppColors.textPrimary),
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: tr('Écrire un message...'),
                      hintStyle: const TextStyle(
                        color: AppColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.primary),
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
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: AppColors.onPrimary,
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
