enum UserRole { seller, buyer }

class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.profileImageUrl,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String phone;
  final String? profileImageUrl;
  final UserRole role;
  final DateTime createdAt;

  bool get isSeller => role == UserRole.seller;
  bool get isBuyer => role == UserRole.buyer;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      profileImageUrl: map['profileImageUrl'] as String?,
      role: (map['role'] as String?) == 'seller'
          ? UserRole.seller
          : UserRole.buyer,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] as int? ?? 0,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'profileImageUrl': profileImageUrl,
    'role': role.name,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? profileImageUrl,
    UserRole? role,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
