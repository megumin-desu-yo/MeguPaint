import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/brush/brush_preset.dart';
import '../../domain/brush/brush_system.dart';
import '../../domain/brush/default_presets.dart';

/// 绘制点（支持压感、倾斜、旋转、速度）- 使用类优化性能
class DrawPoint {
  double x;
  double y;
  double pressure; // 0.0 - 1.0
  double tilt; // 0.0 - 1.0（倾斜角度归一化）
  double rotation; // 弧度（笔杆旋转）
  double velocity; // 像素/采样（由时间戳计算）
  int timestamp; // 毫秒时间戳

  DrawPoint({
    required Offset position,
    this.pressure = 0.5,
    this.tilt = 0.0,
    this.rotation = 0.0,
    this.velocity = 0.0,
    this.timestamp = 0,
  }) : x = position.dx,
       y = position.dy;

  Offset get position => Offset(x, y);

  /// 直接设置坐标（避免创建新对象）
  void setPosition(Offset pos, [double? p]) {
    x = pos.dx;
    y = pos.dy;
    if (p != null) pressure = p;
  }

  Map<String, dynamic> toMap() => {
    'x': x,
    'y': y,
    'pressure': pressure,
    'tilt': tilt,
    'rotation': rotation,
    'velocity': velocity,
    'timestamp': timestamp,
  };

