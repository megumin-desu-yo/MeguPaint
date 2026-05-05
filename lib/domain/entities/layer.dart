/// 图层权限状态
enum LayerPermissionStatus {
  /// 无权限 (任何人可编辑)
  public,

  /// 自己拥有 (仅自己可编辑)
  owned,

  /// 他人拥有 (仅可查看)
  others,
}

/// 图层实体 (基础单位)
class Layer {
  /// 图层ID (格式: {artworkId}-{layerIndex})
  final String id;

  /// 图层编号
  final int index;

  /// 图层名称
  final String name;

  /// 所有者签名 (HMAC-SHA256(privateKey, layerId + seed))
  /// null 表示无权限图层
  final String? ownerSignature;

  /// 所有者用户名
  /// null 表示无权限图层
  final String? ownerId;

  /// 所有者公开标识 (由私钥派生，用于指纹展示)
  /// null 表示无权限图层
  final String? ownerPublicId;

  /// 是否可见
  final bool isVisible;

  /// 是否锁定 (独立于权限)
  final bool isLocked;

  /// 不透明度 (0.0 - 1.0)
  final double opacity;

  /// 创建时间
  final DateTime createdAt;

  const Layer({
    required this.id,
    required this.index,
    required this.name,
    this.ownerSignature,
    this.ownerId,
    this.ownerPublicId,
    this.isVisible = true,
    this.isLocked = false,
    this.opacity = 1.0,
    required this.createdAt,
  });

  /// 是否有权限 (有签名)
  bool get hasPermission => ownerSignature != null;

  /// 获取权限状态
  LayerPermissionStatus getPermissionStatus(String currentUserId) {
    if (ownerSignature == null) {
      return LayerPermissionStatus.public;
    }
    if (ownerId == currentUserId) {
      return LayerPermissionStatus.owned;
    }
    return LayerPermissionStatus.others;
  }

  /// 是否可以编辑（简单检查，仅比对用户名，用于 UI 显示）
  bool canEdit(String currentUserId) {
    final status = getPermissionStatus(currentUserId);
    return status == LayerPermissionStatus.public ||
        status == LayerPermissionStatus.owned;
  }

  /// 是否可以编辑（带签名验证，用于实际操作）
  /// [currentUserId] 当前用户名
  /// [privateKey] 当前用户私钥
  /// [seed] 画作种子
  /// [verifySignature] 签名验证函数 (privateKey, layerId, seed, signature) -> bool
  bool canEditWithVerification(
    String currentUserId,
    String privateKey,
    int seed,
    bool Function(String privateKey, String layerId, int seed, String signature)
    verifySignature,
  ) {
    final status = getPermissionStatus(currentUserId);
    // public 图层无需验证
    if (status == LayerPermissionStatus.public) return true;
    // owned 图层需要验证签名
    if (status == LayerPermissionStatus.owned) {
      if (ownerSignature == null) return false;
      return verifySignature(privateKey, id, seed, ownerSignature!);
    }
    // others 图层不可编辑
    return false;
  }

  /// 验证所有权签名
  /// [privateKey] 私钥
  /// [seed] 画作种子
  /// [verifySignature] 签名验证函数
  bool verifyOwnership(
    String privateKey,
    int seed,
    bool Function(String privateKey, String layerId, int seed, String signature)
    verifySignature,
  ) {
    if (ownerSignature == null) return false;
    return verifySignature(privateKey, id, seed, ownerSignature!);
  }

  /// 是否可以删除
  bool canDelete(String currentUserId) {
    return canEdit(currentUserId);
  }

  /// 是否可以删除（带签名验证）
  bool canDeleteWithVerification(
    String currentUserId,
    String privateKey,
    int seed,
    bool Function(String privateKey, String layerId, int seed, String signature)
    verifySignature,
  ) {
    return canEditWithVerification(
      currentUserId,
      privateKey,
      seed,
      verifySignature,
    );
  }

  /// 是否可以修改权限
  bool canChangePermission(String currentUserId) {
    final status = getPermissionStatus(currentUserId);
    // 自己的图层可以降为无权限，无权限图层可以添加签名
    return status == LayerPermissionStatus.owned ||
        status == LayerPermissionStatus.public;
  }

  /// 是否可以修改权限（带签名验证）
  bool canChangePermissionWithVerification(
    String currentUserId,
    String privateKey,
    int seed,
    bool Function(String privateKey, String layerId, int seed, String signature)
    verifySignature,
  ) {
    final status = getPermissionStatus(currentUserId);
    if (status == LayerPermissionStatus.public) return true;
    if (status == LayerPermissionStatus.owned) {
      if (ownerSignature == null) return false;
      return verifySignature(privateKey, id, seed, ownerSignature!);
    }
    return false;
  }

  /// 复制并修改
  Layer copyWith({
    String? id,
    int? index,
    String? name,
    String? ownerSignature,
    String? ownerId,
    String? ownerPublicId,
    bool? isVisible,
    bool? isLocked,
    double? opacity,
    DateTime? createdAt,
    bool clearOwner = false,
  }) {
    return Layer(
      id: id ?? this.id,
      index: index ?? this.index,
      name: name ?? this.name,
      ownerSignature: clearOwner
          ? null
          : (ownerSignature ?? this.ownerSignature),
      ownerId: clearOwner ? null : (ownerId ?? this.ownerId),
      ownerPublicId: clearOwner ? null : (ownerPublicId ?? this.ownerPublicId),
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      opacity: opacity ?? this.opacity,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 从 Map 创建
  factory Layer.fromMap(Map<String, dynamic> map) {
    return Layer(
      id: map['id'] as String,
      index: map['index'] as int,
      name: map['name'] as String,
      ownerSignature: map['ownerSignature'] as String?,
      ownerId: map['ownerId'] as String?,
      ownerPublicId: map['ownerPublicId'] as String?,
      isVisible: map['isVisible'] as bool? ?? true,
      isLocked: map['isLocked'] as bool? ?? false,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'index': index,
      'name': name,
      'ownerSignature': ownerSignature,
      'ownerId': ownerId,
      'ownerPublicId': ownerPublicId,
      'isVisible': isVisible,
      'isLocked': isLocked,
      'opacity': opacity,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
