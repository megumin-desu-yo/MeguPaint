import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 快捷键动作类型
enum ShortcutAction {
  brush,
  eraser,
  eyedropper,
  move,
  undo,
  redo,
  rectangle,
  circle,
  line,
  fill,
  text,
}

/// 单个快捷键配置
class ShortcutBinding {
  final ShortcutAction action;
  final String label;
  final LogicalKeySet keySet;
  final String displayText;

  const ShortcutBinding({
    required this.action,
    required this.label,
    required this.keySet,
    required this.displayText,
  });

  /// 检查是否匹配给定的按键事件
  bool matches(KeyEvent event, Set<LogicalKeyboardKey> pressedKeys) {
    final keys = keySet.triggers.toSet();
    return keys.isNotEmpty && keys.every((k) => pressedKeys.contains(k));
  }

  /// 从JSON创建
  factory ShortcutBinding.fromJson(Map<String, dynamic> json) {
    final action = ShortcutAction.values.firstWhere(
      (a) => a.toString() == json['action'],
    );
    final keys = (json['keys'] as List).map((k) {
      return LogicalKeyboardKey.findKeyByKeyId(k as int) ??
          LogicalKeyboardKey.keyA;
    }).toList();
    return ShortcutBinding(
      action: action,
      label: json['label'] ?? '',
      keySet: LogicalKeySet.fromSet(keys.toSet()),
      displayText: json['displayText'] ?? '',
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'action': action.toString(),
      'label': label,
      'keys': keySet.triggers.map((k) => k.keyId).toList(),
      'displayText': displayText,
    };
  }
}

/// 快捷键配置状态
class ShortcutSettings {
  final List<ShortcutBinding> bindings;

  const ShortcutSettings({required this.bindings});

  /// 默认快捷键配置
  factory ShortcutSettings.defaults() {
    return ShortcutSettings(
      bindings: [
        ShortcutBinding(
          action: ShortcutAction.brush,
          label: '笔刷',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyB),
          displayText: 'B',
        ),
        ShortcutBinding(
          action: ShortcutAction.eraser,
          label: '橡皮擦',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyE),
          displayText: 'E',
        ),
        ShortcutBinding(
          action: ShortcutAction.eyedropper,
          label: '吸色管',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyI),
          displayText: 'I',
        ),
        ShortcutBinding(
          action: ShortcutAction.move,
          label: '移动',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyM),
          displayText: 'M',
        ),
        ShortcutBinding(
          action: ShortcutAction.undo,
          label: '撤回',
          keySet: LogicalKeySet(
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.keyZ,
          ),
          displayText: 'Ctrl(L)+Z',
        ),
        ShortcutBinding(
          action: ShortcutAction.redo,
          label: '反撤回',
          keySet: LogicalKeySet(
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.keyY,
          ),
          displayText: 'Ctrl(L)+Y',
        ),
        ShortcutBinding(
          action: ShortcutAction.rectangle,
          label: '矩形',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyR),
          displayText: 'R',
        ),
        ShortcutBinding(
          action: ShortcutAction.circle,
          label: '圆形',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyC),
          displayText: 'C',
        ),
        ShortcutBinding(
          action: ShortcutAction.line,
          label: '直线',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyL),
          displayText: 'L',
        ),
        ShortcutBinding(
          action: ShortcutAction.fill,
          label: '填充',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyG),
          displayText: 'G',
        ),
        ShortcutBinding(
          action: ShortcutAction.text,
          label: '文字',
          keySet: LogicalKeySet(LogicalKeyboardKey.keyT),
          displayText: 'T',
        ),
      ],
    );
  }

  /// 获取指定动作的快捷键绑定
  ShortcutBinding? getBinding(ShortcutAction action) {
    try {
      return bindings.firstWhere((b) => b.action == action);
    } catch (_) {
      return null;
    }
  }

  /// 根据按键查找对应的动作
  ShortcutAction? findAction(Set<LogicalKeyboardKey> pressedKeys) {
    for (final binding in bindings) {
      final keys = binding.keySet.triggers.toSet();
      if (keys.isNotEmpty && keys.every((k) => pressedKeys.contains(k))) {
        return binding.action;
      }
    }
    return null;
  }

  /// 检查按键组合是否存在冲突
  /// 返回冲突的动作，如果没有冲突则返回null
  ShortcutAction? checkConflict(
    LogicalKeySet keySet,
    ShortcutAction excludeAction,
  ) {
    final newKeys = keySet.triggers.toSet();
    if (newKeys.isEmpty) return null;

    for (final binding in bindings) {
      if (binding.action == excludeAction) continue;
      final existingKeys = binding.keySet.triggers.toSet();
      if (existingKeys.isNotEmpty && _setsEqual(newKeys, existingKeys)) {
        return binding.action;
      }
    }
    return null;
  }

  bool _setsEqual<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  /// 复制并更新指定动作的快捷键
  ShortcutSettings copyWithBinding(
    ShortcutAction action,
    LogicalKeySet keySet,
    String displayText,
  ) {
    final newBindings = bindings.map((b) {
      if (b.action == action) {
        return ShortcutBinding(
          action: b.action,
          label: b.label,
          keySet: keySet,
          displayText: displayText,
        );
      }
      return b;
    }).toList();
    return ShortcutSettings(bindings: newBindings);
  }

  /// 重置为默认配置
  ShortcutSettings resetToDefaults() => ShortcutSettings.defaults();
}

/// 快捷键设置管理器
class ShortcutNotifier extends StateNotifier<ShortcutSettings> {
  ShortcutNotifier() : super(ShortcutSettings.defaults());

  /// 更新指定动作的快捷键
  /// 返回true表示成功，false表示存在冲突
  bool updateBinding(
    ShortcutAction action,
    LogicalKeySet keySet,
    String displayText,
  ) {
    // 检查冲突
    final conflict = state.checkConflict(keySet, action);
    if (conflict != null) {
      return false;
    }

    state = state.copyWithBinding(action, keySet, displayText);
    return true;
  }

  /// 重置为默认配置
  void reset() {
    state = ShortcutSettings.defaults();
  }

  /// 根据按键查找对应的动作
  ShortcutAction? findAction(Set<LogicalKeyboardKey> pressedKeys) {
    for (final binding in state.bindings) {
      final keys = binding.keySet.triggers.toSet();
      if (keys.isNotEmpty && keys.every((k) => pressedKeys.contains(k))) {
        return binding.action;
      }
    }
    return null;
  }
}

/// 快捷键设置Provider
final shortcutProvider =
    StateNotifierProvider<ShortcutNotifier, ShortcutSettings>(
      (ref) => ShortcutNotifier(),
    );
