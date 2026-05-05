import 'dart:ui';

import 'brush_preset.dart';
import 'jitter_settings.dart';
import 'response_curve.dart';

/// 内置笔刷预设集合
class DefaultPresets {
  DefaultPresets._();

  /// 获取所有内置预设
  static List<BrushPreset> get all => [
    hardRound,
    softRound,
    pencil2B,
    pencilHB,
    airbrush,
    marker,
    inkBrush,
    calligraphy,
    gPen,
    realGPen,
    sketchPencil,
    dryBrush,
  ];

  /// 硬边圆形笔刷（默认）
  static const BrushPreset hardRound = BrushPreset(
    id: 'builtin_hard_round',
    name: '硬边圆形',
    engineType: BrushEngineType.round,
    baseSize: 10.0,
    minSizeRatio: 0.1,
    baseOpacity: 1.0,
    minOpacityRatio: 0.0,
    hardness: 1.0,
    roundness: 1.0,
    spacing: 0.15,
    flow: 1.0,
    color: Color(0xFF000000),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.constant,
      enabled: false,
    ),
    jitter: JitterSettings.none,
    stabilization: 0.3,
    stabilizationFactor: 0.7,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 柔边圆形笔刷
  static const BrushPreset softRound = BrushPreset(
    id: 'builtin_soft_round',
    name: '柔边圆形',
    engineType: BrushEngineType.round,
    baseSize: 20.0,
    minSizeRatio: 0.2,
    baseOpacity: 0.8,
    minOpacityRatio: 0.1,
    hardness: 0.3,
    roundness: 1.0,
    spacing: 0.1,
    flow: 0.8,
    color: Color(0xFF000000),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
      enabled: true,
    ),
    jitter: JitterSettings.none,
    stabilization: 0.3,
    stabilizationFactor: 0.7,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 2B 铅笔
  static const BrushPreset pencil2B = BrushPreset(
    id: 'builtin_pencil_2b',
    name: '铅笔 2B',
    engineType: BrushEngineType.pencil,
    baseSize: 6.0,
    minSizeRatio: 0.3,
    baseOpacity: 0.7,
    minOpacityRatio: 0.2,
    hardness: 0.5,
    roundness: 0.9,
    spacing: 0.08,
    flow: 0.7,
    color: Color(0xFF333333),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.soft,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
      enabled: true,
    ),
    jitter: JitterSettings(
      sizeJitter: 0.05,
      angleJitter: 0.1,
      opacityJitter: 0.15,
      scatter: 0.05,
    ),
    stabilization: 0.2,
    stabilizationFactor: 0.5,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// HB 铅笔（较硬）
  static const BrushPreset pencilHB = BrushPreset(
    id: 'builtin_pencil_hb',
    name: '铅笔 HB',
    engineType: BrushEngineType.pencil,
    baseSize: 4.0,
    minSizeRatio: 0.4,
    baseOpacity: 0.5,
    minOpacityRatio: 0.1,
    hardness: 0.7,
    roundness: 0.95,
    spacing: 0.06,
    flow: 0.5,
    color: Color(0xFF444444),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.hard,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
      enabled: true,
    ),
    jitter: JitterSettings(
      sizeJitter: 0.03,
      angleJitter: 0.05,
      opacityJitter: 0.1,
      scatter: 0.03,
    ),
    stabilization: 0.15,
    stabilizationFactor: 0.5,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 喷枪
  static const BrushPreset airbrush = BrushPreset(
    id: 'builtin_airbrush',
    name: '喷枪',
    engineType: BrushEngineType.airbrush,
    baseSize: 40.0,
    minSizeRatio: 0.3,
    baseOpacity: 0.6,
    minOpacityRatio: 0.1,
    hardness: 0.0,
    roundness: 1.0,
    spacing: 0.15,
    flow: 0.8,
    color: Color(0xFF000000),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
      enabled: true,
    ),
    jitter: JitterSettings(sizeJitter: 0.1, opacityJitter: 0.2),
    stabilization: 0.1,
    stabilizationFactor: 0.3,
    smoothEnabled: false,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 马克笔
  static const BrushPreset marker = BrushPreset(
    id: 'builtin_marker',
    name: '马克笔',
    engineType: BrushEngineType.marker,
    baseSize: 15.0,
    minSizeRatio: 0.8,
    baseOpacity: 0.4,
    minOpacityRatio: 0.2,
    hardness: 0.8,
    roundness: 0.5,
    angle: 0.785, // π/4
    spacing: 0.05,
    flow: 0.6,
    color: Color(0xFF000000),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.constant,
      enabled: false,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.constant,
      enabled: false,
    ),
    jitter: JitterSettings.none,
    stabilization: 0.2,
    stabilizationFactor: 0.5,
    smoothEnabled: true,
    pressureEnabled: false,
    isBuiltin: true,
  );

  /// 墨水笔
  static const BrushPreset inkBrush = BrushPreset(
    id: 'builtin_ink',
    name: '墨水笔',
    engineType: BrushEngineType.ink,
    baseSize: 8.0,
    minSizeRatio: 0.05,
    baseOpacity: 1.0,
    minOpacityRatio: 0.3,
    hardness: 0.9,
    roundness: 1.0,
    spacing: 0.08,
    flow: 1.0,
    color: Color(0xFF000000),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve(
        points: [
          CurvePoint(input: 0.0, output: 0.0),
          CurvePoint(input: 0.3, output: 0.5),
          CurvePoint(input: 0.7, output: 0.9),
          CurvePoint(input: 1.0, output: 1.0),
        ],
      ),
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
      enabled: true,
    ),
    jitter: JitterSettings.none,
    stabilization: 0.4,
    stabilizationFactor: 0.8,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 书法笔
  static const BrushPreset calligraphy = BrushPreset(
    id: 'builtin_calligraphy',
    name: '书法笔',
    engineType: BrushEngineType.ink,
    baseSize: 12.0,
    minSizeRatio: 0.03,
    baseOpacity: 1.0,
    minOpacityRatio: 0.5,
    hardness: 0.95,
    roundness: 0.4,
    angle: 0.524, // 30°
    spacing: 0.06,
    flow: 1.0,
    color: Color(0xFF1A1A1A),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve(
        points: [
          CurvePoint(input: 0.0, output: 0.0),
          CurvePoint(input: 0.2, output: 0.3),
          CurvePoint(input: 0.8, output: 0.95),
          CurvePoint(input: 1.0, output: 1.0),
        ],
      ),
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.constant,
      enabled: false,
    ),
    roundnessDynamic: DynamicMapping(
      source: DynamicSource.tilt,
      curve: ResponseCurve.linear,
      enabled: true,
    ),
    jitter: JitterSettings.none,
    stabilization: 0.5,
    stabilizationFactor: 0.8,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 基础G笔：强S型压力曲线，硬朗手感，适合精确控制的轮廓线
  static const BrushPreset gPen = BrushPreset(
    id: 'builtin_g_pen',
    name: 'G笔',
    engineType: BrushEngineType.ink,
    baseSize: 20.0,
    minSizeRatio: 0.02,
    baseOpacity: 1.0,
    minOpacityRatio: 0.0,
    hardness: 0.95,
    roundness: 1.0,
    spacing: 0.03,
    flow: 1.0,
    color: Color(0xFF000000),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.strongS,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.constant,
      enabled: false,
    ),
    jitter: JitterSettings(sizeJitter: 0.015, opacityJitter: 0.02),
    stabilization: 0.4,
    stabilizationFactor: 0.8,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 真实G笔：软S型曲线，起点更灵敏，弹性更好，适合自由绘画风格
  static const BrushPreset realGPen = BrushPreset(
    id: 'builtin_real_g_pen',
    name: '真实G笔',
    engineType: BrushEngineType.ink,
    baseSize: 25.0,
    minSizeRatio: 0.02,
    baseOpacity: 1.0,
    minOpacityRatio: 0.0,
    hardness: 0.8,
    roundness: 1.0,
    spacing: 0.03,
    flow: 1.0,
    color: Color(0xFF000000),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.softS,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.constant,
      enabled: false,
    ),
    jitter: JitterSettings(sizeJitter: 0.02, opacityJitter: 0.025),
    stabilization: 0.35,
    stabilizationFactor: 0.7,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 速写铅笔
  static const BrushPreset sketchPencil = BrushPreset(
    id: 'builtin_sketch_pencil',
    name: '速写铅笔',
    engineType: BrushEngineType.pencil,
    baseSize: 3.0,
    minSizeRatio: 0.5,
    baseOpacity: 0.6,
    minOpacityRatio: 0.1,
    hardness: 0.6,
    roundness: 1.0,
    spacing: 0.05,
    flow: 0.5,
    color: Color(0xFF2C2C2C),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.velocity,
      curve: ResponseCurve.inverseLinear,
      enabled: true,
    ),
    jitter: JitterSettings(
      sizeJitter: 0.08,
      angleJitter: 0.15,
      opacityJitter: 0.2,
      scatter: 0.08,
    ),
    stabilization: 0.1,
    stabilizationFactor: 0.3,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );

  /// 干笔
  static const BrushPreset dryBrush = BrushPreset(
    id: 'builtin_dry_brush',
    name: '干笔',
    engineType: BrushEngineType.round,
    baseSize: 25.0,
    minSizeRatio: 0.2,
    baseOpacity: 0.5,
    minOpacityRatio: 0.05,
    hardness: 0.4,
    roundness: 0.7,
    spacing: 0.12,
    flow: 0.4,
    color: Color(0xFF000000),
    sizeDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.linear,
    ),
    opacityDynamic: DynamicMapping(
      source: DynamicSource.pressure,
      curve: ResponseCurve.soft,
      enabled: true,
    ),
    jitter: JitterSettings(
      sizeJitter: 0.15,
      angleJitter: 0.3,
      opacityJitter: 0.4,
      scatter: 0.2,
      roundnessJitter: 0.2,
    ),
    stabilization: 0.2,
    stabilizationFactor: 0.5,
    smoothEnabled: true,
    pressureEnabled: true,
    isBuiltin: true,
  );
}
