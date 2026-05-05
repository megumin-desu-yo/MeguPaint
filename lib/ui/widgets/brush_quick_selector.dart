import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/brush/brush_preset.dart';
import '../../domain/brush/default_presets.dart';
import '../../presentation/providers/drawing_provider.dart';

/// 笔刷引擎类型的显示名称和图标
const Map<BrushEngineType, ({String name, IconData icon})> _engineMeta = {
  BrushEngineType.round: (name: '圆形', icon: Icons.circle),
  BrushEngineType.pencil: (name: '铅笔', icon: Icons.edit),
  BrushEngineType.airbrush: (name: '喷枪', icon: Icons.blur_on),
  BrushEngineType.marker: (name: '马克笔', icon: Icons.format_color_fill),
  BrushEngineType.ink: (name: '墨水', icon: Icons.brush),
};

/// 笔刷快捷选择弹出窗口
/// 紧贴左侧工具栏，竖向排列预设画笔
class BrushQuickSelector extends ConsumerWidget {
  final VoidCallback? onDismiss;

  const BrushQuickSelector({super.key, this.onDismiss});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetState = ref.watch(brushPresetProvider);
    final currentPreset = presetState.currentPreset;
    final allPresets = DefaultPresets.all;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '画笔预设',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const Divider(height: 8),
            // 预设列表
            ...allPresets.map((preset) {
              final isSelected = preset.id == currentPreset.id;
              final meta = _engineMeta[preset.engineType];
              return _BrushPresetItem(
                preset: preset,
                isSelected: isSelected,
                icon: meta?.icon ?? Icons.brush,
                onTap: () {
                  ref
                      .read(brushPresetProvider.notifier)
                      .selectPreset(preset.id);
                  // 同步颜色到旧 provider
                  ref.read(drawingProvider.notifier).setColor(preset.color);
                  // 选择后关闭弹出窗口
                  onDismiss?.call();
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// 笔刷预设项
class _BrushPresetItem extends StatelessWidget {
  final BrushPreset preset;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  const _BrushPresetItem({
    required this.preset,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // 图标
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              // 名称
              Expanded(
                child: Text(
                  preset.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 显示笔刷快捷选择弹出窗口
/// 返回一个 OverlayEntry，调用者负责移除
OverlayEntry showBrushQuickSelector({
  required BuildContext context,
  required Offset buttonPosition,
  required double toolbarWidth,
}) {
  late OverlayEntry entry;

  entry = OverlayEntry(
    maintainState: true,
    builder: (ctx) => _BrushQuickSelectorOverlay(
      buttonPosition: buttonPosition,
      toolbarWidth: toolbarWidth,
      onDismiss: () {
        // 检查 entry 是否仍然 mounted
        if (entry.mounted) {
          entry.remove();
        }
      },
    ),
  );

  // 使用 rootOverlay: true 确保获取根 Overlay
  final overlayState = Overlay.of(context, rootOverlay: true);
  overlayState.insert(entry);
  return entry;
}

/// 笔刷快捷选择弹出窗口的 Overlay 包装
class _BrushQuickSelectorOverlay extends StatelessWidget {
  final Offset buttonPosition;
  final double toolbarWidth;
  final VoidCallback onDismiss;

  const _BrushQuickSelectorOverlay({
    required this.buttonPosition,
    required this.toolbarWidth,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // 计算弹出窗口位置：紧贴左侧工具栏右侧
    final left = toolbarWidth;
    final top = buttonPosition.dy;

    return Stack(
      children: [
        // 点击外部关闭
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        // 弹出窗口
        Positioned(
          left: left + 4, // 留一点间距
          top: top,
          child: BrushQuickSelector(onDismiss: onDismiss),
        ),
      ],
    );
  }
}