  factory DrawPoint.fromMap(Map<String, dynamic> map) {
    return DrawPoint(
      position: Offset(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
      ),
      pressure: (map['pressure'] as num?)?.toDouble() ?? 0.5,
      tilt: (map['tilt'] as num?)?.toDouble() ?? 0.0,
      rotation: (map['rotation'] as num?)?.toDouble() ?? 0.0,
      velocity: (map['velocity'] as num?)?.toDouble() ?? 0.0,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 预测点缓存（用于平滑算法）
class _PredictiveCache {
  final List<Offset> rawPositions = [];
  static const int _maxSize = 4;

  void add(Offset position) {
    rawPositions.add(position);
    if (rawPositions.length > _maxSize) {
      rawPositions.removeAt(0);
    }
  }

  void clear() => rawPositions.clear();

  /// 计算预测位置（基于速度趋势）
  Offset? predict() {
    if (rawPositions.length < 2) return null;
    final last = rawPositions.last;
    final prev = rawPositions[rawPositions.length - 2];
    // 外推一个点
    return Offset(
      last.dx + (last.dx - prev.dx) * 0.5,
      last.dy + (last.dy - prev.dy) * 0.5,
    );
  }
}

/// 压感曲线控制点（简化版，用于 provider）
class PressureCurvePoint {
  final double x; // 输入压力
  final double y; // 输出压力

  const PressureCurvePoint({required this.x, required this.y});

  Map<String, dynamic> toMap() => {'x': x, 'y': y};

  factory PressureCurvePoint.fromMap(Map<String, dynamic> map) =>
      PressureCurvePoint(x: map['x'] as double, y: map['y'] as double);
}

/// 笔刷设置
class BrushSettings {
  final Color color;
  final double width;
  final double opacity; // 0.0 - 1.0
  final double stabilization; // 0.0 - 1.0 (稳定度，越大越平滑)
  final double stabilizationFactor; // 0.0 - 1.0 (稳定度系数，影响跟手性)
  final double pressureIntensity; // 0.0 - 1.0 (压感强度)
  final bool pressureEnabled; // 压感开关
  final bool smoothEnabled; // 平滑曲线开关
  final List<PressureCurvePoint> pressureCurve; // 压感曲线控制点

  const BrushSettings({
    this.color = Colors.black,
    this.width = 4.0,
    this.opacity = 1.0,
    this.stabilization = 0.3,
    this.stabilizationFactor = 0.7,
    this.pressureIntensity = 0.5,
    this.pressureEnabled = true,
    this.smoothEnabled = true,
    this.pressureCurve = const [
      PressureCurvePoint(x: 0.0, y: 0.0),
      PressureCurvePoint(x: 1.0, y: 1.0),
    ],
  });

  BrushSettings copyWith({
    Color? color,
    double? width,
    double? opacity,
    double? stabilization,
    double? stabilizationFactor,
    double? pressureIntensity,
    bool? pressureEnabled,
    bool? smoothEnabled,
    List<PressureCurvePoint>? pressureCurve,
  }) {
    return BrushSettings(
      color: color ?? this.color,
      width: width ?? this.width,
      opacity: opacity ?? this.opacity,
      stabilization: stabilization ?? this.stabilization,
      stabilizationFactor: stabilizationFactor ?? this.stabilizationFactor,
      pressureIntensity: pressureIntensity ?? this.pressureIntensity,
      pressureEnabled: pressureEnabled ?? this.pressureEnabled,
      smoothEnabled: smoothEnabled ?? this.smoothEnabled,
      pressureCurve: pressureCurve ?? this.pressureCurve,
    );
  }
}

/// 绘制状态（分离笔刷和点数据以减少重建）
class DrawingState {
  /// 当前正在绘制的点列表（可变，避免频繁内存分配）
  final List<DrawPoint> currentPoints;

  /// 是否正在绘制
  final bool isDrawing;

  /// 点数量（用于快速判断变化）
  final int pointCount;

  /// 最后一个点的位置（用于快速重绘判断）
  final Offset? lastPosition;

  const DrawingState({
    required this.currentPoints,
    this.isDrawing = false,
    this.pointCount = 0,
    this.lastPosition,
  });

  /// 创建空状态
  factory DrawingState.empty() => DrawingState(
    currentPoints: [],
    isDrawing: false,
    pointCount: 0,
    lastPosition: null,
  );
}

/// 笔刷状态（独立管理，减少不必要的重建）
class BrushState {
  final BrushSettings settings;

  const BrushState({this.settings = const BrushSettings()});
}

/// 绘制状态管理器（高性能版本）
class DrawingNotifier extends StateNotifier<DrawingState> {
  /// 可变点列表（复用内存）
  final List<DrawPoint> _mutablePoints = [];

  /// 预测缓存
  final _PredictiveCache _predictiveCache = _PredictiveCache();

  /// 当前笔刷设置引用
  BrushSettings _brush = const BrushSettings();

  /// 上一次稳定后的位置（用于平滑算法）
  Offset? _lastStabilizedPosition;
  double? _lastStabilizedPressure;

  DrawingNotifier() : super(DrawingState.empty());

  /// 获取当前笔刷设置
  BrushSettings get brush => _brush;

  /// 开始绘制
  void startStroke(Offset position, {double pressure = 0.5}) {
    _mutablePoints.clear();
    _predictiveCache.clear();
    _lastStabilizedPosition = null;
    _lastStabilizedPressure = null;

    _mutablePoints.add(DrawPoint(position: position, pressure: pressure));
    _predictiveCache.add(position);

    _emitState();
  }

  /// 添加点（高性能版本，避免创建新列表）
  void addPoint(Offset position, {double pressure = 0.5}) {
    if (_mutablePoints.isEmpty) return;

    _predictiveCache.add(position);

    DrawPoint newPoint;
    final stabilization = _brush.stabilization;

    if (stabilization > 0 && _lastStabilizedPosition != null) {
      // 使用移动加权平均 + 预测补偿
      final factor = stabilization * _brush.stabilizationFactor; // 稳定度系数影响跟手性

      // 基于速度动态调整稳定度
      final velocity = (position - _lastStabilizedPosition!).distance;
      final dynamicFactor = factor * (1.0 - math.min(velocity / 100, 0.5));

      // 稳定位置
      final stabilizedPosition = Offset(
        _lastStabilizedPosition!.dx * dynamicFactor +
            position.dx * (1 - dynamicFactor),
        _lastStabilizedPosition!.dy * dynamicFactor +
            position.dy * (1 - dynamicFactor),
      );

      // 稳定压感
      final stabilizedPressure =
          _lastStabilizedPressure! * dynamicFactor +
          pressure * (1 - dynamicFactor);

      newPoint = DrawPoint(
        position: stabilizedPosition,
        pressure: stabilizedPressure,
      );
      _lastStabilizedPosition = stabilizedPosition;
      _lastStabilizedPressure = stabilizedPressure;
    } else {
      newPoint = DrawPoint(position: position, pressure: pressure);
      _lastStabilizedPosition = position;
      _lastStabilizedPressure = pressure;
    }

    _mutablePoints.add(newPoint);
    _emitState();
  }

  /// 结束绘制，返回最终的点列表
  List<DrawPoint> endStroke() {
    final points = List<DrawPoint>.from(_mutablePoints);
    _mutablePoints.clear();
    _predictiveCache.clear();
    _lastStabilizedPosition = null;
    _lastStabilizedPressure = null;

    state = DrawingState.empty();
    return points;
  }

  /// 取消当前正在绘制的笔画（用于撤回操作）
  void cancelStroke() {
    _mutablePoints.clear();
    _predictiveCache.clear();
    _lastStabilizedPosition = null;
    _lastStabilizedPressure = null;

    state = DrawingState.empty();
  }

  /// 发射状态更新（仅在需要时触发）
  void _emitState() {
    state = DrawingState(
      currentPoints: _mutablePoints,
      isDrawing: true,
      pointCount: _mutablePoints.length,
      lastPosition: _mutablePoints.isNotEmpty
          ? _mutablePoints.last.position
          : null,
    );
  }

  /// 更新笔刷设置（不触发绘制状态重建）
  void updateBrush(BrushSettings brush) {
    _brush = brush;
  }

  /// 更新颜色
  void setColor(Color color) {
    _brush = _brush.copyWith(color: color);
  }

  /// 更新宽度
  void setWidth(double width) {
    _brush = _brush.copyWith(width: width);
  }

  /// 更新透明度
  void setOpacity(double opacity) {
    _brush = _brush.copyWith(opacity: opacity);
  }

  /// 更新稳定度
  void setStabilization(double stabilization) {
    _brush = _brush.copyWith(stabilization: stabilization);
  }

  /// 更新压感强度
  void setPressureIntensity(double pressureIntensity) {
    _brush = _brush.copyWith(pressureIntensity: pressureIntensity);
  }

  /// 更新压感开关
  void setPressureEnabled(bool pressureEnabled) {
    _brush = _brush.copyWith(pressureEnabled: pressureEnabled);
  }

  /// 更新平滑曲线开关
  void setSmoothEnabled(bool smoothEnabled) {
    _brush = _brush.copyWith(smoothEnabled: smoothEnabled);
  }

  /// 更新稳定度系数
  void setStabilizationFactor(double stabilizationFactor) {
    _brush = _brush.copyWith(stabilizationFactor: stabilizationFactor);
  }

  /// 更新压感曲线
  void setPressureCurve(List<PressureCurvePoint> pressureCurve) {
    _brush = _brush.copyWith(pressureCurve: pressureCurve);
  }
}

/// 笔刷状态管理器（独立管理笔刷设置，兼容旧接口）
class BrushNotifier extends StateNotifier<BrushState> {
  BrushNotifier() : super(const BrushState());

  BrushSettings get settings => state.settings;

  void updateBrush(BrushSettings settings) {
    state = BrushState(settings: settings);
  }

  void setColor(Color color) {
    state = BrushState(settings: state.settings.copyWith(color: color));
  }

  void setWidth(double width) {
    state = BrushState(settings: state.settings.copyWith(width: width));
  }

  void setOpacity(double opacity) {
    state = BrushState(settings: state.settings.copyWith(opacity: opacity));
  }

  void setStabilization(double stabilization) {
    state = BrushState(
      settings: state.settings.copyWith(stabilization: stabilization),
    );
  }

  void setPressureIntensity(double pressureIntensity) {
    state = BrushState(
      settings: state.settings.copyWith(pressureIntensity: pressureIntensity),
    );
  }

  void setPressureEnabled(bool pressureEnabled) {
    state = BrushState(
      settings: state.settings.copyWith(pressureEnabled: pressureEnabled),
    );
  }

  void setSmoothEnabled(bool smoothEnabled) {
    state = BrushState(
      settings: state.settings.copyWith(smoothEnabled: smoothEnabled),
    );
  }

  void setStabilizationFactor(double stabilizationFactor) {
    state = BrushState(
      settings: state.settings.copyWith(
        stabilizationFactor: stabilizationFactor,
      ),
    );
  }

  void setPressureCurve(List<PressureCurvePoint> pressureCurve) {
    state = BrushState(
      settings: state.settings.copyWith(pressureCurve: pressureCurve),
    );
  }
}

// === 笔刷预设状态管理 ===

/// 笔刷预设状态
class BrushPresetState {
  /// 当前选中的预设
  final BrushPreset currentPreset;

  /// 所有可用预设（内置 + 用户自定义）
  final List<BrushPreset> allPresets;

  const BrushPresetState({
    required this.currentPreset,
    required this.allPresets,
  });

  BrushPresetState copyWith({
    BrushPreset? currentPreset,
    List<BrushPreset>? allPresets,
  }) => BrushPresetState(
    currentPreset: currentPreset ?? this.currentPreset,
    allPresets: allPresets ?? this.allPresets,
  );
}

/// 笔刷预设管理器
class BrushPresetNotifier extends StateNotifier<BrushPresetState> {
  final BrushSystem _brushSystem = BrushSystem();

  BrushPresetNotifier()
    : super(
        BrushPresetState(
          currentPreset: DefaultPresets.hardRound,
          allPresets: BrushSystem().presets,
        ),
      );

  /// 获取当前预设
  BrushPreset get currentPreset => state.currentPreset;

  /// 选择预设
  void selectPreset(String presetId) {
    final preset = _brushSystem.getPreset(presetId);
    if (preset != null) {
      state = state.copyWith(currentPreset: preset);
    }
  }

  /// 更新当前预设的颜色（不改变预设本身，仅覆盖颜色）
  void setColor(Color color) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(color: color),
    );
  }

  /// 更新当前预设的基础尺寸
  void setBaseSize(double size) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(baseSize: size),
    );
  }

  /// 更新当前预设的不透明度
  void setBaseOpacity(double opacity) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(baseOpacity: opacity),
    );
  }

  /// 更新当前预设的硬度
  void setHardness(double hardness) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(hardness: hardness),
    );
  }

  /// 更新当前预设的间距
  void setSpacing(double spacing) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(spacing: spacing),
    );
  }

  /// 更新当前预设的流量
  void setFlow(double flow) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(flow: flow),
    );
  }

  /// 更新当前预设的稳定度
  void setStabilization(double stabilization) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(stabilization: stabilization),
    );
  }

  /// 更新当前预设的压感开关
  void setPressureEnabled(bool enabled) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(pressureEnabled: enabled),
    );
  }

  /// 更新当前预设的平滑开关
  void setSmoothEnabled(bool enabled) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(smoothEnabled: enabled),
    );
  }

  /// 更新当前预设的圆度
  void setRoundness(double roundness) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(roundness: roundness),
    );
  }

  /// 更新当前预设的角度
  void setAngle(double angle) {
    state = state.copyWith(
      currentPreset: state.currentPreset.copyWith(angle: angle),
    );
  }

  /// 添加用户自定义预设（基于当前预设克隆）
  void saveAsNewPreset(String name) {
    final newId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final newPreset = state.currentPreset.copyWith(
      id: newId,
      name: name,
      isBuiltin: false,
    );
    _brushSystem.addPreset(newPreset);
    state = state.copyWith(
      currentPreset: newPreset,
      allPresets: _brushSystem.presets,
    );
  }

  /// 删除用户自定义预设
  void deletePreset(String presetId) {
    if (_brushSystem.removePreset(presetId)) {
      // 如果删除的是当前预设，切换到默认预设
      if (state.currentPreset.id == presetId) {
        state = state.copyWith(
          currentPreset: _brushSystem.defaultPreset,
          allPresets: _brushSystem.presets,
        );
      } else {
        state = state.copyWith(allPresets: _brushSystem.presets);
      }
    }
  }

  /// 刷新预设列表
  void refreshPresets() {
    state = state.copyWith(allPresets: _brushSystem.presets);
  }
}

/// 绘制 Provider（点数据）
final drawingProvider = StateNotifierProvider<DrawingNotifier, DrawingState>(
  (ref) => DrawingNotifier(),
);

/// 笔刷 Provider（独立管理笔刷设置，兼容旧接口）
final brushProvider = StateNotifierProvider<BrushNotifier, BrushState>(
  (ref) => BrushNotifier(),
);

/// 笔刷预设 Provider（新笔刷系统）
final brushPresetProvider =
    StateNotifierProvider<BrushPresetNotifier, BrushPresetState>(
      (ref) => BrushPresetNotifier(),
    );

/// 笔刷粗细非线性曲线程度（指数）。
/// 1.0 = 线性；越大越偏向小值区更细分
final brushSizeCurveExponentProvider = StateProvider<double>((ref) => 2.0);
