import 'dart:ui';

import 'response_curve.dart';
import 'jitter_settings.dart';

/// 笔刷引擎类型枚举
enum BrushEngineType {
  /// 圆形引擎：基础圆点，支持硬度渐变
  round,

  /// 铅笔引擎：模拟铅笔纹理和边缘噪声
  pencil,

  /// 喷枪引擎：连续喷涂，粒子散布
  airbrush,

  /// 马克笔引擎：半透明叠加，扁平笔尖
  marker,

  /// 墨水引擎：模拟毛笔/钢笔，压感敏感
  ink,
}

/// 动态参数映射源（传感器类型）
enum DynamicSource {
  /// 压力 (0.0 - 1.0)
  pressure,

  /// 速度（由位移和时间计算）
  velocity,

  /// 倾斜角度
  tilt,

  /// 旋转角度
  rotation,

  /// 随机值
  random,
}

/// 动态参数映射：将传感器输入映射到笔刷属性
class DynamicMapping {
  /// 映射源
  final DynamicSource source;

  /// 响应曲线
  final ResponseCurve curve;

  /// 是否启用
  final bool enabled;

  const DynamicMapping({
    required this.source,
    required this.curve,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => {
    'source': source.index,
    'curve': curve.toMap(),
    'enabled': enabled,
  };

  factory DynamicMapping.fromMap(Map<String, dynamic> map) => DynamicMapping(
    source: DynamicSource.values[(map['source'] as num).toInt()],
    curve: ResponseCurve.fromMap(map['curve'] as Map<String, dynamic>),
    enabled: map['enabled'] as bool? ?? true,
  );

  DynamicMapping copyWith({
    DynamicSource? source,
    ResponseCurve? curve,
    bool? enabled,
  }) => DynamicMapping(
    source: source ?? this.source,
    curve: curve ?? this.curve,
    enabled: enabled ?? this.enabled,
  );
}

/// 笔刷预设：完整的笔刷配置
class BrushPreset {
  /// 预设唯一 ID
  final String id;

  /// 预设名称
  final String name;

  /// 引擎类型
  final BrushEngineType engineType;

  /// 基础尺寸（像素）
  final double baseSize;

  /// 最小尺寸比例 (0.0 - 1.0)，压感最小时的尺寸比例
  final double minSizeRatio;

  /// 基础不透明度 (0.0 - 1.0)
  final double baseOpacity;

  /// 最小不透明度比例 (0.0 - 1.0)
  final double minOpacityRatio;

  /// 基础硬度 (0.0 - 1.0)
  final double hardness;

  /// 基础圆度 (0.0 - 1.0)
  final double roundness;

  /// 基础旋转角度（弧度）
  final double angle;

  /// 间距（相对于笔刷尺寸的比例，0.01 - 5.0）
  /// 值越小越密，0.25 表示每隔 25% 笔刷直径放一个印
  final double spacing;

  /// 流量 (0.0 - 1.0)，控制每个印的颜料量
  final double flow;

  /// 颜色（可被用户覆盖）
  final Color color;

  // === 动态参数映射 ===

  /// 尺寸映射（默认：压力 -> 尺寸）
  final DynamicMapping sizeDynamic;

  /// 不透明度映射（默认：压力 -> 不透明度）
  final DynamicMapping opacityDynamic;

  /// 硬度映射
  final DynamicMapping? hardnessDynamic;

  /// 圆度映射（默认：倾斜 -> 圆度）
  final DynamicMapping? roundnessDynamic;

  /// 角度映射（默认：旋转 -> 角度）
  final DynamicMapping? angleDynamic;

  // === 抖动 ===

  /// 抖动设置
  final JitterSettings jitter;

  // === 稳定性 ===

  /// 输入稳定度 (0.0 - 1.0)
  final double stabilization;

  /// 稳定度系数 (0.0 - 1.0)
  final double stabilizationFactor;

  /// 平滑曲线开关
  final bool smoothEnabled;

  /// 压感开关
  final bool pressureEnabled;

  /// 是否为内置预设（不可删除）
  final bool isBuiltin;

  const BrushPreset({
    required this.id,
    required this.name,
    this.engineType = BrushEngineType.round,
    this.baseSize = 10.0,
    this.minSizeRatio = 0.1,
    this.baseOpacity = 1.0,
    this.minOpacityRatio = 0.0,
    this.hardness = 1.0,
    this.roundness = 1.0,
    this.angle = 0.0,
    this.spacing = 0.15,
    this.flow = 1.0,
    this.color = const Color(0xFF000000),
    this.sizeDynamic = const DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
    ),
    this.opacityDynamic = const DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.constant,
      enabled: false,
    ),
    this.hardnessDynamic,
    this.roundnessDynamic,
    this.angleDynamic,
    this.jitter = JitterSettings.none,
    this.stabilization = 0.3,
    this.stabilizationFactor = 0.7,
    this.smoothEnabled = true,
    this.pressureEnabled = true,
    this.isBuiltin = false,
  });

