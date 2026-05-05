import 'dart:ui';

/// 印（Stamp）：笔刷的最小渲染单元
/// 由笔刷引擎根据输入点和预设参数生成
class Stamp {
  /// 印的中心位置（画布坐标）
  final Offset position;

  /// 当前印的尺寸（像素直径）
  final double size;

  /// 不透明度 (0.0 - 1.0)
  final double opacity;

  /// 旋转角度（弧度）
  final double rotation;

  /// 圆度 (0.0 - 1.0)，1.0 为圆形，0.0 为线形
  final double roundness;

  /// 边缘硬度 (0.0 - 1.0)，1.0 为硬边，0.0 为完全柔化
  final double hardness;

  /// 颜色
  final Color color;

  /// 混合模式
  final BlendMode blendMode;

  const Stamp({
    required this.position,
    required this.size,
    this.opacity = 1.0,
    this.rotation = 0.0,
    this.roundness = 1.0,
    this.hardness = 1.0,
    this.color = const Color(0xFF000000),
    this.blendMode = BlendMode.srcOver,
  });

  Stamp copyWith({
    Offset? position,
    double? size,
    double? opacity,
    double? rotation,
    double? roundness,
    double? hardness,
    Color? color,
    BlendMode? blendMode,
  }) => Stamp(
    position: position ?? this.position,
    size: size ?? this.size,
    opacity: opacity ?? this.opacity,
    rotation: rotation ?? this.rotation,
    roundness: roundness ?? this.roundness,
    hardness: hardness ?? this.hardness,
    color: color ?? this.color,
    blendMode: blendMode ?? this.blendMode,
  );
}
