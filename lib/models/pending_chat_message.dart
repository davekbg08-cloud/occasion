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
///
/// [mediaUrl] n'est renseigné qu'une fois l'upload Storage terminé (voir
/// `ChatNotifier.sendMediaMessage`) : tant que l'upload est en cours,
/// aucune entrée n'existe encore dans la boîte d'envoi — seules les
/// métadonnées (URL déjà obtenue, jamais les octets bruts de l'image/vidéo)
/// ont besoin de survivre à un redémarrage, exactement comme [content].
///
/// [forwardedFromChatId]/[forwardedFromMessageId] non-nuls indiquent que
/// cette entrée doit être envoyée via `sendChatMessage` puis `forwardMessage`
/// — voir `ChatNotifier._dispatchSend`.
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
    this.mediaUrl,
    this.mediaType,
    this.mediaWidth,
    this.mediaHeight,
    this.forwardedFromChatId,
    this.forwardedFromMessageId,
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
  final String? mediaUrl;
  final String? mediaType;
  final int? mediaWidth;
  final int? mediaHeight;
  final String? forwardedFromChatId;
  final String? forwardedFromMessageId;

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
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      forwardedFromChatId: forwardedFromChatId,
      forwardedFromMessageId: forwardedFromMessageId,
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
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (mediaType != null) 'mediaType': mediaType,
    if (mediaWidth != null) 'mediaWidth': mediaWidth,
    if (mediaHeight != null) 'mediaHeight': mediaHeight,
    if (forwardedFromChatId != null) 'forwardedFromChatId': forwardedFromChatId,
    if (forwardedFromMessageId != null)
      'forwardedFromMessageId': forwardedFromMessageId,
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
      mediaUrl: json['mediaUrl'] as String?,
      mediaType: json['mediaType'] as String?,
      mediaWidth: (json['mediaWidth'] as num?)?.toInt(),
      mediaHeight: (json['mediaHeight'] as num?)?.toInt(),
      forwardedFromChatId: json['forwardedFromChatId'] as String?,
      forwardedFromMessageId: json['forwardedFromMessageId'] as String?,
    );
  }
}
