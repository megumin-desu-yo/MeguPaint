import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../presentation/providers/drawing_provider.dart';
import '../../presentation/providers/settings_provider.dart';
import '../../presentation/providers/shortcut_provider.dart';
import 'pressure_curve_editor.dart';

/// 绘画设置对话框（左右分栏布局）
class DrawingSettingsDialog extends ConsumerStatefulWidget {
  final AppLocalizations l10n;

  const DrawingSettingsDialog({super.key, required this.l10n});

  @override
  ConsumerState<DrawingSettingsDialog> createState() =>
      _DrawingSettingsDialogState();
}

class _DrawingSettingsDialogState extends ConsumerState<DrawingSettingsDialog> {
  int _selectedCategoryIndex = 0;

  final List<_SettingsCategory> _categories = [
    _SettingsCategory(icon: Icons.brush, key: 'brush'),
    _SettingsCategory(icon: Icons.palette, key: 'color'),
    _SettingsCategory(icon: Icons.layers, key: 'layers'),
    _SettingsCategory(icon: Icons.keyboard, key: 'shortcuts'),
    _SettingsCategory(icon: Icons.tune, key: 'advanced'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700,
        height: 600,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    widget.l10n.translate('drawing_settings'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  // 还原默认按钮
                  TextButton.icon(
                    onPressed: _resetToDefaults,
                    icon: const Icon(Icons.restore, size: 18),
                    label: Text(widget.l10n.translate('reset_defaults')),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    iconSize: 20,
                  ),
                ],
              ),
            ),
            // 内容区域（左右分栏）
            Expanded(
              child: Row(
                children: [
                  // 左侧选项栏
                  Container(
                    width: 120,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: ListView.builder(
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final isSelected = _selectedCategoryIndex == index;
                        return _buildCategoryItem(category, index, isSelected);
                      },
                    ),
                  ),
                  // 右侧功能区域
                  Expanded(child: _buildSettingsContent()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建左侧选项项
  Widget _buildCategoryItem(
    _SettingsCategory category,
    int index,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategoryIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
        ),
        child: Row(
          children: [
            Icon(
              category.icon,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.l10n.translate('settings_${category.key}'),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建右侧功能内容
  Widget _buildSettingsContent() {
    switch (_selectedCategoryIndex) {
      case 0: // 笔刷设置
        return _buildBrushSettings();
      case 1: // 颜色设置
        return _buildColorSettings();
      case 2: // 图层设置
        return _buildLayerSettings();
      case 3: // 快捷键设置
        return _buildShortcutsSettings();
      case 4: // 高级设置
        return _buildAdvancedSettings();
      default:
        return const Center(child: Text('Unknown'));
    }
  }

  /// 笔刷设置
  Widget _buildBrushSettings() {
    final brush = ref.watch(brushProvider).settings;
    final curveExp = ref.watch(brushSizeCurveExponentProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.l10n.translate('settings_brush'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),

          // 粗细非线性程度
          Row(
            children: [
              Text('粗细非线性程度'),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  curveExp.toStringAsFixed(1),
                  textAlign: TextAlign.end,
                ),
              ),
              Slider(
                value: curveExp.clamp(1.0, 10.0),
                min: 1.0,
                max: 10.0,
                onChanged: (v) {
                  ref.read(brushSizeCurveExponentProvider.notifier).state = v;
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '值越大，小粗细范围调节越精细',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // === 压感开关 ===
          Row(
            children: [
              Text(
                widget.l10n.translate('pressure_enabled'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Switch(
                value: brush.pressureEnabled,
                onChanged: (v) {
                  ref.read(drawingProvider.notifier).setPressureEnabled(v);
                  ref.read(brushProvider.notifier).setPressureEnabled(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // === 压感平滑设置 ===
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.l10n.translate('pressure_smoothing'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  Switch(
                    value: ref.watch(settingsProvider).pressureSmoothing,
                    onChanged: (v) {
                      ref
                          .read(settingsProvider.notifier)
                          .setPressureSmoothing(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.l10n.translate('pressure_smoothing_description'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // === 平滑因子滑条（关闭时灰色禁用）===
              Opacity(
                opacity: ref.watch(settingsProvider).pressureSmoothing
                    ? 1.0
                    : 0.4,
                child: IgnorePointer(
                  ignoring: !ref.watch(settingsProvider).pressureSmoothing,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.l10n.translate('smoothing_factor'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          Text(
                            ref
                                .watch(settingsProvider)
                                .pressureSmoothingFactor
                                .toStringAsFixed(2),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: ref
                            .watch(settingsProvider)
                            .pressureSmoothingFactor,
                        min: 0.1,
                        max: 0.9,
                        divisions: 8,
                        onChanged: (v) {
                          ref
                              .read(settingsProvider.notifier)
                              .setPressureSmoothingFactor(v);
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.l10n.translate('smoothing_factor_description'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // === 起笔压感抬升 ===
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.l10n.translate('pressure_start_ramp'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  Switch(
                    value: ref.watch(settingsProvider).pressureStartRamp,
                    onChanged: (v) {
                      ref
                          .read(settingsProvider.notifier)
                          .setPressureStartRamp(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.l10n.translate('pressure_start_ramp_description'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              // === 起笔抬升强度滑条（关闭时灰色禁用）===
              Opacity(
                opacity: ref.watch(settingsProvider).pressureStartRamp
                    ? 1.0
                    : 0.4,
                child: IgnorePointer(
                  ignoring: !ref.watch(settingsProvider).pressureStartRamp,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.l10n.translate(
                              'pressure_start_ramp_strength',
                            ),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          Text(
                            ref
                                .watch(settingsProvider)
                                .pressureStartRampStrength
                                .toStringAsFixed(2),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: ref
                            .watch(settingsProvider)
                            .pressureStartRampStrength,
                        min: 0.0,
                        max: 1.0,
                        divisions: 10,
                        onChanged: (v) {
                          ref
                              .read(settingsProvider.notifier)
                              .setPressureStartRampStrength(v);
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.l10n.translate(
                          'pressure_start_ramp_strength_description',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // === 压感曲线设置（关闭时灰色禁用）===
          Opacity(
            opacity: brush.pressureEnabled ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: !brush.pressureEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.l10n.translate('pressure_curve'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.l10n.translate('pressure_curve_desc'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 压感曲线编辑器
                  PressureCurveEditor(
                    controlPoints: brush.pressureCurve
                        .map((p) => PressureControlPoint(x: p.x, y: p.y))
                        .toList(),
                    onCurveChanged: (points) {
                      final curvePoints = points
                          .map((p) => PressureCurvePoint(x: p.x, y: p.y))
                          .toList();
                      ref
                          .read(drawingProvider.notifier)
                          .setPressureCurve(curvePoints);
                      ref
                          .read(brushProvider.notifier)
                          .setPressureCurve(curvePoints);
                    },
                    onReset: () {
                      const defaultCurve = [
                        PressureCurvePoint(x: 0.0, y: 0.0),
                        PressureCurvePoint(x: 1.0, y: 1.0),
                      ];
                      ref
                          .read(drawingProvider.notifier)
                          .setPressureCurve(defaultCurve);
                      ref
                          .read(brushProvider.notifier)
                          .setPressureCurve(defaultCurve);
                    },
                    size: const Size(220, 180),
                  ),
                  const SizedBox(height: 16),

                  // 压感测试区域
                  PressureTestArea(
                    controlPoints: brush.pressureCurve
                        .map((p) => PressureControlPoint(x: p.x, y: p.y))
                        .toList(),
                    height: 60,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 颜色设置
  Widget _buildColorSettings() {
    final brush = ref.watch(brushProvider).settings;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.l10n.translate('settings_color'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          // 预设颜色
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                      Colors.black,
                      Colors.white,
                      Colors.red,
                      Colors.orange,
                      Colors.yellow,
                      Colors.green,
                      Colors.blue,
                      Colors.purple,
                      Colors.pink,
                      Colors.brown,
                      Colors.grey,
                    ]
                    .map(
                      (c) => GestureDetector(
                        onTap: () {
                          // 同时更新两个 provider
                          ref.read(drawingProvider.notifier).setColor(c);
                          ref.read(brushProvider.notifier).setColor(c);
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            border: Border.all(
                              color: brush.color == c
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                              width: brush.color == c ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  /// 图层设置
  Widget _buildLayerSettings() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.l10n.translate('settings_layers'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text(widget.l10n.translate('layer_settings_placeholder')),
        ],
      ),
    );
  }

  /// 快捷键设置
  Widget _buildShortcutsSettings() {
    final shortcuts = ref.watch(shortcutProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.l10n.translate('settings_shortcuts'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '点击快捷键区域后按下新的按键组合来自定义',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: shortcuts.bindings.length,
              itemBuilder: (context, index) {
                final binding = shortcuts.bindings[index];
                return _ShortcutBindingTile(
                  binding: binding,
                  onReset: () => ref.read(shortcutProvider.notifier).reset(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 高级设置：目前仅指向笔刷面板，避免与笔刷面板重复
  Widget _buildAdvancedSettings() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.l10n.translate('settings_advanced'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            widget.l10n.translate('advanced_settings_desc'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.l10n.translate('stroke_optimization'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            widget.l10n.translate('stroke_optimization_redirect'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  /// 还原默认设置
  void _resetToDefaults() {
    ref.read(drawingProvider.notifier).updateBrush(const BrushSettings());
    ref.read(brushProvider.notifier).updateBrush(const BrushSettings());
  }
}

/// 设置分类
class _SettingsCategory {
  final IconData icon;
  final String key;

  const _SettingsCategory({required this.icon, required this.key});
}

/// 快捷键绑定项组件
class _ShortcutBindingTile extends ConsumerStatefulWidget {
  final ShortcutBinding binding;
  final VoidCallback onReset;

  const _ShortcutBindingTile({required this.binding, required this.onReset});

  @override
  ConsumerState<_ShortcutBindingTile> createState() =>
      _ShortcutBindingTileState();
}

class _ShortcutBindingTileState extends ConsumerState<_ShortcutBindingTile> {
  bool _isEditing = false;
  int _editingIndex = -1; // 当前编辑的按键索引
  String? _conflictMessage;
  late List<LogicalKeyboardKey> _keys; // 当前按键列表

  @override
  void initState() {
    super.initState();
    _keys = widget.binding.keySet.triggers.toList();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 标签
          SizedBox(width: 80, child: Text(widget.binding.label)),
          const SizedBox(width: 16),
          // 按键框列表
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                ..._buildKeyBoxes(),
                // 添加按钮
                if (!_isEditing && _keys.length < 4) _buildAddButton(),
              ],
            ),
          ),
          // 删除按钮（有多个键时显示，编辑状态也显示）
          if (_keys.length > 1)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: _removeLastKey,
              tooltip: '移除最后一个按键',
            ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return SizedBox(
      width: 56,
      height: 32,
      child: InkWell(
        onTap: _addKeySlot,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.5),
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.add,
            size: 16,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildKeyBoxes() {
    final widgets = <Widget>[];
    for (int i = 0; i < _keys.length; i++) {
      // 添加 + 号（非第一个）
      if (i > 0) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('+', style: Theme.of(context).textTheme.bodySmall),
          ),
        );
      }
      widgets.add(_buildKeyBox(i));
    }
    return widgets;
  }

  Widget _buildKeyBox(int index) {
    final isEditingThis = _isEditing && _editingIndex == index;
    final key = _keys[index];

    return SizedBox(
      width: 56,
      height: 32,
      child: InkWell(
        onTap: () => _startEditing(index),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isEditingThis
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            border: Border.all(
              color: _conflictMessage != null
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).dividerColor,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: isEditingThis
              ? const Text('按下按键...', style: TextStyle(fontSize: 10))
              : Text(_formatKey(key), style: const TextStyle(fontSize: 11)),
        ),
      ),
    );
  }

  void _startEditing(int index) {
    setState(() {
      _isEditing = true;
      _editingIndex = index;
      _conflictMessage = null;
    });
  }

  void _addKeySlot() {
    setState(() {
      _keys.add(LogicalKeyboardKey.keyA); // 占位符
      _isEditing = true;
      _editingIndex = _keys.length - 1;
      _conflictMessage = null;
    });
  }

  void _removeLastKey() {
    if (_keys.length > 1) {
      setState(() {
        _keys.removeLast();
        _saveKeys();
      });
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_isEditing) return false;
    if (event is! KeyDownEvent) return true;

    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;

    // Escape 取消编辑
    if (pressedKeys.contains(LogicalKeyboardKey.escape)) {
      setState(() {
        _isEditing = false;
        _editingIndex = -1;
        // 如果是新增的占位符，移除它
        if (_keys.isNotEmpty && _keys.last == LogicalKeyboardKey.keyA) {
          _keys.removeLast();
        }
      });
      return true;
    }

    // 获取按下的单个键（排除修饰键的组合）
    final newKey = _getSingleKey(pressedKeys);
    if (newKey == null) return true;

    // 更新指定位置的键
    setState(() {
      _keys[_editingIndex] = newKey;
      _isEditing = false;
      _editingIndex = -1;
      _saveKeys();
    });

    return true;
  }

  LogicalKeyboardKey? _getSingleKey(Set<LogicalKeyboardKey> pressedKeys) {
    // 过滤掉当前编辑位置的键
    final otherKeys = _keys
        .asMap()
        .entries
        .where((e) => e.key != _editingIndex)
        .map((e) => e.value)
        .toSet();

    for (final key in pressedKeys) {
      if (!otherKeys.contains(key)) {
        return key;
      }
    }
    return null;
  }

  void _saveKeys() {
    if (_keys.isEmpty) return;

    final keySet = LogicalKeySet.fromSet(_keys.toSet());
    final displayText = _keys.map(_formatKey).join('+');

    // 检查冲突
    final shortcuts = ref.read(shortcutProvider);
    final conflict = shortcuts.checkConflict(keySet, widget.binding.action);

    if (conflict != null) {
      setState(() {
        _conflictMessage = '与 "${_getActionLabel(conflict)}" 冲突';
      });
      return;
    }

    ref
        .read(shortcutProvider.notifier)
        .updateBinding(widget.binding.action, keySet, displayText);
    _conflictMessage = null;
  }

  String _formatKey(LogicalKeyboardKey key) {
    final name = key.keyLabel;

    // 区分左右 Ctrl
    if (key == LogicalKeyboardKey.controlLeft) return 'Ctrl(L)';
    if (key == LogicalKeyboardKey.controlRight) return 'Ctrl(R)';
    if (key == LogicalKeyboardKey.shiftLeft) return 'Shift(L)';
    if (key == LogicalKeyboardKey.shiftRight) return 'Shift(R)';
    if (key == LogicalKeyboardKey.altLeft) return 'Alt(L)';
    if (key == LogicalKeyboardKey.altRight) return 'Alt(R)';

    // 通用 Ctrl/Shift/Alt（兼容旧数据）
    if (name == 'Control') return 'Ctrl';
    if (name == 'Shift') return 'Shift';
    if (name == 'Alt') return 'Alt';

    // 字母键
    if (name.startsWith('Key ') && name.length > 4) {
      return name.substring(4);
    }

    return name;
  }

  String _getActionLabel(ShortcutAction action) {
    switch (action) {
      case ShortcutAction.brush:
        return '笔刷';
      case ShortcutAction.eraser:
        return '橡皮擦';
      case ShortcutAction.eyedropper:
        return '吸色管';
      case ShortcutAction.move:
        return '移动';
      case ShortcutAction.undo:
        return '撤回';
      case ShortcutAction.redo:
        return '反撤回';
      case ShortcutAction.rectangle:
        return '矩形';
      case ShortcutAction.circle:
        return '圆形';
      case ShortcutAction.line:
        return '直线';
      case ShortcutAction.fill:
        return '填充';
      case ShortcutAction.text:
        return '文字';
    }
  }
}

/// 竖向圆矩形滑条组件
class VerticalSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final IconData icon;
  final String label;
  final String? displayText;
  final ValueChanged<double> onChanged;

  const VerticalSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.icon,
    required this.label,
    this.displayText,
    required this.onChanged,
  });

  @override
  State<VerticalSlider> createState() => _VerticalSliderState();
}

class _VerticalSliderState extends State<VerticalSlider> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = widget.displayText ?? widget.value.toStringAsFixed(1);

    return Container(
      width: 32,
      height: 160,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 图标
          Icon(widget.icon, size: 16, color: theme.colorScheme.onSurface),
          const SizedBox(height: 4),
          // 竖向滑条
          Expanded(
            child: RotatedBox(
              quarterTurns: 3, // 逆时针旋转90度，使横向滑条变为竖向
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: theme.colorScheme.surfaceContainerHigh,
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: widget.value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  onChanged: (v) {
                    setState(() => _isDragging = true);
                    widget.onChanged(v);
                  },
                  onChangeEnd: (_) => setState(() => _isDragging = false),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 数值显示
          Text(
            displayText,
            style: TextStyle(
              fontSize: 9,
              fontWeight: _isDragging ? FontWeight.bold : FontWeight.normal,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
