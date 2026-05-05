import 'dart:ui';

import '../../presentation/providers/drawing_provider.dart';
import 'brush_engine.dart';
import 'brush_preset.dart';
import 'default_presets.dart';
import 'engines/airbrush_engine.dart';
import 'engines/ink_engine.dart';
import 'engines/marker_engine.dart';
import 'engines/pencil_engine.dart';
import 'engines/round_engine.dart';
import 'stamp.dart';
import 'stamp_renderer.dart';

/// 笔刷系统门面：统一入口，管理引擎注册、预设和渲染流程
class BrushSystem {
  static final BrushSystem _instance = BrushSystem._();
  factory BrushSystem() => _instance;

  BrushSystem._() {
    _initialize();
  }

  final BrushEngineRegistry _registry = BrushEngineRegistry();

  /// 当前预设列表（内置 + 用户自定义）
  final List<BrushPreset> _presets = [];

  /// 是否已初始化
  bool _initialized = false;

  /// 初始化：注册所有引擎和加载内置预设
  void _initialize() {
    if (_initialized) return;

    // 注册内置引擎
    _registry.register(RoundEngine());
    _registry.register(PencilEngine());
    _registry.register(AirbrushEngine());
    _registry.register(MarkerEngine());
    _registry.register(InkEngine());

    // 加载内置预设
    _presets.addAll(DefaultPresets.all);

    _initialized = true;
  }

  /// 获取所有已注册引擎
  List<BrushEngine> get engines => _registry.allEngines;

  /// 获取所有预设
  List<BrushPreset> get presets => List.unmodifiable(_presets);

  /// 获取内置预设
  List<BrushPreset> get builtinPresets =>
      _presets.where((p) => p.isBuiltin).toList();

  /// 获取用户自定义预设
  List<BrushPreset> get userPresets =>
      _presets.where((p) => !p.isBuiltin).toList();

  /// 根据 ID 获取预设
  BrushPreset? getPreset(String id) {
    try {
      return _presets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 添加用户自定义预设
  void addPreset(BrushPreset preset) {
    _presets.add(preset);
  }

  /// 更新预设
  void updatePreset(BrushPreset preset) {
    final index = _presets.indexWhere((p) => p.id == preset.id);
    if (index >= 0) {
      _presets[index] = preset;
    }
  }

  /// 删除用户自定义预设（内置预设不可删除）
  bool removePreset(String id) {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index < 0) return false;
    if (_presets[index].isBuiltin) return false;
    _presets.removeAt(index);
    return true;
  }

  /// 获取指定引擎类型的引擎实例
  BrushEngine? getEngine(BrushEngineType type) => _registry.getEngine(type);

  /// 根据预设生成印列表
  /// [points] 输入点序列
  /// [preset] 笔刷预设
  List<Stamp> generateStamps(List<DrawPoint> points, BrushPreset preset) {
    final engine = _registry.getEngine(preset.engineType);
    if (engine == null) {
      // 回退到圆形引擎
      final fallback = _registry.getEngine(BrushEngineType.round);
      return fallback?.generateStamps(points, preset) ?? [];
    }
    return engine.generateStamps(points, preset);
  }

  /// 完整渲染流程：生成印 + 渲染到画布
  /// [canvas] 目标画布
  /// [points] 输入点序列
  /// [preset] 笔刷预设
  /// [isEraser] 是否为橡皮擦模式
  void renderStroke(
    Canvas canvas,
    List<DrawPoint> points,
    BrushPreset preset, {
    bool isEraser = false,
  }) {
    if (points.isEmpty) return;

    final stamps = generateStamps(points, preset);
    if (stamps.isEmpty) return;

    StampRenderer.renderStamps(canvas, stamps, isEraser: isEraser);
  }

  /// 获取默认预设（硬边圆形）
  BrushPreset get defaultPreset => DefaultPresets.hardRound;

  /// 导出预设为 Map（用于 JSON 序列化）
  List<Map<String, dynamic>> exportUserPresets() {
    return userPresets.map((p) => p.toMap()).toList();
  }

  /// 导入预设
  void importPresets(List<Map<String, dynamic>> data) {
    for (final map in data) {
      try {
        final preset = BrushPreset.fromMap(map);
        // 避免重复
        if (!_presets.any((p) => p.id == preset.id)) {
          _presets.add(preset);
        }
      } catch (e) {
        // 跳过无效预设
      }
    }
  }
}
