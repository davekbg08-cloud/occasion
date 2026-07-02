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
    this.unreadCount = 0,
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
  final int unreadCount;

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
      unreadCount: map['unreadCount'] as int? ?? 0,
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
    'unreadCount': unreadCount,
  };

  Chat copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
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
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
