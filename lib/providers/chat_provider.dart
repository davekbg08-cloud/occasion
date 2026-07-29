import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../models/pending_chat_message.dart';
import '../services/chat_service.dart';
import '../services/pending_message_store.dart';

class ChatState {
  const ChatState({
    this.chats = const [],
    this.messagesByChatId = const {},
    this.activeChatId,
    this.isLoading = false,
    this.error,
    this.isLoadingOlderMessages = false,
    this.hasMoreOlderMessages = true,
  });

  final List<Chat> chats;
  final Map<String, List<Message>> messagesByChatId;
  final String? activeChatId;
  final bool isLoading;
  final String? error;
  final bool isLoadingOlderMessages;
  final bool hasMoreOlderMessages;

  List<Message> get messages {
    final chatId = activeChatId;
    if (chatId == null) return const [];
    return messagesByChatId[chatId] ?? const [];
  }

  ChatState copyWith({
    List<Chat>? chats,
    Map<String, List<Message>>? messagesByChatId,
    String? activeChatId,
    bool? isLoading,
    String? error,
    bool clearActiveChat = false,
    bool clearError = false,
    bool? isLoadingOlderMessages,
    bool? hasMoreOlderMessages,
  }) {
    return ChatState(
      chats: chats ?? this.chats,
      messagesByChatId: messagesByChatId ?? this.messagesByChatId,
      activeChatId: clearActiveChat ? null : activeChatId ?? this.activeChatId,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      isLoadingOlderMessages:
          isLoadingOlderMessages ?? this.isLoadingOlderMessages,
      hasMoreOlderMessages: hasMoreOlderMessages ?? this.hasMoreOlderMessages,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier({ChatService? service, PendingMessageStore? pendingStore})
    : _service = service ?? ChatService(),
      _pendingStore = pendingStore ?? const PendingMessageStore(),
      super(const ChatState());

  final ChatService _service;
  final PendingMessageStore _pendingStore;
  StreamSubscription<List<Chat>>? _chatsSubscription;
  StreamSubscription<List<Message>>? _messagesSubscription;
  String? _listeningUserId;
  String? _listeningChatId;
  String? _pendingLoadedForChatId;

  void listenChats(String userId) {
    if (userId.isEmpty || _listeningUserId == userId) return;

    _listeningUserId = userId;
    _chatsSubscription?.cancel();
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      _chatsSubscription = _service
          .userChats(userId)
          .listen(
            (list) {
              state = state.copyWith(
                chats: list,
                isLoading: false,
                clearError: true,
              );
            },
            onError: (Object error) {
              state = state.copyWith(isLoading: false, error: error.toString());
            },
          );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  void listenMessages(String chatId, String currentUserId) {
    if (chatId.isEmpty) return;

    if (_listeningChatId != chatId) {
      _listeningChatId = chatId;
      _messagesSubscription?.cancel();
      state = state.copyWith(
        activeChatId: chatId,
        clearError: true,
        hasMoreOlderMessages: true,
      );

      if (currentUserId.isNotEmpty && _pendingLoadedForChatId != chatId) {
        _pendingLoadedForChatId = chatId;
        unawaited(_loadPendingForChat(chatId, currentUserId));
      }

      try {
        _messagesSubscription = _service
            .chatMessages(chatId)
            .listen(
              (list) {
                state = state.copyWith(
                  activeChatId: chatId,
                  messagesByChatId: {
                    ...state.messagesByChatId,
                    chatId: _reconcileWithFirestore(chatId, list),
                  },
                  clearError: true,
                );
                if (currentUserId.isNotEmpty) {
                  unawaited(
                    _pruneConfirmedPending(chatId, currentUserId, list),
                  );
                }
              },
              onError: (Object error) {
                state = state.copyWith(error: error.toString());
              },
            );
      } catch (error) {
        state = state.copyWith(error: error.toString());
      }
    }

    if (currentUserId.isEmpty) return;

    _service
        .markAsRead(chatId)
        .then((_) => _clearUnread(chatId, currentUserId))
        .catchError((Object error) {
          // Erreur réseau/serveur : ne ferme jamais la conversation, se
          // contente de signaler l'échec (l'utilisateur reste sur l'écran,
          // un prochain appel à listenMessages — ex. réouverture du chat —
          // retentera naturellement).
          state = state.copyWith(error: error.toString());
        });
  }

  /// Recharge, à l'ouverture d'une conversation, les messages
  /// `queued`/`sending`/`failed` encore persistés localement pour cet
  /// utilisateur et ce chat (survivants d'une fermeture complète de
  /// l'application) et les réinjecte comme bulles locales — sans jamais
  /// générer de nouveau `clientMessageId`. La comparaison avec le flux
  /// Firestore ([_pruneConfirmedPending]) élimine ensuite celles qui se
  /// révèlent déjà confirmées côté serveur (réponse de l'appel callable
  /// perdue mais message réellement créé).
  Future<void> _loadPendingForChat(String chatId, String userId) async {
    List<PendingChatMessage> pending;
    try {
      pending = await _pendingStore.load(userId);
    } catch (_) {
      return;
    }
    final forThisChat = pending.where((p) => p.chatId == chatId).toList();
    if (forThisChat.isEmpty) return;

    final current = state.messagesByChatId[chatId] ?? const [];
    final existingIds = current.map((m) => m.id).toSet();
    final restored = [
      for (final p in forThisChat)
        if (!existingIds.contains(p.clientMessageId))
          Message(
            id: p.clientMessageId,
            chatId: p.chatId,
            senderId: p.senderId,
            receiverId: p.receiverId,
            content: p.content,
            status: p.state == PendingMessageState.failed
                ? MessageStatus.failed
                : MessageStatus.sending,
            sentAt: p.localCreatedAt,
          ),
    ];
    if (restored.isEmpty) return;

    state = state.copyWith(
      messagesByChatId: {
        ...state.messagesByChatId,
        chatId: [...current, ...restored],
      },
    );
  }

  /// Retire de la boîte d'envoi locale toute entrée dont le
  /// `clientMessageId` apparaît désormais dans le flux Firestore — le
  /// message est confirmé, l'entrée locale n'a plus de raison d'être
  /// (qu'il ait été envoyé par cette session ou reconnu ici après une
  /// réponse callable perdue, voir section 5 de la spécification).
  Future<void> _pruneConfirmedPending(
    String chatId,
    String userId,
    List<Message> firestoreMessages,
  ) async {
    List<PendingChatMessage> pending;
    try {
      pending = await _pendingStore.load(userId);
    } catch (_) {
      return;
    }
    final firestoreIds = firestoreMessages.map((m) => m.id).toSet();
    for (final p in pending) {
      if (p.chatId == chatId && firestoreIds.contains(p.clientMessageId)) {
        await _pendingStore.remove(userId, chatId, p.clientMessageId);
      }
    }
  }

  /// Charge une page supplémentaire de messages plus anciens que le plus
  /// vieux message actuellement chargé (lecture ponctuelle, pas un stream).
  Future<void> loadOlderMessages(String chatId) async {
    if (state.isLoadingOlderMessages || !state.hasMoreOlderMessages) return;
    final current = state.messagesByChatId[chatId] ?? const [];
    if (current.isEmpty) return;

    state = state.copyWith(isLoadingOlderMessages: true);
    try {
      final older = await _service.fetchOlderMessages(
        chatId: chatId,
        before: current.first.sentAt,
      );
      state = state.copyWith(
        messagesByChatId: {
          ...state.messagesByChatId,
          chatId: [...older, ...current],
        },
        isLoadingOlderMessages: false,
        hasMoreOlderMessages: older.length >= ChatService.messagePageSize,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingOlderMessages: false,
        error: error.toString(),
      );
    }
  }

  Future<Chat> openChat({
    required String buyerId,
    required String sellerId,
    required String buyerName,
    required String sellerName,
    String? buyerProfileImageUrl,
    String? sellerProfileImageUrl,
    String? listingId,
    String? listingTitle,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final chat = await _service.getOrCreateChat(
        buyerId: buyerId,
        sellerId: sellerId,
        buyerName: buyerName,
        sellerName: sellerName,
        buyerProfileImageUrl: buyerProfileImageUrl,
        sellerProfileImageUrl: sellerProfileImageUrl,
        listingId: listingId,
        listingTitle: listingTitle,
      );

      _upsertChat(chat);
      state = state.copyWith(isLoading: false, clearError: true);
      return chat;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
      rethrow;
    }
  }

  /// Envoi optimiste, dans cet ordre précis (jamais réarrangé) :
  /// génère `clientMessageId` → construit l'entrée locale `queued` → la
  /// PERSISTE (boîte d'envoi locale, survit à la fermeture complète de
  /// l'app) → seulement une fois cette persistance confirmée, affiche la
  /// bulle optimiste et appelle [onQueued] (le seul moment où l'appelant —
  /// `chat_screen.dart` — a le droit de vider son champ de saisie) → passe
  /// l'entrée à `sending` → appelle la Cloud Function `sendChatMessage`.
  ///
  /// Si la persistance locale échoue, [onQueued] n'est jamais appelé (le
  /// texte doit rester dans le champ), l'erreur est visible via
  /// [ChatState.error] et aucun appel réseau n'est déclenché. En cas
  /// d'échec réseau, la bulle locale passe à `failed` (jamais dans
  /// [ChatState.error], réservé aux erreurs globales d'écran) ;
  /// [retryMessage] permet de retenter avec le même `clientMessageId`,
  /// donc sans jamais créer de doublon. En cas de succès, on ne fait rien
  /// de plus ici : le flux Firestore ([_reconcileWithFirestore]) remplacera
  /// la bulle locale par le document réel dès qu'il arrive — l'état local
  /// n'est jamais la source de vérité.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String content,
    void Function()? onQueued,
  }) async {
    if (senderId.isEmpty) return;
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final clientMessageId = _service.newClientMessageId(chatId);
    final now = DateTime.now();
    final pending = PendingChatMessage(
      clientMessageId: clientMessageId,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: trimmed,
      localCreatedAt: now,
      state: PendingMessageState.queued,
    );

    try {
      await _pendingStore.upsert(senderId, pending);
    } catch (error) {
      state = state.copyWith(error: error.toString());
      return;
    }

    final optimistic = Message(
      id: clientMessageId,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: trimmed,
      status: MessageStatus.sending,
      sentAt: now,
    );
    _appendLocalMessage(chatId, optimistic);
    onQueued?.call();

    await _dispatchSend(
      userId: senderId,
      chatId: chatId,
      clientMessageId: clientMessageId,
      content: trimmed,
      basePending: pending,
    );
  }

  /// Retente l'envoi d'une bulle en échec (`MessageStatus.failed`) en
  /// réutilisant EXACTEMENT le même `clientMessageId` — un nouveau clic sur
  /// Réessayer, ou un retry automatique borné (voir `retryAllPending`), ne
  /// peut donc jamais produire un doublon ni générer un nouvel id.
  Future<void> retryMessage(String chatId, String clientMessageId) async {
    final current = state.messagesByChatId[chatId] ?? const [];
    final target = _findById(current, clientMessageId);
    if (target == null || target.status != MessageStatus.failed) return;

    _replaceLocalMessage(
      chatId,
      target.copyWith(status: MessageStatus.sending),
    );
    await _dispatchSend(
      userId: target.senderId,
      chatId: chatId,
      clientMessageId: clientMessageId,
      content: target.content,
      basePending: PendingChatMessage(
        clientMessageId: clientMessageId,
        chatId: chatId,
        senderId: target.senderId,
        receiverId: target.receiverId,
        content: target.content,
        localCreatedAt: target.sentAt,
        state: PendingMessageState.failed,
      ),
    );
  }

  /// Retente, de façon bornée (jamais de boucle infinie), tous les
  /// messages `failed`/en attente d'un chat — déclenché par le retour au
  /// premier plan de l'application ou la réouverture d'une conversation
  /// (voir `chat_screen.dart`), jamais en tâche de fond illimitée. Le
  /// résultat réel de l'appel serveur reste la seule source de vérité : la
  /// simple présence d'une connexion ne garantit rien, ce retry ne fait que
  /// retenter l'appel, jamais supposer un succès.
  static const int maxAutoRetryAttempts = 5;

  Future<void> retryAllPending(String chatId) async {
    final current = state.messagesByChatId[chatId] ?? const [];
    final failedIds = current
        .where((m) => m.status == MessageStatus.failed)
        .map((m) => m.id)
        .toList();
    for (final id in failedIds) {
      final pending = await _pendingStore.load(
        current.firstWhere((m) => m.id == id).senderId,
      );
      final entry = _findPending(pending, chatId, id);
      if (entry != null && entry.attemptCount >= maxAutoRetryAttempts) {
        continue; // plafond atteint : reste visible avec Réessayer manuel.
      }
      await retryMessage(chatId, id);
    }
  }

  PendingChatMessage? _findPending(
    List<PendingChatMessage> entries,
    String chatId,
    String clientMessageId,
  ) {
    for (final entry in entries) {
      if (entry.chatId == chatId && entry.clientMessageId == clientMessageId) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _dispatchSend({
    required String userId,
    required String chatId,
    required String clientMessageId,
    required String content,
    required PendingChatMessage basePending,
  }) async {
    final priorAttempts = _findPending(
      await _pendingStore.load(userId),
      chatId,
      clientMessageId,
    )?.attemptCount;

    await _pendingStore.upsert(
      userId,
      basePending.copyWith(
        state: PendingMessageState.sending,
        attemptCount: (priorAttempts ?? basePending.attemptCount) + 1,
        lastAttemptAt: DateTime.now(),
      ),
    );

    try {
      await _service.sendChatMessage(
        chatId: chatId,
        clientMessageId: clientMessageId,
        content: content,
      );
      await _pendingStore.remove(userId, chatId, clientMessageId);
    } catch (error) {
      // Erreur réseau/serveur : jamais silencieuse, jamais dans l'état
      // d'erreur global (qui fermerait/masquerait tout l'écran) — la bulle
      // elle-même passe en échec avec un bouton Réessayer. Le texte et le
      // clientMessageId restent inchangés dans la boîte d'envoi locale.
      final current = state.messagesByChatId[chatId] ?? const [];
      final target = _findById(current, clientMessageId);
      if (target != null) {
        _replaceLocalMessage(
          chatId,
          target.copyWith(status: MessageStatus.failed),
        );
      }
      await _pendingStore.upsert(
        userId,
        basePending.copyWith(
          state: PendingMessageState.failed,
          attemptCount: (priorAttempts ?? basePending.attemptCount) + 1,
          lastAttemptAt: DateTime.now(),
          lastErrorCode: _errorCodeOf(error),
        ),
      );
    }
  }

  String _errorCodeOf(Object error) {
    if (error is FirebaseFunctionsException) return error.code;
    return 'unknown';
  }

  Message? _findById(List<Message> messages, String id) {
    for (final message in messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _appendLocalMessage(String chatId, Message message) {
    final current = state.messagesByChatId[chatId] ?? const [];
    state = state.copyWith(
      messagesByChatId: {
        ...state.messagesByChatId,
        chatId: [...current, message],
      },
    );
  }

  void _replaceLocalMessage(String chatId, Message message) {
    final current = state.messagesByChatId[chatId] ?? const [];
    state = state.copyWith(
      messagesByChatId: {
        ...state.messagesByChatId,
        chatId: [
          for (final m in current)
            if (m.id == message.id) message else m,
        ],
      },
    );
  }

  /// Fusionne la liste autoritaire reçue de Firestore avec les bulles
  /// locales encore `sending`/`failed` qui n'ont pas (ou pas encore) de
  /// contrepartie dans ce flux : dès qu'un document Firestore porte le même
  /// id qu'une bulle locale (l'id EST le `clientMessageId`), la bulle
  /// locale disparaît au profit du document réel — l'état local n'est
  /// jamais gardé comme source de vérité une fois confirmé par le serveur.
  List<Message> _reconcileWithFirestore(
    String chatId,
    List<Message> firestoreMessages,
  ) {
    final firestoreIds = firestoreMessages.map((m) => m.id).toSet();
    final stillPendingLocal = (state.messagesByChatId[chatId] ?? const [])
        .where(
          (m) =>
              (m.status == MessageStatus.sending ||
                  m.status == MessageStatus.failed) &&
              !firestoreIds.contains(m.id),
        )
        .toList();
    return [...firestoreMessages, ...stillPendingLocal];
  }

  Future<void> deleteChat(String chatId) async {
    try {
      await _service.deleteChat(chatId);
      state = state.copyWith(
        chats: state.chats.where((chat) => chat.id != chatId).toList(),
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void clearMessages() {
    state = state.copyWith(clearActiveChat: true);
  }

  /// Réinitialise entièrement l'état en mémoire (chats, messages, erreurs)
  /// et arrête les flux en cours — appelé lors d'un changement d'utilisateur
  /// (connexion d'un compte différent après déconnexion) ou d'une
  /// déconnexion simple, jamais pendant une session normale. Ne touche
  /// jamais la boîte d'envoi persistante d'un autre utilisateur (déjà
  /// isolée par clé de stockage) : seul l'état EN MÉMOIRE de ce notifier est
  /// concerné, pour ne jamais laisser les messages d'un ancien compte
  /// visibles au suivant.
  void resetForUserChange() {
    _chatsSubscription?.cancel();
    _messagesSubscription?.cancel();
    _chatsSubscription = null;
    _messagesSubscription = null;
    _listeningUserId = null;
    _listeningChatId = null;
    _pendingLoadedForChatId = null;
    state = const ChatState();
  }

  void _upsertChat(Chat chat) {
    final index = state.chats.indexWhere((item) => item.id == chat.id);
    final chats = [...state.chats];

    if (index == -1) {
      chats.insert(0, chat);
    } else {
      chats[index] = chat;
    }

    state = state.copyWith(chats: chats);
  }

  void _clearUnread(String chatId, String userId) {
    state = state.copyWith(
      chats: [
        for (final chat in state.chats)
          if (chat.id == chatId) chat.clearUnreadFor(userId) else chat,
      ],
    );
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    _messagesSubscription?.cancel();
    super.dispose();
  }
}

final chatNotifierProvider = StateNotifierProvider<ChatNotifier, ChatState>((
  ref,
) {
  return ChatNotifier();
});

final chatMessagesProvider = Provider.family<List<Message>, String>((
  ref,
  chatId,
) {
  return ref.watch(
    chatNotifierProvider.select(
      (state) => state.messagesByChatId[chatId] ?? const [],
    ),
  );
});
