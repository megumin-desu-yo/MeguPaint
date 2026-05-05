import '../../../presentation/providers/drawing_provider.dart';
import '../brush_engine.dart';
import '../brush_preset.dart';
import '../stamp.dart';

/// 马克笔引擎：半透明叠加，扁平笔尖
/// 特点：低不透明度叠加、扁平椭圆笔尖、方向跟随路径
class MarkerEngine extends BrushEngine {
  @override
  String get id => 'marker';

  @override
  String get name => '马克笔';

  @override
  BrushEngineType get engineType => BrushEngineType.marker;

  @override
  List<Stamp> generateStamps(List<DrawPoint> points, BrushPreset preset) {
    if (points.isEmpty) return [];

    final stamps = <Stamp>[];
    // 马克笔间距非常密，模拟连续涂抹
    final spacingPx = (preset.baseSize * preset.spacing * 0.3).clamp(0.5, double.infinity);

    if (points.length == 1) {
      stamps.add(_createMarkerStamp(points.first, null, null, preset));
      return stamps;
    }

    double accumDist = 0.0;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final segDist = (p1.position - p0.position).distance;

      if (segDist < 0.001) continue;

      // 计算路径方向角度
      final dx = p1.x - p0.x;
      final dy = p1.y - p0.y;
      final pathAngle = _atan2(dy, dx);

      if (i == 0 && accumDist == 0.0) {
        stamps.add(_createMarkerStamp(p0, null, pathAngle, preset));
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
        stamps.add(_createMarkerStamp(interpPoint, i > 0 ? points[i - 1] : null, pathAngle, preset));
      }

      accumDist = (accumDist + segDist) % spacingPx;
    }

    return stamps;
  }

  Stamp _createMarkerStamp(
    DrawPoint point,
    DrawPoint? prevPoint,
    double? pathAngle,
    BrushPreset preset,
  ) {
    double size = applyDynamicMapping(
      preset.baseSize,
      preset.minSizeRatio,
      preset.sizeDynamic,
      point,
      prevPoint,
    );

    // 马克笔不透明度较低，多次叠加产生渐变效果
    double opacity = applyDynamicMapping(
      preset.baseOpacity,
      preset.minOpacityRatio,
      preset.opacityDynamic,
      point,
      prevPoint,
    );

    // 马克笔笔尖角度：跟随路径或固定角度
    double angle = preset.angle;
    if (pathAngle != null && preset.angleDynamic == null) {
      // 默认笔尖垂直于路径方向偏移 45°
      angle = pathAngle + 0.785; // π/4
    }

    // 马克笔圆度较低（扁平笔尖）
    final roundness = preset.roundness;

    // 应用颜色抖动
    final color = applyColorJitter(preset.color, preset.jitter);

    return Stamp(
      position: point.position,
      size: size.clamp(0.5, 500.0),
      opacity: (opacity * preset.flow).clamp(0.0, 1.0),
      rotation: angle,
      roundness: roundness,
      hardness: preset.hardness,
      color: color,
    );
  }

  /// 安全的 atan2
  static double _atan2(double y, double x) {
    if (x == 0 && y == 0) return 0;
    return y.isNaN || x.isNaN ? 0 : _dart_atan2(y, x);
  }

  static double _dart_atan2(double y, double x) {
    // dart:math atan2
    return y == 0 && x == 0 ? 0 : _mathAtan2(y, x);
  }

  static double _mathAtan2(double y, double x) {
    return _importedAtan2(y, x);
  }

  static double _importedAtan2(double y, double x) {
    // 内联实现避免额外导入
    if (x > 0) return _atanApprox(y / x);
    if (x < 0 && y >= 0) return _atanApprox(y / x) + 3.14159265;
    if (x < 0 && y < 0) return _atanApprox(y / x) - 3.14159265;
    if (x == 0 && y > 0) return 1.5707963;
    if (x == 0 && y < 0) return -1.5707963;
    return 0;
  }

  static double _atanApprox(double x) {
    // 快速 atan 近似
    if (x.abs() > 1) {
      final sign = x >= 0 ? 1.0 : -1.0;
      return sign * 1.5707963 - _atanCore(1.0 / x);
    }
    return _atanCore(x);
  }

  static double _atanCore(double x) {
    final x2 = x * x;
    return x * (1.0 - x2 * (0.3333333 - x2 * 0.2));
  }
}
