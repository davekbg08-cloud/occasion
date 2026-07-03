enum UserRole { seller, buyer }

enum SellerIdentityStatus {
  unverified,
  phoneVerified,
  identitySubmitted,
  verified,
  rejected,
}

extension SellerIdentityStatusX on SellerIdentityStatus {
  String get firestoreValue {
    switch (this) {
      case SellerIdentityStatus.phoneVerified:
        return 'phone_verified';
      case SellerIdentityStatus.identitySubmitted:
        return 'identity_submitted';
      case SellerIdentityStatus.verified:
        return 'verified';
      case SellerIdentityStatus.rejected:
        return 'rejected';
      case SellerIdentityStatus.unverified:
        return 'unverified';
    }
  }

  static SellerIdentityStatus fromValue(String? value) {
    switch (value) {
      case 'phone_verified':
        return SellerIdentityStatus.phoneVerified;
      case 'identity_submitted':
        return SellerIdentityStatus.identitySubmitted;
      case 'verified':
        return SellerIdentityStatus.verified;
      case 'rejected':
        return SellerIdentityStatus.rejected;
      default:
        return SellerIdentityStatus.unverified;
    }
  }
}

class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.profileImageUrl,
    required this.role,
    required this.createdAt,
    this.identityStatus = SellerIdentityStatus.unverified,
    this.phoneVerified = false,
    this.selfieUrl,
    this.idDocumentUrl,
  });

  final String id;
  final String name;
  final String phone;
  final String? profileImageUrl;
  final UserRole role;
  final DateTime createdAt;
  final SellerIdentityStatus identityStatus;
  final bool phoneVerified;
  final String? selfieUrl;
  final String? idDocumentUrl;

  bool get isSeller => role == UserRole.seller;
  bool get isBuyer => role == UserRole.buyer;
  bool get isVerifiedSeller =>
      isSeller && identityStatus == SellerIdentityStatus.verified;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final identityStatus = SellerIdentityStatusX.fromValue(
      map['identityStatus'] as String? ?? map['sellerStatus'] as String?,
    );
    final inferredPhoneVerified =
        identityStatus == SellerIdentityStatus.phoneVerified ||
        identityStatus == SellerIdentityStatus.identitySubmitted ||
        identityStatus == SellerIdentityStatus.verified;
    final phoneVerified =
        map['phoneVerified'] as bool? ?? inferredPhoneVerified;

    return UserModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      profileImageUrl: map['profileImageUrl'] as String?,
      role: (map['role'] as String?) == 'seller'
          ? UserRole.seller
          : UserRole.buyer,
      createdAt: _toDateTime(map['createdAt']),
      identityStatus: identityStatus,
      phoneVerified: phoneVerified,
      selfieUrl: map['selfieUrl'] as String?,
      idDocumentUrl: map['idDocumentUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'profileImageUrl': profileImageUrl,
    'role': role.name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'identityStatus': identityStatus.firestoreValue,
    'sellerStatus': identityStatus.firestoreValue,
    'phoneVerified': phoneVerified,
    'selfieUrl': selfieUrl,
    'idDocumentUrl': idDocumentUrl,
  };

  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? profileImageUrl,
    UserRole? role,
    DateTime? createdAt,
    SellerIdentityStatus? identityStatus,
    bool? phoneVerified,
    String? selfieUrl,
    String? idDocumentUrl,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      identityStatus: identityStatus ?? this.identityStatus,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      selfieUrl: selfieUrl ?? this.selfieUrl,
      idDocumentUrl: idDocumentUrl ?? this.idDocumentUrl,
    );
  }

  static DateTime _toDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    try {
      final dynamic dynamicValue = value;
      final converted = dynamicValue?.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Keep legacy users readable when Firestore stores malformed dates.
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
