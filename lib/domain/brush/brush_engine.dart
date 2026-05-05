import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

import '../../presentation/providers/drawing_provider.dart';
import 'brush_preset.dart';
import 'jitter_settings.dart';
import 'stamp.dart';

/// 笔刷引擎抽象基类
/// 每个引擎实现特定的笔迹生成算法
abstract class BrushEngine {
  /// 引擎唯一标识
  String get id;

  /// 引擎显示名称
  String get name;

  /// 对应的引擎类型
  BrushEngineType get engineType;

  /// 根据输入点和预设生成印（Stamp）列表
  /// [points] 输入点序列（已经过稳定化处理）
  /// [preset] 笔刷预设
  /// 返回需要渲染的 Stamp 列表
  List<Stamp> generateStamps(List<DrawPoint> points, BrushPreset preset);

  /// 随机数生成器（各引擎共享种子以保证可重现性）
  final math.Random random = math.Random();

  // === 工具方法 ===

  /// 从输入点提取动态源值
  double getDynamicValue(
    DynamicSource source,
    DrawPoint point,
    DrawPoint? prevPoint,
  ) {
    switch (source) {
      case DynamicSource.pressure:
        return point.pressure.clamp(0.0, 1.0);
      case DynamicSource.velocity:
        if (prevPoint == null) return 0.5;
        final dist = (point.position - prevPoint.position).distance;
        // 归一化速度：0-200 像素/采样 映射到 0-1
        return (dist / 200.0).clamp(0.0, 1.0);
      case DynamicSource.tilt:
        return point.tilt.clamp(0.0, 1.0);
      case DynamicSource.rotation:
        // 归一化到 0-1
        return (point.rotation / (2 * math.pi)).clamp(0.0, 1.0);
      case DynamicSource.random:
        return random.nextDouble();
    }
  }

  /// 计算动态映射后的值
  /// [base] 基础值
  /// [minRatio] 最小比例
  /// [mapping] 动态映射配置
  /// [point] 当前输入点
  /// [prevPoint] 前一个输入点（用于计算速度）
  double applyDynamicMapping(
    double base,
    double minRatio,
    DynamicMapping? mapping,
    DrawPoint point,
    DrawPoint? prevPoint,
  ) {
    if (mapping == null || !mapping.enabled) return base;
    final input = getDynamicValue(mapping.source, point, prevPoint);
    final factor = mapping.curve.evaluate(input);
    // factor=0 时使用 minRatio*base, factor=1 时使用 base
    return base * (minRatio + (1.0 - minRatio) * factor);
  }

  /// 应用抖动到值
  double applyJitter(double value, double jitterAmount) {
    if (jitterAmount <= 0) return value;
    final offset = (random.nextDouble() * 2.0 - 1.0) * jitterAmount;
    return value * (1.0 + offset);
  }

  /// 应用散布偏移
  Offset applyScatter(Offset position, double scatterAmount, double brushSize) {
    if (scatterAmount <= 0) return position;
    final angle = random.nextDouble() * 2 * math.pi;
    final dist = random.nextDouble() * scatterAmount * brushSize;
    return Offset(
      position.dx + math.cos(angle) * dist,
      position.dy + math.sin(angle) * dist,
    );
  }

  /// 应用颜色抖动
  Color applyColorJitter(Color color, JitterSettings jitter) {
    if (!jitter.hasJitter) return color;
    if (jitter.hueJitter <= 0 &&
        jitter.saturationJitter <= 0 &&
        jitter.brightnessJitter <= 0) {
      return color;
    }

    final hsl = HSLColor.fromColor(color);
    double h = hsl.hue;
    double s = hsl.saturation;
    double l = hsl.lightness;

    if (jitter.hueJitter > 0) {
      h =
          (h + (random.nextDouble() * 2.0 - 1.0) * jitter.hueJitter * 360) %
          360;
      if (h < 0) h += 360;
    }
    if (jitter.saturationJitter > 0) {
      s = (s + (random.nextDouble() * 2.0 - 1.0) * jitter.saturationJitter)
          .clamp(0.0, 1.0);
    }
    if (jitter.brightnessJitter > 0) {
      l = (l + (random.nextDouble() * 2.0 - 1.0) * jitter.brightnessJitter)
          .clamp(0.0, 1.0);
    }

    return HSLColor.fromAHSL(color.opacity, h, s, l).toColor();
  }

  /// 沿路径在两点间生成间隔点
  /// 返回插值后的 (位置, t值) 列表，t 用于插值压感等属性
  List<({Offset position, double t})> interpolatePositions(
    Offset from,
    Offset to,
    double spacing,
    double startDistance,
  ) {
    final totalDist = (to - from).distance;
    if (totalDist < 0.001) return [];

    final result = <({Offset position, double t})>[];
    final dir = Offset(
      (to.dx - from.dx) / totalDist,
      (to.dy - from.dy) / totalDist,
    );

    double d = startDistance;
    while (d < totalDist) {
      final t = d / totalDist;
      result.add((
        position: Offset(from.dx + dir.dx * d, from.dy + dir.dy * d),
        t: t,
      ));
      d += spacing;
    }
    return result;
  }

  /// 线性插值 DrawPoint 属性
  double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// 笔刷引擎注册表
class BrushEngineRegistry {
  static final BrushEngineRegistry _instance = BrushEngineRegistry._();
  factory BrushEngineRegistry() => _instance;
  BrushEngineRegistry._();

  final Map<BrushEngineType, BrushEngine> _engines = {};

  /// 注册引擎
  void register(BrushEngine engine) {
    _engines[engine.engineType] = engine;
  }

  /// 获取引擎
  BrushEngine? getEngine(BrushEngineType type) => _engines[type];

  /// 获取所有已注册引擎
  List<BrushEngine> get allEngines => _engines.values.toList();

  /// 检查引擎是否已注册
  bool hasEngine(BrushEngineType type) => _engines.containsKey(type);
}
