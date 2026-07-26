class Chat {
  const Chat({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    required this.buyerName,
    required this.sellerName,
    this.buyerProfileImageUrl,
    this.sellerProfileImageUrl,
    this.listingId,
    this.listingTitle,
    this.lastMessage,
    this.lastMessageAt,
    this.lastSenderId,
    this.buyerUnreadCount = 0,
    this.sellerUnreadCount = 0,
  });

  final String id;
  final String buyerId;
  final String sellerId;
  final String buyerName;
  final String sellerName;
  final String? buyerProfileImageUrl;
  final String? sellerProfileImageUrl;
  final String? listingId;
  final String? listingTitle;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderId;
  final int buyerUnreadCount;
  final int sellerUnreadCount;

  /// Compteur de messages non lus propre à [userId] — jamais celui de
  /// l'autre participant (contrairement à l'ancien `unreadCount` partagé).
  int unreadCountFor(String userId) {
    return userId == buyerId ? buyerUnreadCount : sellerUnreadCount;
  }

  String otherUserName(String currentUserId) {
    return currentUserId == buyerId ? sellerName : buyerName;
  }

  String? otherUserProfileImage(String currentUserId) {
    return currentUserId == buyerId
        ? sellerProfileImageUrl
        : buyerProfileImageUrl;
  }

  String otherUserId(String currentUserId) {
    return currentUserId == buyerId ? sellerId : buyerId;
  }

  factory Chat.fromMap(Map<String, dynamic> map) {
    // Compat temporaire : tant qu'une conversation n'a pas été migrée (pas
    // encore de buyerUnreadCount/sellerUnreadCount écrits), on retombe sur
    // l'ancien compteur partagé pour les deux côtés plutôt que 0 — comme
    // avant la migration, pas pire. Voir tool/migrate_chat_unread_counts.dart.
    final legacyUnread = map['unreadCount'] as int? ?? 0;
    return Chat(
      id: map['id'] as String? ?? '',
      buyerId: map['buyerId'] as String? ?? '',
      sellerId: map['sellerId'] as String? ?? '',
      buyerName: map['buyerName'] as String? ?? '',
      sellerName: map['sellerName'] as String? ?? '',
      buyerProfileImageUrl: map['buyerProfileImageUrl'] as String?,
      sellerProfileImageUrl: map['sellerProfileImageUrl'] as String?,
      listingId: map['listingId'] as String?,
      listingTitle: map['listingTitle'] as String?,
      lastMessage: map['lastMessage'] as String?,
      lastMessageAt: map['lastMessageAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastMessageAt'] as int)
          : null,
      lastSenderId: map['lastSenderId'] as String?,
      buyerUnreadCount: map['buyerUnreadCount'] as int? ?? legacyUnread,
      sellerUnreadCount: map['sellerUnreadCount'] as int? ?? legacyUnread,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'buyerId': buyerId,
    'sellerId': sellerId,
    'buyerName': buyerName,
    'sellerName': sellerName,
    'buyerProfileImageUrl': buyerProfileImageUrl,
    'sellerProfileImageUrl': sellerProfileImageUrl,
    'listingId': listingId,
    'listingTitle': listingTitle,
    'participants': [buyerId, sellerId],
    'lastMessage': lastMessage,
    'lastMessageAt': lastMessageAt?.millisecondsSinceEpoch,
    'lastSenderId': lastSenderId,
    'buyerUnreadCount': buyerUnreadCount,
    'sellerUnreadCount': sellerUnreadCount,
  };

  Chat copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastSenderId,
    int? buyerUnreadCount,
    int? sellerUnreadCount,
  }) {
    return Chat(
      id: id,
      buyerId: buyerId,
      sellerId: sellerId,
      buyerName: buyerName,
      sellerName: sellerName,
      buyerProfileImageUrl: buyerProfileImageUrl,
      sellerProfileImageUrl: sellerProfileImageUrl,
      listingId: listingId,
      listingTitle: listingTitle,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      buyerUnreadCount: buyerUnreadCount ?? this.buyerUnreadCount,
      sellerUnreadCount: sellerUnreadCount ?? this.sellerUnreadCount,
    );
  }

  /// Remet à zéro uniquement le compteur de [userId], jamais celui de
  /// l'autre participant.
  Chat clearUnreadFor(String userId) {
    if (userId == buyerId) return copyWith(buyerUnreadCount: 0);
    if (userId == sellerId) return copyWith(sellerUnreadCount: 0);
    return this;
  }
}
