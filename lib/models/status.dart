enum StatusType { image, video }

class Status {
  const Status({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    this.sellerProfileImageUrl,
    required this.mediaUrl,
    required this.type,
    this.caption,
    this.productId,
    this.likesCount = 0,
    this.status = 'published',
    this.active = true,
    required this.createdAt,
  });

  final String id;
  final String sellerId;
  final String sellerName;
  final String? sellerProfileImageUrl;
  final String mediaUrl;
  final StatusType type;
  final String? caption;
  final String? productId;
  final int likesCount;
  final String status;
  final bool active;
  final DateTime createdAt;

  factory Status.fromMap(Map<String, dynamic> map) {
    return Status(
      id: map['id'] as String? ?? '',
      sellerId: map['sellerId'] as String? ?? '',
      sellerName: map['sellerName'] as String? ?? '',
      sellerProfileImageUrl: map['sellerProfileImageUrl'] as String?,
      mediaUrl: map['mediaUrl'] as String? ?? '',
      type: (map['type'] as String?) == 'video'
          ? StatusType.video
          : StatusType.image,
      caption: map['caption'] as String?,
      productId: map['productId'] as String?,
      likesCount: map['likesCount'] as int? ?? 0,
      status: map['status'] as String? ?? 'published',
      active: map['active'] as bool? ?? true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] as int? ?? 0,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'sellerProfileImageUrl': sellerProfileImageUrl,
    'mediaUrl': mediaUrl,
    'type': type.name,
    'caption': caption,
    'productId': productId,
    'likesCount': likesCount,
    'status': status,
    'active': active,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  Status copyWith({int? likesCount, String? status, bool? active}) {
    return Status(
      id: id,
      sellerId: sellerId,
      sellerName: sellerName,
      sellerProfileImageUrl: sellerProfileImageUrl,
      mediaUrl: mediaUrl,
      type: type,
      caption: caption,
      productId: productId,
      likesCount: likesCount ?? this.likesCount,
      status: status ?? this.status,
      active: active ?? this.active,
      createdAt: createdAt,
    );
  }
}
