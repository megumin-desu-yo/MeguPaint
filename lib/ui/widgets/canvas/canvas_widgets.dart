import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/brush/brush_preset.dart' show BrushEngineType;
import '../../../domain/brush/default_presets.dart';
import '../../../presentation/providers/drawing_provider.dart'
    show brushPresetProvider, brushProvider, drawingProvider;

/// 放大镜像素网格绘制器
class MagnifierGridPainter extends CustomPainter {
  final List<List<Color>> pixels;
  final double pixelSize;
  final int centerIndex;

  MagnifierGridPainter({
    required this.pixels,
    required this.pixelSize,
    required this.centerIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final gridPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int y = 0; y < pixels.length; y++) {
      for (int x = 0; x < pixels[y].length; x++) {
        final rect = Rect.fromLTWH(
          x * pixelSize,
          y * pixelSize,
          pixelSize,
          pixelSize,
        );
        paint.color = pixels[y][x];
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect, gridPaint);
      }
    }

    // 绘制中心十字线标记
    final centerX = centerIndex * pixelSize + pixelSize / 2;
    final centerY = centerIndex * pixelSize + pixelSize / 2;
    final crossPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(centerX - pixelSize / 2, centerY),
      Offset(centerX + pixelSize / 2, centerY),
      crossPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - pixelSize / 2),
      Offset(centerX, centerY + pixelSize / 2),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant MagnifierGridPainter oldDelegate) {
    return pixels != oldDelegate.pixels ||
        pixelSize != oldDelegate.pixelSize ||
        centerIndex != oldDelegate.centerIndex;
  }
}

/// 放大镜预览组件
class MagnifierWidget extends StatelessWidget {
  final int gridSize;
  final List<List<Color>> pixels;
  final Color previewColor;

  const MagnifierWidget({
    super.key,
    required this.gridSize,
    required this.pixels,
    required this.previewColor,
  });

  @override
  Widget build(BuildContext context) {
    const pixelSize = 14.0;
    final magnifierSize = pixelSize * gridSize;
    const borderWidth = 2.0;
    const innerPadding = 4.0;

    return Container(
      width: magnifierSize + innerPadding * 2 + borderWidth * 2,
      height: magnifierSize + innerPadding * 2 + 26,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 像素网格预览区
          Container(
            width: magnifierSize,
            height: magnifierSize,
            margin: const EdgeInsets.all(innerPadding),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
            child: pixels.isEmpty
                ? Container(color: previewColor)
                : CustomPaint(
                    painter: MagnifierGridPainter(
                      pixels: pixels,
                      pixelSize: pixelSize,
                      centerIndex: gridSize ~/ 2,
                    ),
                    size: Size(magnifierSize, magnifierSize),
                  ),
          ),
          // HEX 颜色值
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              '#${previewColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 工具按钮组件
class ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;
  final Widget? menuContent;

  const ToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
    this.menuContent,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isActive ? Theme.of(context).colorScheme.primaryContainer : null,
      ),
      child: IconButton(icon: Icon(icon), onPressed: onTap),
    );

    if (menuContent != null) {
      return Tooltip(
        message: tooltip,
        child: MenuAnchor(
          builder: (context, controller, _) {
            return child;
          },
          menuChildren: [menuContent!],
          alignmentOffset: const Offset(4, 0),
        ),
      );
    }

    return Tooltip(message: tooltip, child: child);
  }
}

/// 笔刷菜单项组件
class BrushMenuItems extends ConsumerStatefulWidget {
  final Map<BrushEngineType, ({String name, IconData icon})> engineMeta;

  const BrushMenuItems({super.key, required this.engineMeta});

  @override
  ConsumerState<BrushMenuItems> createState() => _BrushMenuItemsState();
}

class _BrushMenuItemsState extends ConsumerState<BrushMenuItems> {
  late ProviderContainer _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    final presetState = ref.watch(brushPresetProvider);
    final currentPreset = presetState.currentPreset;
    final allPresets = DefaultPresets.all;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('画笔预设', style: Theme.of(context).textTheme.labelSmall),
        ),
        const Divider(height: 1),
        // 预设列表
        ...allPresets.map((preset) {
          final isSelected = preset.id == currentPreset.id;
          final meta = widget.engineMeta[preset.engineType];
          return MenuItemButton(
            leadingIcon: Icon(
              meta?.icon ?? Icons.brush,
              size: 18,
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
            trailingIcon: isSelected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onPressed: () {
              _container
                  .read(brushPresetProvider.notifier)
                  .selectPreset(preset.id);
              _container.read(drawingProvider.notifier).setColor(preset.color);
              _container
                  .read(drawingProvider.notifier)
                  .setWidth(preset.baseSize);
              _container
                  .read(drawingProvider.notifier)
                  .setOpacity(preset.baseOpacity);
              _container
                  .read(drawingProvider.notifier)
                  .setStabilization(preset.stabilization);
              _container
                  .read(drawingProvider.notifier)
                  .setPressureEnabled(preset.pressureEnabled);
              _container
                  .read(drawingProvider.notifier)
                  .setSmoothEnabled(preset.smoothEnabled);

              _container.read(brushProvider.notifier).setColor(preset.color);
              _container.read(brushProvider.notifier).setWidth(preset.baseSize);
              _container
                  .read(brushProvider.notifier)
                  .setOpacity(preset.baseOpacity);
              _container
                  .read(brushProvider.notifier)
                  .setStabilization(preset.stabilization);
              _container
                  .read(brushProvider.notifier)
                  .setPressureEnabled(preset.pressureEnabled);
              _container
                  .read(brushProvider.notifier)
                  .setSmoothEnabled(preset.smoothEnabled);
            },
            child: Text(preset.name),
          );
        }),
      ],
    );
  }
}
