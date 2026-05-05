import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用设置状态
/// 该类存储用户自定义的应用程序设置，包括画布尺寸、自动保存选项等。
class AppSettings {
  final int defaultCanvasWidth;
  final int defaultCanvasHeight;
  final bool autoSave;
  final Duration autoSaveInterval;
  final Locale currentLocale;
  final bool debugMode;
  final bool pressureSmoothing;
  final double pressureSmoothingFactor;
  final bool pressureStartRamp;
  final double pressureStartRampStrength;

  const AppSettings({
    this.defaultCanvasWidth = 1920,

    /// 默认画布宽度（像素），默认值为1920
    this.defaultCanvasHeight = 1080,
    this.autoSave = true,
    this.autoSaveInterval = const Duration(minutes: 5),
    this.currentLocale = const Locale('zh', 'CN'),
    this.debugMode = false,
    this.pressureSmoothing = true,
    this.pressureSmoothingFactor = 0.3,
    this.pressureStartRamp = false,
    this.pressureStartRampStrength = 0.7,
  });

  /// 复制当前对象并允许修改部分字段，返回一个新的AppSettings实例
  /// 常用于状态更新（例如在StateNotifier中修改状态）
  AppSettings copyWith({
    int? defaultCanvasWidth,
    int? defaultCanvasHeight,
    bool? autoSave,
    Duration? autoSaveInterval,
    Locale? currentLocale,
    bool? debugMode,
    bool? pressureSmoothing,
    double? pressureSmoothingFactor,
    bool? pressureStartRamp,
    double? pressureStartRampStrength,
  }) {
    return AppSettings(
      defaultCanvasWidth: defaultCanvasWidth ?? this.defaultCanvasWidth,
      defaultCanvasHeight: defaultCanvasHeight ?? this.defaultCanvasHeight,
      autoSave: autoSave ?? this.autoSave,
      autoSaveInterval: autoSaveInterval ?? this.autoSaveInterval,
      currentLocale: currentLocale ?? this.currentLocale,
      debugMode: debugMode ?? this.debugMode,
      pressureSmoothing: pressureSmoothing ?? this.pressureSmoothing,
      pressureSmoothingFactor:
          pressureSmoothingFactor ?? this.pressureSmoothingFactor,
      pressureStartRamp: pressureStartRamp ?? this.pressureStartRamp,
      pressureStartRampStrength:
          pressureStartRampStrength ?? this.pressureStartRampStrength,
    );
  }
}

/// 设置状态管理器
/// 继承自StateNotifier，负责管理AppSettings状态并提供修改状态的方法
/// 使得其他组件可以监听AppSettings的变化并调用SettingsNotifier的方法
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  // 更新默认画布尺寸
  void setDefaultCanvasSize(int width, int height) {
    state = state.copyWith(
      defaultCanvasWidth: width,
      defaultCanvasHeight: height,
    );
  }

  // 更新自动保存设置
  void setAutoSave(bool enabled, [Duration? interval]) {
    state = state.copyWith(
      autoSave: enabled,
      autoSaveInterval: interval ?? state.autoSaveInterval,
    );
  }

  // 切换语言
  void setLocale(Locale locale) {
    state = state.copyWith(currentLocale: locale);
  }

  // 切换调试模式
  void setDebugMode(bool enabled) {
    state = state.copyWith(debugMode: enabled);
  }

  // 切换压感平滑
  void setPressureSmoothing(bool enabled) {
    state = state.copyWith(pressureSmoothing: enabled);
  }

  // 设置压感平滑因子
  void setPressureSmoothingFactor(double factor) {
    state = state.copyWith(pressureSmoothingFactor: factor);
  }

  // 切换起笔压感抬升
  void setPressureStartRamp(bool enabled) {
    state = state.copyWith(pressureStartRamp: enabled);
  }

  // 设置起笔压感抬升强度
  void setPressureStartRampStrength(double strength) {
    state = state.copyWith(pressureStartRampStrength: strength);
  }
}

/// 设置Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(),
);
