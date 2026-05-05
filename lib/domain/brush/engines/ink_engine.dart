import '../../../presentation/providers/drawing_provider.dart';
import '../brush_engine.dart';
import '../brush_preset.dart';
import '../stamp.dart';

/// 墨水引擎：模拟毛笔/钢笔，压感敏感
/// 特点：压感强烈影响笔触宽度，起笔收笔有明显变化，流畅连贯
class InkEngine extends BrushEngine {
  @override
  String get id => 'ink';

  @override
  String get name => '墨水';

  @override
  BrushEngineType get engineType => BrushEngineType.ink;

  @override
  List<Stamp> generateStamps(List<DrawPoint> points, BrushPreset preset) {
    if (points.isEmpty) return [];

    final stamps = <Stamp>[];
    // 墨水笔间距较密，确保流畅
    final spacingPx = (preset.baseSize * preset.spacing * 0.4).clamp(
      0.3,
      double.infinity,
    );

    if (points.length == 1) {
      stamps.add(_createInkStamp(points.first, null, preset));
      return stamps;
    }

    double accumDist = 0.0;

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final segDist = (p1.position - p0.position).distance;

      if (segDist < 0.001) continue;

      if (i == 0 && accumDist == 0.0) {
        stamps.add(_createInkStamp(p0, null, preset));
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
          rotation: p0.rotation + (p1.rotation - p0.rotation) * t,
          velocity: p0.velocity + (p1.velocity - p0.velocity) * t,
        );
        stamps.add(
          _createInkStamp(interpPoint, i > 0 ? points[i - 1] : null, preset),
        );
      }

      accumDist = (accumDist + segDist) % spacingPx;
    }

    // 末端印
    stamps.add(_createInkStamp(points.last, points[points.length - 2], preset));

    // 后处理：基于物理距离应用起笔渐入/收笔渐出
    _applyTaper(stamps, spacingPx, preset.baseSize);

    return stamps;
  }

  /// 对印列表应用起笔渐入/收笔渐出效果
  /// 基于物理距离（与笔刷尺寸成比例）计算 taper 印数量，
  /// 既保证笔锋效果明显，又避免因百分比导致的实时抖动
  void _applyTaper(List<Stamp> stamps, double spacingPx, double baseSize) {
    final total = stamps.length;
    if (total <= 1) return;

    // taper 物理距离与笔刷尺寸成比例，再转换为印数量
    final taperInMin = 4;
    final taperOutMin = 3;
    final half = total ~/ 2;

    // 上限不能超过 total-1，避免 i/taperCount 出现极端情况
    final taperInUpper = (half < taperInMin ? taperInMin : half) > (total - 1)
        ? (total - 1)
        : (half < taperInMin ? taperInMin : half);
    final taperOutUpper =
        (half < taperOutMin ? taperOutMin : half) > (total - 1)
        ? (total - 1)
        : (half < taperOutMin ? taperOutMin : half);

    final taperInCount = taperInUpper <= taperInMin
        ? taperInUpper
        : (baseSize * 1.0 / spacingPx).ceil().clamp(taperInMin, taperInUpper);
    final taperOutCount = taperOutUpper <= taperOutMin
        ? taperOutUpper
        : (baseSize * 0.6 / spacingPx).ceil().clamp(taperOutMin, taperOutUpper);

    for (int i = 0; i < total; i++) {
      double sizeFactor = 1.0;

      // 起笔渐入：前 N 个印逐渐变大
      if (i < taperInCount) {
        final taperIn = i / taperInCount;
        sizeFactor = 0.3 + 0.7 * taperIn;
      }
      // 收笔渐出：后 M 个印逐渐变小
      final distFromEnd = total - 1 - i;
      if (distFromEnd < taperOutCount) {
        final taperOut = distFromEnd / taperOutCount;
        final outFactor = 0.2 + 0.8 * taperOut;
        sizeFactor = sizeFactor < 1.0 ? sizeFactor * outFactor : outFactor;
      }

      if (sizeFactor < 1.0) {
        stamps[i] = stamps[i].copyWith(
          size: (stamps[i].size * sizeFactor).clamp(0.5, 500.0),
        );
      }
    }
  }

  Stamp _createInkStamp(
    DrawPoint point,
    DrawPoint? prevPoint,
    BrushPreset preset,
  ) {
    // 墨水笔尺寸受压感强烈影响
    double size = applyDynamicMapping(
      preset.baseSize,
      preset.minSizeRatio,
      preset.sizeDynamic,
      point,
      prevPoint,
    );

    // 不透明度
    double opacity = applyDynamicMapping(
      preset.baseOpacity,
      preset.minOpacityRatio,
      preset.opacityDynamic,
      point,
      prevPoint,
    );

    // 速度影响：快速绘制时墨水变薄（透明度降低）
    if (prevPoint != null) {
      final vel = (point.position - prevPoint.position).distance;
      final velFactor = 1.0 - (vel / 150.0).clamp(0.0, 0.3);
      opacity *= velFactor;
    }

    // 墨水笔硬度：较高以获得锐利边缘
    final hardness = preset.hardness;

    // 轻微圆度变化模拟毛笔效果
    double roundness = preset.roundness;
    if (point.tilt > 0) {
      roundness = (roundness * (1.0 - point.tilt * 0.5)).clamp(0.2, 1.0);
    }

    // 应用颜色抖动
    final color = applyColorJitter(preset.color, preset.jitter);

    return Stamp(
      position: point.position,
      size: size.clamp(0.5, 500.0),
      opacity: (opacity * preset.flow).clamp(0.0, 1.0),
      rotation: preset.angle,
      roundness: roundness,
      hardness: hardness,
      color: color,
    );
  }
}
