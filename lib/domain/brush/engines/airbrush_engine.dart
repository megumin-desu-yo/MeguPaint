import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../../presentation/providers/drawing_provider.dart';
import '../brush_engine.dart';
import '../brush_preset.dart';
import '../stamp.dart';

/// 喷枪引擎：连续喷涂，粒子散布
/// 特点：大量低不透明度小粒子散布在路径周围，密度随压力变化
class AirbrushEngine extends BrushEngine {
  /// 确定性随机数生成器，每次 generateStamps 重置种子
  /// 保证相同输入点产生相同粒子分布，避免实时绘制闪烁
  math.Random _rng = math.Random(0);

  @override
  String get id => 'airbrush';

  @override
  String get name => '喷枪';

  @override
  BrushEngineType get engineType => BrushEngineType.airbrush;

  @override
  List<Stamp> generateStamps(List<DrawPoint> points, BrushPreset preset) {
    if (points.isEmpty) return [];

    // 用首点位置哈希作为种子，保证相同笔画产生相同粒子
    _rng = math.Random(points.first.position.hashCode);

    final stamps = <Stamp>[];
    final spacingPx = (preset.baseSize * preset.spacing).clamp(
      1.0,
      double.infinity,
    );

    if (points.length == 1) {
      _addSprayParticles(stamps, points.first, null, preset);
      return stamps;
    }

    double accumDist = 0.0;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final segDist = (p1.position - p0.position).distance;

      if (segDist < 0.001) continue;

      if (i == 0 && accumDist == 0.0) {
        _addSprayParticles(stamps, p0, null, preset);
      }

      final interpolated = interpolatePositions(
        p0.position,
        p1.position,
        spacingPx,
        spacingPx - accumDist,
      );

      for (final interp in interpolated) {
        final t = interp.t;
        final interpPoint = DrawPoint(
          position: interp.position,
          pressure: p0.pressure + (p1.pressure - p0.pressure) * t,
          tilt: p0.tilt + (p1.tilt - p0.tilt) * t,
        );
        _addSprayParticles(
          stamps,
          interpPoint,
          i > 0 ? points[i - 1] : null,
          preset,
        );
      }

      accumDist = (accumDist + segDist) % spacingPx;
    }

    return stamps;
  }

  /// 在指定点周围生成喷涂粒子
  void _addSprayParticles(
    List<Stamp> stamps,
    DrawPoint point,
    DrawPoint? prevPoint,
    BrushPreset preset,
  ) {
    // 喷枪尺寸（喷涂范围）
    final sprayRadius = applyDynamicMapping(
      preset.baseSize,
      preset.minSizeRatio,
      preset.sizeDynamic,
      point,
      prevPoint,
    );

    // 粒子数量受压力影响（压力越大粒子越密）
    final baseDensity = (sprayRadius * 0.5).clamp(3.0, 30.0);
    final density = (baseDensity * point.pressure).round().clamp(1, 30);

    // 基础不透明度
    double baseOpacity = applyDynamicMapping(
      preset.baseOpacity,
      preset.minOpacityRatio,
      preset.opacityDynamic,
      point,
      prevPoint,
    );

    // 每个粒子的不透明度
    final particleOpacity = (baseOpacity * preset.flow * 0.6 / density).clamp(
      0.03,
      0.5,
    );

    // 粒子尺寸
    final particleSize = (sprayRadius * 0.18).clamp(1.0, 10.0);

    for (int j = 0; j < density; j++) {
      // 高斯分布散布（中心密、边缘疏）
      final angle = _rng.nextDouble() * 2 * math.pi;
      final r = _gaussianRandom() * sprayRadius * 0.5;

      final particlePos = Offset(
        point.position.dx + math.cos(angle) * r,
        point.position.dy + math.sin(angle) * r,
      );

      // 距离越远越透明
      final distFactor = 1.0 - (r / (sprayRadius * 0.5)).clamp(0.0, 1.0);
      final finalOpacity = (particleOpacity * distFactor).clamp(0.0, 1.0);

      final color = applyColorJitter(preset.color, preset.jitter);

      stamps.add(
        Stamp(
          position: particlePos,
          size: particleSize * (0.5 + _rng.nextDouble()),
          opacity: finalOpacity,
          rotation: 0.0,
          roundness: 1.0,
          hardness: 0.15, // 柔和边缘，但保持可见度
          color: color,
        ),
      );
    }
  }

  /// 简易高斯随机（Box-Muller 变换，取绝对值限制为正）
  double _gaussianRandom() {
    final u1 = _rng.nextDouble();
    final u2 = _rng.nextDouble();
    final z =
        math.sqrt(-2.0 * math.log(u1.clamp(0.0001, 1.0))) *
        math.cos(2.0 * math.pi * u2);
    return z.abs().clamp(0.0, 3.0) / 3.0; // 归一化到 0-1
  }
}
