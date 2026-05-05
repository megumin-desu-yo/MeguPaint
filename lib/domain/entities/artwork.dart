import 'layer.dart';

/// 画作实体
class Artwork {
  /// 画作ID (UUID)
  final String id;
  
  /// 画作名称
  final String name;
  
  /// 随机种子 (用于图层签名验证)
  final int seed;
  
  /// 宽度
  final int width;
  
  /// 高度
  final int height;
  
  /// 创建者用户名
  final String creatorId;
  
  /// 创建时间
  final DateTime createdAt;
  
  /// 最后修改时间
  final DateTime updatedAt;
  
  /// 图层列表
  final List<Layer> layers;

  const Artwork({
    required this.id,
    required this.name,
    required this.seed,
    required this.width,
    required this.height,
    required this.creatorId,
    required this.createdAt,
    required this.updatedAt,
    this.layers = const [],
  });

  /// 是否已初始化
  bool get isInitialized => id.isNotEmpty;

  /// 图层数量
  int get layerCount => layers.length;

  /// 复制并修改
  Artwork copyWith({
    String? id,
    String? name,
    int? seed,
    int? width,
    int? height,
    String? creatorId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Layer>? layers,
  }) {
    return Artwork(
      id: id ?? this.id,
      name: name ?? this.name,
      seed: seed ?? this.seed,
      width: width ?? this.width,
      height: height ?? this.height,
      creatorId: creatorId ?? this.creatorId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      layers: layers ?? this.layers,
    );
  }

  /// 从 Map 创建
  factory Artwork.fromMap(Map<String, dynamic> map) {
    return Artwork(
      id: map['id'] as String,
      name: map['name'] as String,
      seed: map['seed'] as int,
      width: map['width'] as int,
      height: map['height'] as int,
      creatorId: map['creatorId'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      layers: (map['layers'] as List<dynamic>?)
              ?.map((e) => Layer.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'seed': seed,
      'width': width,
      'height': height,
      'creatorId': creatorId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'layers': layers.map((e) => e.toMap()).toList(),
    };
  }
}
