/// 用户凭证实体
class UserCredential {
  /// 用户名
  final String username;
  
  /// 密码哈希 (PBKDF2-SHA256)
  final String passwordHash;
  
  /// 私钥 (由用户名+密码派生，用于签名)
  final String privateKey;
  
  /// 创建时间
  final DateTime createdAt;

  const UserCredential({
    required this.username,
    required this.passwordHash,
    required this.privateKey,
    required this.createdAt,
  });

  /// 从 Map 创建
  factory UserCredential.fromMap(Map<String, dynamic> map) {
    return UserCredential(
      username: map['username'] as String,
      passwordHash: map['passwordHash'] as String,
      privateKey: map['privateKey'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'passwordHash': passwordHash,
      'privateKey': privateKey,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 复制并修改
  UserCredential copyWith({
    String? username,
    String? passwordHash,
    String? privateKey,
    DateTime? createdAt,
  }) {
    return UserCredential(
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      privateKey: privateKey ?? this.privateKey,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
