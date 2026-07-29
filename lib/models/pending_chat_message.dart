/// État local (jamais envoyé tel quel à Firestore) d'un message en cours
/// d'envoi ou en échec, persisté par [PendingMessageStore] pour survivre à
/// la fermeture complète de l'application — voir
/// `lib/services/pending_message_store.dart`.
enum PendingMessageState {
  queued,
  sending,
  failed;

  String get storageValue => name;

  static PendingMessageState fromStorageValue(String? value) {
    return PendingMessageState.values.firstWhere(
      (state) => state.storageValue == value,
      orElse: () => PendingMessageState.failed,
    );
  }
}

/// Une entrée de la boîte d'envoi locale. Clé logique :
/// `chatId` + `clientMessageId` (le `userId` propriétaire est déjà porté
/// par la clé de stockage dans [PendingMessageStore], pas répété ici).
///
/// Ne journalise jamais [content] — voir les appelants.
class PendingChatMessage {
  const PendingChatMessage({
    required this.clientMessageId,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.localCreatedAt,
    required this.state,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.lastErrorCode,
  });

  final String clientMessageId;
  final String chatId;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime localCreatedAt;
  final PendingMessageState state;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastErrorCode;

  PendingChatMessage copyWith({
    PendingMessageState? state,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
  }) {
    return PendingChatMessage(
      clientMessageId: clientMessageId,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      localCreatedAt: localCreatedAt,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastErrorCode: clearLastErrorCode
          ? null
          : (lastErrorCode ?? this.lastErrorCode),
    );
  }

  Map<String, dynamic> toJson() => {
    'clientMessageId': clientMessageId,
    'chatId': chatId,
    'senderId': senderId,
    'receiverId': receiverId,
    'content': content,
    'localCreatedAt': localCreatedAt.millisecondsSinceEpoch,
    'state': state.storageValue,
    'attemptCount': attemptCount,
    if (lastAttemptAt != null)
      'lastAttemptAt': lastAttemptAt!.millisecondsSinceEpoch,
    if (lastErrorCode != null) 'lastErrorCode': lastErrorCode,
  };

  factory PendingChatMessage.fromJson(Map<String, dynamic> json) {
    return PendingChatMessage(
      clientMessageId: json['clientMessageId'] as String,
      chatId: json['chatId'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      content: json['content'] as String,
      localCreatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['localCreatedAt'] as int,
      ),
      state: PendingMessageState.fromStorageValue(json['state'] as String?),
      attemptCount: json['attemptCount'] as int? ?? 0,
      lastAttemptAt: json['lastAttemptAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastAttemptAt'] as int)
          : null,
      lastErrorCode: json['lastErrorCode'] as String?,
    );
  }
}
