import 'package:flutter/material.dart';

/// 画布工具枚举
enum CanvasTool {
  brush,
  eraser,
  eyedropper,
  move,
  select,
  rectangle,
  circle,
  line,
  fill,
  edgeFill,
  text,
}

/// CanvasTool 扩展方法
extension CanvasToolExtension on CanvasTool {
  /// 获取工具对应的图标
  IconData get icon {
    switch (this) {
      case CanvasTool.brush:
        return Icons.brush;
      case CanvasTool.eraser:
        return Icons.delete_outline;
      case CanvasTool.eyedropper:
        return Icons.colorize;
      case CanvasTool.move:
        return Icons.pan_tool;
      case CanvasTool.select:
        return Icons.near_me;
      case CanvasTool.rectangle:
        return Icons.rectangle_outlined;
      case CanvasTool.circle:
        return Icons.circle_outlined;
      case CanvasTool.line:
        return Icons.horizontal_rule;
      case CanvasTool.fill:
        return Icons.format_paint;
      case CanvasTool.edgeFill:
        return Icons.border_outer;
      case CanvasTool.text:
        return Icons.text_fields;
    }
  }
}
