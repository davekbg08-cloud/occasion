enum MessageStatus { sent, delivered, read }

class Message {
  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.status = MessageStatus.sent,
    required this.sentAt,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String receiverId;
  final String content;
  final MessageStatus status;
  final DateTime sentAt;

  bool get isRead => status == MessageStatus.read;

  factory Message.fromMap(Map<String, dynamic> map) {
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
    );
  }
}
