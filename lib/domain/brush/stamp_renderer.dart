import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'stamp.dart';

/// 印渲染器：将 Stamp 列表渲染到 Canvas
/// 支持硬度渐变、椭圆笔尖、颜色混合
class StampRenderer {
  /// 将印列表渲染到画布
  /// [canvas] 目标画布
  /// [stamps] 印列表
  /// [isEraser] 是否为橡皮擦模式
  static void renderStamps(
    Canvas canvas,
    List<Stamp> stamps, {
    bool isEraser = false,
  }) {
    if (stamps.isEmpty) return;

    for (final stamp in stamps) {
      _renderSingleStamp(canvas, stamp, isEraser: isEraser);
    }
  }

  /// 渲染单个印
  static void _renderSingleStamp(
    Canvas canvas,
    Stamp stamp, {
    bool isEraser = false,
  }) {
    if (stamp.size <= 0 || stamp.opacity <= 0) return;

    final radius = stamp.size / 2;

    // 保存画布状态
    canvas.save();

    // 移动到印的中心
    canvas.translate(stamp.position.dx, stamp.position.dy);

    // 应用旋转
    if (stamp.rotation != 0) {
      canvas.rotate(stamp.rotation);
    }

    // 应用圆度（椭圆变形）
    if (stamp.roundness < 1.0) {
      canvas.scale(1.0, stamp.roundness.clamp(0.1, 1.0));
    }

    if (isEraser) {
      // 橡皮擦模式：使用 BlendMode.clear
      final paint = Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, radius, paint);
    } else if (stamp.hardness >= 0.95) {
      // 硬边笔刷：纯色圆
      final paint = Paint()
        ..color = stamp.color.withOpacity(stamp.opacity)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawCircle(Offset.zero, radius, paint);
    } else {
      // 柔边笔刷：径向渐变模拟硬度
      _renderSoftStamp(canvas, stamp, radius);
    }

    // 恢复画布状态
    canvas.restore();
  }

  /// 渲染柔边印（径向渐变）
  static void _renderSoftStamp(Canvas canvas, Stamp stamp, double radius) {
    // hardness 控制不透明区域的比例
    // hardness=1: 全部不透明（硬边）
    // hardness=0: 中心到边缘完全渐变（最柔）
    final hardStop = stamp.hardness.clamp(0.0, 0.99);

    final gradient = ui.Gradient.radial(
      Offset.zero,
      radius,
      [
        stamp.color.withOpacity(stamp.opacity),
        stamp.color.withOpacity(stamp.opacity),
        stamp.color.withOpacity(0.0),
      ],
      [0.0, hardStop, 1.0],
    );

    final paint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawCircle(Offset.zero, radius, paint);
  }

  /// 快速渲染：对大量小印使用 drawPoints 优化
  /// 仅适用于硬边、圆形、无旋转的印
  static void renderStampsFast(
    Canvas canvas,
    List<Stamp> stamps, {
    bool isEraser = false,
  }) {
    if (stamps.isEmpty) return;

    // 检查是否可以使用快速路径
    final canUseFastPath = stamps.every(
      (s) => s.hardness >= 0.95 && s.roundness >= 0.95 && s.rotation == 0,
    );

    if (!canUseFastPath) {
      renderStamps(canvas, stamps, isEraser: isEraser);
      return;
    }

    // 按尺寸和颜色分组批量绘制
    final groups = <_StampGroup, List<Offset>>{};

    for (final stamp in stamps) {
      final key = _StampGroup(
        size: stamp.size,
        color: stamp.color,
        opacity: stamp.opacity,
      );
      groups.putIfAbsent(key, () => []).add(stamp.position);
    }

    for (final entry in groups.entries) {
      final group = entry.key;
      final positions = entry.value;

      final paint = Paint()
        ..strokeWidth = group.size
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      if (isEraser) {
        paint.blendMode = BlendMode.clear;
      } else {
        paint.color = group.color.withOpacity(group.opacity);
      }

      // 使用 drawPoints 批量绘制
      canvas.drawPoints(ui.PointMode.points, positions, paint);
    }
  }
}

/// 用于分组批量绘制的键
class _StampGroup {
  final double size;
  final Color color;
  final double opacity;

  _StampGroup({required this.size, required this.color, required this.opacity});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _StampGroup &&
          size == other.size &&
          color == other.color &&
          opacity == other.opacity;

  @override
  int get hashCode => Object.hash(size, color, opacity);
}
