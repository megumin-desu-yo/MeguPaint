import 'package:flutter/material.dart';
import 'color_schemes.dart';

/// 应用主题配置
class AppTheme {
  AppTheme._();

  // 亮色主题
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColorSchemes.primarySeed,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
    ),
    // 绘画软件使用深色工具栏
    scaffoldBackgroundColor: Colors.grey[100],
  );

  // 暗色主题
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColorSchemes.primarySeed,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
    ),
    scaffoldBackgroundColor: const Color(0xFF1E1E1E),
  );

  // 画布主题（深色背景）
  static const Color canvasBackgroundColor = Color(0xFF2D2D2D);
  static const Color canvasCheckerColor1 = Color(0xFF404040);
  static const Color canvasCheckerColor2 = Color(0xFF4A4A4A);
}