  BrushPreset copyWith({
    String? id,
    String? name,
    BrushEngineType? engineType,
    double? baseSize,
    double? minSizeRatio,
    double? baseOpacity,
    double? minOpacityRatio,
    double? hardness,
    double? roundness,
    double? angle,
    double? spacing,
    double? flow,
    Color? color,
    DynamicMapping? sizeDynamic,
    DynamicMapping? opacityDynamic,
    DynamicMapping? hardnessDynamic,
    bool clearHardnessDynamic = false,
    DynamicMapping? roundnessDynamic,
    bool clearRoundnessDynamic = false,
    DynamicMapping? angleDynamic,
    bool clearAngleDynamic = false,
    JitterSettings? jitter,
    double? stabilization,
    double? stabilizationFactor,
    bool? smoothEnabled,
    bool? pressureEnabled,
    bool? isBuiltin,
  }) => BrushPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    engineType: engineType ?? this.engineType,
    baseSize: baseSize ?? this.baseSize,
    minSizeRatio: minSizeRatio ?? this.minSizeRatio,
    baseOpacity: baseOpacity ?? this.baseOpacity,
    minOpacityRatio: minOpacityRatio ?? this.minOpacityRatio,
    hardness: hardness ?? this.hardness,
    roundness: roundness ?? this.roundness,
    angle: angle ?? this.angle,
    spacing: spacing ?? this.spacing,
    flow: flow ?? this.flow,
    color: color ?? this.color,
    sizeDynamic: sizeDynamic ?? this.sizeDynamic,
    opacityDynamic: opacityDynamic ?? this.opacityDynamic,
    hardnessDynamic: clearHardnessDynamic
        ? null
        : (hardnessDynamic ?? this.hardnessDynamic),
    roundnessDynamic: clearRoundnessDynamic
        ? null
        : (roundnessDynamic ?? this.roundnessDynamic),
    angleDynamic: clearAngleDynamic
        ? null
        : (angleDynamic ?? this.angleDynamic),
    jitter: jitter ?? this.jitter,
    stabilization: stabilization ?? this.stabilization,
    stabilizationFactor: stabilizationFactor ?? this.stabilizationFactor,
    smoothEnabled: smoothEnabled ?? this.smoothEnabled,
    pressureEnabled: pressureEnabled ?? this.pressureEnabled,
    isBuiltin: isBuiltin ?? this.isBuiltin,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'engineType': engineType.index,
    'baseSize': baseSize,
    'minSizeRatio': minSizeRatio,
    'baseOpacity': baseOpacity,
    'minOpacityRatio': minOpacityRatio,
    'hardness': hardness,
    'roundness': roundness,
    'angle': angle,
    'spacing': spacing,
    'flow': flow,
    'color': color.value,
    'sizeDynamic': sizeDynamic.toMap(),
    'opacityDynamic': opacityDynamic.toMap(),
    if (hardnessDynamic != null) 'hardnessDynamic': hardnessDynamic!.toMap(),
    if (roundnessDynamic != null) 'roundnessDynamic': roundnessDynamic!.toMap(),
    if (angleDynamic != null) 'angleDynamic': angleDynamic!.toMap(),
    'jitter': jitter.toMap(),
    'stabilization': stabilization,
    'stabilizationFactor': stabilizationFactor,
    'smoothEnabled': smoothEnabled,
    'pressureEnabled': pressureEnabled,
    'isBuiltin': isBuiltin,
  };

  factory BrushPreset.fromMap(Map<String, dynamic> map) => BrushPreset(
    id: map['id'] as String,
    name: map['name'] as String,
    engineType: BrushEngineType.values[(map['engineType'] as num).toInt()],
    baseSize: (map['baseSize'] as num).toDouble(),
    minSizeRatio: (map['minSizeRatio'] as num?)?.toDouble() ?? 0.1,
    baseOpacity: (map['baseOpacity'] as num).toDouble(),
    minOpacityRatio: (map['minOpacityRatio'] as num?)?.toDouble() ?? 0.0,
    hardness: (map['hardness'] as num?)?.toDouble() ?? 1.0,
    roundness: (map['roundness'] as num?)?.toDouble() ?? 1.0,
    angle: (map['angle'] as num?)?.toDouble() ?? 0.0,
    spacing: (map['spacing'] as num?)?.toDouble() ?? 0.15,
    flow: (map['flow'] as num?)?.toDouble() ?? 1.0,
    color: Color((map['color'] as num).toInt()),
    sizeDynamic: DynamicMapping.fromMap(
      map['sizeDynamic'] as Map<String, dynamic>,
    ),
    opacityDynamic: DynamicMapping.fromMap(
      map['opacityDynamic'] as Map<String, dynamic>,
    ),
    hardnessDynamic: map['hardnessDynamic'] != null
        ? DynamicMapping.fromMap(map['hardnessDynamic'] as Map<String, dynamic>)
        : null,
    roundnessDynamic: map['roundnessDynamic'] != null
        ? DynamicMapping.fromMap(
            map['roundnessDynamic'] as Map<String, dynamic>,
          )
        : null,
    angleDynamic: map['angleDynamic'] != null
        ? DynamicMapping.fromMap(map['angleDynamic'] as Map<String, dynamic>)
        : null,
    jitter: map['jitter'] != null
        ? JitterSettings.fromMap(map['jitter'] as Map<String, dynamic>)
        : JitterSettings.none,
    stabilization: (map['stabilization'] as num?)?.toDouble() ?? 0.3,
    stabilizationFactor:
        (map['stabilizationFactor'] as num?)?.toDouble() ?? 0.7,
    smoothEnabled: map['smoothEnabled'] as bool? ?? true,
    pressureEnabled: map['pressureEnabled'] as bool? ?? true,
    isBuiltin: map['isBuiltin'] as bool? ?? false,
  );
}
