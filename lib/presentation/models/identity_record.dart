/// 身份认证记录
class IdentityRecord {
  /// 用户名
  final String username;
  
  /// 指纹（十六进制字符串）
  final String fingerprintHex;
  
  /// 备注（未填写时默认为用户名）
  final String remark;
  
  /// 创建时间
  final DateTime createdAt;
  
  /// 最后更新时间
  final DateTime updatedAt;

  IdentityRecord({
    required this.username,
    required this.fingerprintHex,
    String? remark,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : remark = remark?.isNotEmpty == true ? remark! : username,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 复制并更新
  IdentityRecord copyWith({
    String? username,
    String? fingerprintHex,
    String? remark,
    DateTime? updatedAt,
  }) {
    return IdentityRecord(
      username: username ?? this.username,
      fingerprintHex: fingerprintHex ?? this.fingerprintHex,
      remark: remark ?? this.remark,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'fingerprintHex': fingerprintHex,
      'remark': remark,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 JSON 解析
  factory IdentityRecord.fromJson(Map<String, dynamic> json) {
    return IdentityRecord(
      username: json['username'] as String,
      fingerprintHex: json['fingerprintHex'] as String,
      remark: json['remark'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  /// 唯一标识（使用指纹作为唯一标识）
  String get key => fingerprintHex;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IdentityRecord && other.fingerprintHex == fingerprintHex;
  }

  @override
  int get hashCode => fingerprintHex.hashCode;
}
