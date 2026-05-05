import 'package:flutter/material.dart';

/// 应用配色方案
class AppColorSchemes {
  AppColorSchemes._();

  // 主色调
  static const Color primarySeed = Color(0xFF6750A4);

  // 工具栏颜色
  static const Color toolbarBackground = Color(0xFF3C3C3C);
  static const Color toolbarForeground = Colors.white;
  static const Color toolbarAccent = Color(0xFF0078D4);

  // 图层颜色标识
  static const List<Color> layerColors = [
    Color(0xFFFF6B6B),
    Color(0xFFFFB347),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFF9B59B6),
    Color(0xFFE056FD),
    Color(0xFF00D9FF),
  ];

  // 选区颜色
  static const Color selectionBorder = Color(0xFF00A8FF);
  static const Color selectionFill = Color(0x4000A8FF);

  // 参考线颜色
  static const Color guideLine = Color(0xFFFF00FF);
  static const Color gridLine = Color(0x40808080);
}
