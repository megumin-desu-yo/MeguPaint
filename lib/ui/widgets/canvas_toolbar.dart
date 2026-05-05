import 'package:flutter/material.dart';
import '../../domain/canvas_tool.dart';
import '../../l10n/app_localizations.dart';

/// 画布工具栏组件
class CanvasToolbar extends StatelessWidget {
  final CanvasTool currentTool;
  final void Function(CanvasTool tool) onToolSelected;
  final AppLocalizations l10n;
  final bool isCollapsed;
  final Widget? brushMenuItems;

  const CanvasToolbar({
    super.key,
    required this.currentTool,
    required this.onToolSelected,
    required this.l10n,
    this.isCollapsed = false,
    this.brushMenuItems,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      left: isCollapsed ? -48 : 0,
      top: 0,
      bottom: 0,
      width: 48,
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildToolButton(
                context,
                Icons.brush,
                l10n.translate('tool_brush'),
                CanvasTool.brush,
                isBrush: true,
              ),
              _buildToolButton(
                context,
                Icons.delete_outline,
                l10n.translate('tool_eraser'),
                CanvasTool.eraser,
              ),
              _buildToolButton(
                context,
                Icons.colorize,
                l10n.translate('tool_eyedropper'),
                CanvasTool.eyedropper,
              ),
              _buildToolButton(
                context,
                Icons.pan_tool,
                l10n.translate('tool_move'),
                CanvasTool.move,
              ),
              _buildToolButton(
                context,
                Icons.near_me,
                l10n.translate('tool_select'),
                CanvasTool.select,
              ),
              const Divider(),
              _buildToolButton(
                context,
                Icons.rectangle_outlined,
                l10n.translate('tool_rectangle'),
                CanvasTool.rectangle,
              ),
              _buildToolButton(
                context,
                Icons.circle_outlined,
                l10n.translate('tool_circle'),
                CanvasTool.circle,
              ),
              _buildToolButton(
                context,
                Icons.horizontal_rule,
                l10n.translate('tool_line'),
                CanvasTool.line,
              ),
              const Divider(),
              _buildToolButton(
                context,
                Icons.format_paint,
                l10n.translate('tool_fill'),
                CanvasTool.fill,
              ),
              _buildToolButton(
                context,
                Icons.border_outer,
                l10n.translate('tool_edge_fill'),
                CanvasTool.edgeFill,
              ),
              _buildToolButton(
                context,
                Icons.text_fields,
                l10n.translate('tool_text'),
                CanvasTool.text,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    CanvasTool tool, {
    bool isBrush = false,
  }) {
    final isActive = currentTool == tool;

    // 笔刷按钮使用 MenuAnchor
    if (isBrush && brushMenuItems != null) {
      return Tooltip(
        message: tooltip,
        child: MenuAnchor(
          builder: (context, controller, child) {
            return Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              child: IconButton(
                icon: Icon(icon),
                onPressed: () {
                  onToolSelected(tool);
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
              ),
            );
          },
          menuChildren: [brushMenuItems!],
          alignmentOffset: const Offset(4, 0),
        ),
      );
    }

    // 其他工具按钮
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
        ),
        child: IconButton(
          icon: Icon(icon),
          onPressed: () => onToolSelected(tool),
        ),
      ),
    );
  }
}
