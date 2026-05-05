import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../../presentation/providers/drawing_provider.dart';
import '../brush_engine.dart';
import '../brush_preset.dart';
import '../stamp.dart';

/// 确定性随机数生成器（基于位置）
class _DeterministicRandom {
  static double nextDouble(Offset position, int seed) {
    // 使用位置和种子生成确定性随机数
    final x = position.dx * 1000;
    final y = position.dy * 1000;
    final value = math.sin(x * 12.9898 + y * 78.233 + seed) * 43758.5453;
    return (value - value.floor());
  }
}

/// 铅笔引擎：模拟铅笔纹理和边缘噪声
/// 特点：低不透明度印叠加、边缘噪声、速度影响透明度
class PencilEngine extends BrushEngine {
  @override
  String get id => 'pencil';

  @override
  String get name => '铅笔';

  @override
  BrushEngineType get engineType => BrushEngineType.pencil;

  @override
  List<Stamp> generateStamps(List<DrawPoint> points, BrushPreset preset) {
    if (points.isEmpty) return [];

    final stamps = <Stamp>[];
    // 铅笔间距更密，模拟连续纹理
    final spacingPx = (preset.baseSize * preset.spacing * 0.5).clamp(
      0.3,
      double.infinity,
    );

    if (points.length == 1) {
      stamps.add(_createPencilStamp(points.first, null, preset, 0));
      return stamps;
    }

    double accumDist = 0.0;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final segDist = (p1.position - p0.position).distance;

      if (segDist < 0.001) continue;

      if (i == 0 && accumDist == 0.0) {
        stamps.add(_createPencilStamp(p0, null, preset, i));
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
          velocity: p0.velocity + (p1.velocity - p0.velocity) * t,
        );
        stamps.add(
          _createPencilStamp(
            interpPoint,
            i > 0 ? points[i - 1] : null,
            preset,
            i,
          ),
        );
      }

      accumDist = (accumDist + segDist) % spacingPx;
    }

    if (points.length > 1) {
      stamps.add(
        _createPencilStamp(
          points.last,
          points[points.length - 2],
          preset,
          points.length - 1,
        ),
      );
    }

    return stamps;
  }

  Stamp _createPencilStamp(
    DrawPoint point,
    DrawPoint? prevPoint,
    BrushPreset preset,
    int seed,
  ) {
    // 铅笔尺寸受压感影响但范围较小
    double size = applyDynamicMapping(
      preset.baseSize,
      preset.minSizeRatio,
      preset.sizeDynamic,
      point,
      prevPoint,
    );

    // 铅笔不透明度较低，模拟石墨颗粒
    double opacity = applyDynamicMapping(
      preset.baseOpacity,
      preset.minOpacityRatio,
      preset.opacityDynamic,
      point,
      prevPoint,
    );

    // 铅笔特有：速度越快越透明（模拟轻拂）
    if (prevPoint != null) {
      final vel = (point.position - prevPoint.position).distance;
      final velFactor = 1.0 - (vel / 100.0).clamp(0.0, 0.5);
      opacity *= velFactor;
    }

    // 铅笔纹理噪声：使用确定性随机数
    final noiseRandom = _DeterministicRandom.nextDouble(
      point.position,
      seed * 1,
    );
    final noiseAmount = 0.3 + noiseRandom * 0.4;
    opacity *= noiseAmount;

    // 铅笔边缘：硬度较低，模拟纤维纸质感
    final hardnessRandom = _DeterministicRandom.nextDouble(
      point.position,
      seed * 2,
    );
    final hardness = (preset.hardness * 0.6 + hardnessRandom * 0.2).clamp(
      0.0,
      1.0,
    );

    // 轻微尺寸抖动
    final sizeRandom = _DeterministicRandom.nextDouble(
      point.position,
      seed * 3,
    );
    size *= (0.9 + sizeRandom * 0.2);

    // 轻微散布（模拟纸面颗粒分布）
    final scatterRandom = _DeterministicRandom.nextDouble(
      point.position,
      seed * 4,
    );
    final scatterOffset = scatterRandom * size * 0.15;
    final angleRandom = _DeterministicRandom.nextDouble(
      point.position,
      seed * 5,
    );
    final scatterAngle = angleRandom * 2 * math.pi;
    final scatteredPos = Offset(
      point.position.dx + math.cos(scatterAngle) * scatterOffset,
      point.position.dy + math.sin(scatterAngle) * scatterOffset,
    );

    // 应用颜色抖动
    final color = applyColorJitter(preset.color, preset.jitter);

    // 轻微随机旋转
    final rotationRandom = _DeterministicRandom.nextDouble(
      point.position,
      seed * 6,
    );
    final rotation = rotationRandom * 0.3;

    return Stamp(
      position: scatteredPos,
      size: size.clamp(0.5, 500.0),
      opacity: (opacity * preset.flow).clamp(0.0, 1.0),
      rotation: rotation,
      roundness: preset.roundness,
      hardness: hardness,
      color: color,
    );
  }
}
