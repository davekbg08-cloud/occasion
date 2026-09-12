import 'status.dart' show StatusType;

/// `sending` et `failed` sont des états LOCAUX uniquement : le serveur
/// (`sendChatMessage`) n'écrit jamais ces valeurs, et `firestore.rules`
/// interdit toute modification client d'un message existant — ils ne
/// peuvent donc jamais se retrouver dans un document Firestore. Cycle de
/// vie réel : `sending` (local, en attente de confirmation) -> `sent`
/// (écrit par `sendChatMessage`) -> `delivered` (écrit par
/// `applyPushResult` si le push a réellement atteint un appareil) ->
/// `read` (écrit par `markChatAsRead`) ; `failed` si l'appel échoue
/// (local, retentable avec le même `clientMessageId`).
enum MessageStatus { sending, sent, delivered, read, failed }

class Message {
  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.status = MessageStatus.sent,
    required this.sentAt,
    this.mediaUrl,
    this.mediaType,
    this.mediaWidth,
    this.mediaHeight,
    this.forwardedFromChatId,
    this.forwardedFromMessageId,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String receiverId;
  final String content;
  final MessageStatus status;
  final DateTime sentAt;

  /// Photo/vidéo jointe — écrite exclusivement par `sendChatMessage`/
  /// `forwardChatMessage` (voir `functions/index.js`), jamais par le
  /// client sur un message existant. `content` reste alors une légende
  /// optionnelle (peut être vide).
  final String? mediaUrl;
  final StatusType? mediaType;
  final int? mediaWidth;
  final int? mediaHeight;

  /// Non-nuls uniquement si ce message est le résultat d'un transfert
  /// (`ChatNotifier.forwardMessage`) — affiche l'étiquette "Transféré".
  final String? forwardedFromChatId;
  final String? forwardedFromMessageId;

  bool get isRead => status == MessageStatus.read;
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get isForwarded => forwardedFromMessageId != null;

  factory Message.fromMap(Map<String, dynamic> map) {
    final mediaTypeRaw = map['mediaType'] as String?;
    return Message(
      id: map['id'] as String? ?? '',
      chatId: map['chatId'] as String? ?? '',
      senderId: map['senderId'] as String? ?? '',
      receiverId: map['receiverId'] as String? ?? '',
      content: map['content'] as String? ?? '',
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.sent,
      ),
      sentAt: DateTime.fromMillisecondsSinceEpoch(map['sentAt'] as int? ?? 0),
      mediaUrl: map['mediaUrl'] as String?,
      mediaType: mediaTypeRaw == 'video'
          ? StatusType.video
          : mediaTypeRaw == 'image'
          ? StatusType.image
          : null,
      mediaWidth: (map['mediaWidth'] as num?)?.toInt(),
      mediaHeight: (map['mediaHeight'] as num?)?.toInt(),
      forwardedFromChatId: map['forwardedFromChatId'] as String?,
      forwardedFromMessageId: map['forwardedFromMessageId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'chatId': chatId,
    'senderId': senderId,
    'receiverId': receiverId,
    'content': content,
    'status': status.name,
    'sentAt': sentAt.millisecondsSinceEpoch,
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (mediaType != null) 'mediaType': mediaType!.name,
    if (mediaWidth != null) 'mediaWidth': mediaWidth,
    if (mediaHeight != null) 'mediaHeight': mediaHeight,
    if (forwardedFromChatId != null) 'forwardedFromChatId': forwardedFromChatId,
    if (forwardedFromMessageId != null)
      'forwardedFromMessageId': forwardedFromMessageId,
  };

  Message copyWith({MessageStatus? status}) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      status: status ?? this.status,
      sentAt: sentAt,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      forwardedFromChatId: forwardedFromChatId,
      forwardedFromMessageId: forwardedFromMessageId,
    );
  }
}
