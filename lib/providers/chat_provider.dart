import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../services/chat_service.dart';

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
  ChatNotifier({ChatService? service})
    : _service = service ?? ChatService(),
      super(const ChatState());

  final ChatService _service;
  StreamSubscription<List<Chat>>? _chatsSubscription;
  StreamSubscription<List<Message>>? _messagesSubscription;
  String? _listeningUserId;
  String? _listeningChatId;

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

  /// Envoi optimiste : insère immédiatement une bulle locale `sending`
  /// (jamais persistée telle quelle — voir `MessageStatus`), puis appelle
  /// la Cloud Function `sendChatMessage`. En cas d'échec, la bulle locale
  /// passe à `failed` (jamais dans [ChatState.error], qui reste réservé aux
  /// erreurs globales d'écran) ; [retryMessage] permet de retenter avec le
  /// même `clientMessageId`, donc sans jamais créer de doublon. En cas de
  /// succès, on ne fait rien de plus ici : le flux Firestore
  /// ([_reconcileWithFirestore]) remplacera la bulle locale par le document
  /// réel dès qu'il arrive — l'état local n'est jamais la source de vérité.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final clientMessageId = _service.newClientMessageId(chatId);
    final optimistic = Message(
      id: clientMessageId,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: trimmed,
      status: MessageStatus.sending,
      sentAt: DateTime.now(),
    );
    _appendLocalMessage(chatId, optimistic);

    await _dispatchSend(
      chatId: chatId,
      clientMessageId: clientMessageId,
      content: trimmed,
    );
  }

  /// Retente l'envoi d'une bulle en échec (`MessageStatus.failed`) en
  /// réutilisant EXACTEMENT le même `clientMessageId` — un nouveau clic sur
  /// Réessayer ne peut donc jamais produire un doublon, la Cloud Function
  /// reconnaît un rejeu sur un id déjà traité.
  Future<void> retryMessage(String chatId, String clientMessageId) async {
    final current = state.messagesByChatId[chatId] ?? const [];
    final target = _findById(current, clientMessageId);
    if (target == null || target.status != MessageStatus.failed) return;

    _replaceLocalMessage(
      chatId,
      target.copyWith(status: MessageStatus.sending),
    );
    await _dispatchSend(
      chatId: chatId,
      clientMessageId: clientMessageId,
      content: target.content,
    );
  }

  Future<void> _dispatchSend({
    required String chatId,
    required String clientMessageId,
    required String content,
  }) async {
    try {
      await _service.sendChatMessage(
        chatId: chatId,
        clientMessageId: clientMessageId,
        content: content,
      );
    } catch (_) {
      // Erreur réseau/serveur : jamais silencieuse, jamais dans l'état
      // d'erreur global (qui fermerait/masquerait tout l'écran) — la bulle
      // elle-même passe en échec avec un bouton Réessayer.
      final current = state.messagesByChatId[chatId] ?? const [];
      final target = _findById(current, clientMessageId);
      if (target != null) {
        _replaceLocalMessage(
          chatId,
          target.copyWith(status: MessageStatus.failed),
        );
      }
    }
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
