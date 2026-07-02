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
  });

  final List<Chat> chats;
  final Map<String, List<Message>> messagesByChatId;
  final String? activeChatId;
  final bool isLoading;
  final String? error;

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
  }) {
    return ChatState(
      chats: chats ?? this.chats,
      messagesByChatId: messagesByChatId ?? this.messagesByChatId,
      activeChatId: clearActiveChat ? null : activeChatId ?? this.activeChatId,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
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
      state = state.copyWith(activeChatId: chatId, clearError: true);

      try {
        _messagesSubscription = _service
            .chatMessages(chatId)
            .listen(
              (list) {
                state = state.copyWith(
                  activeChatId: chatId,
                  messagesByChatId: {...state.messagesByChatId, chatId: list},
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
        .markAsRead(chatId, currentUserId)
        .then((_) => _clearUnread(chatId))
        .catchError((Object error) {
          state = state.copyWith(error: error.toString());
        });
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

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    try {
      await _service.sendMessage(
        chatId: chatId,
        senderId: senderId,
        receiverId: receiverId,
        content: content,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
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

  void _clearUnread(String chatId) {
    state = state.copyWith(
      chats: [
        for (final chat in state.chats)
          if (chat.id == chatId) chat.copyWith(unreadCount: 0) else chat,
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
