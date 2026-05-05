import '../../../presentation/providers/drawing_provider.dart';
import '../brush_engine.dart';
import '../brush_preset.dart';
import '../stamp.dart';

/// 圆形引擎：基础圆点笔刷，支持硬度渐变
/// 类似 Photoshop 的默认圆形笔刷
class RoundEngine extends BrushEngine {
  @override
  String get id => 'round';

  @override
  String get name => '圆形';

  @override
  BrushEngineType get engineType => BrushEngineType.round;

  @override
  List<Stamp> generateStamps(List<DrawPoint> points, BrushPreset preset) {
    if (points.isEmpty) return [];

    final stamps = <Stamp>[];
    final spacingPx = (preset.baseSize * preset.spacing).clamp(
      0.5,
      double.infinity,
    );

    // 单点：直接生成一个印
    if (points.length == 1) {
      stamps.add(_createStamp(points.first, null, preset));
      return stamps;
    }

    // 多点：沿路径按间距生成印
    double accumDist = 0.0;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final segDist = (p1.position - p0.position).distance;

      if (segDist < 0.001) continue;

      // 第一个点始终生成一个印
      if (i == 0 && accumDist == 0.0) {
        stamps.add(_createStamp(p0, null, preset));
        accumDist = 0.0;
      }

      // 沿线段间距放印
      final interpolated = interpolatePositions(
        p0.position,
        p1.position,
        spacingPx,
        spacingPx - accumDist, // 考虑上一段的剩余距离
      );

      for (final interp in interpolated) {
        // 插值压感和其他属性
        final t = interp.t;
        final interpPoint = DrawPoint(
          position: interp.position,
          pressure: p0.pressure + (p1.pressure - p0.pressure) * t,
          tilt: p0.tilt + (p1.tilt - p0.tilt) * t,
          rotation: p0.rotation + (p1.rotation - p0.rotation) * t,
          velocity: p0.velocity + (p1.velocity - p0.velocity) * t,
        );
        stamps.add(
          _createStamp(interpPoint, i > 0 ? points[i - 1] : null, preset),
        );
      }

      // 更新累积距离
      accumDist = (accumDist + segDist) % spacingPx;
    }

    // 最后一个点也生成一个印（确保末端覆盖）
    if (points.length > 1) {
      stamps.add(
        _createStamp(
          points.last,
          points.length > 1 ? points[points.length - 2] : null,
          preset,
        ),
      );
    }

    return stamps;
  }

  /// 根据输入点和预设创建单个 Stamp
  Stamp _createStamp(
    DrawPoint point,
    DrawPoint? prevPoint,
    BrushPreset preset,
  ) {
    // 计算动态尺寸
    double size = applyDynamicMapping(
      preset.baseSize,
      preset.minSizeRatio,
      preset.sizeDynamic,
      point,
      prevPoint,
    );

    // 计算动态不透明度
    double opacity = applyDynamicMapping(
      preset.baseOpacity,
      preset.minOpacityRatio,
      preset.opacityDynamic,
      point,
      prevPoint,
    );

    // 计算动态硬度
    double hardness = preset.hardness;
    if (preset.hardnessDynamic != null) {
      hardness = applyDynamicMapping(
        preset.hardness,
        0.0,
        preset.hardnessDynamic,
        point,
        prevPoint,
      );
    }

    // 计算动态圆度
    double roundness = preset.roundness;
    if (preset.roundnessDynamic != null) {
      roundness = applyDynamicMapping(
        preset.roundness,
        0.1,
        preset.roundnessDynamic,
        point,
        prevPoint,
      );
    }

    // 计算动态角度
    double angle = preset.angle;
    if (preset.angleDynamic != null) {
      angle =
          applyDynamicMapping(1.0, 0.0, preset.angleDynamic, point, prevPoint) *
          3.14159 *
          2;
    }

    // 应用抖动
    final jitter = preset.jitter;
    size = applyJitter(size, jitter.sizeJitter);
    opacity = (applyJitter(opacity, jitter.opacityJitter)).clamp(0.0, 1.0);
    if (jitter.angleJitter > 0) {
      angle += (_randomAngle() * jitter.angleJitter);
    }
    roundness = (applyJitter(
      roundness,
      jitter.roundnessJitter,
    )).clamp(0.0, 1.0);

    // 应用散布
    final position = applyScatter(point.position, jitter.scatter, size);

    // 应用流量
    opacity *= preset.flow;

    // 应用颜色抖动
    final color = applyColorJitter(preset.color, jitter);

    return Stamp(
      position: position,
      size: size.clamp(0.5, 500.0),
      opacity: opacity.clamp(0.0, 1.0),
      rotation: angle,
      roundness: roundness.clamp(0.0, 1.0),
      hardness: hardness.clamp(0.0, 1.0),
      color: color,
    );
  }

  double _randomAngle() {
    return (random.nextDouble() * 2.0 - 1.0) * 3.14159;
  }
}
