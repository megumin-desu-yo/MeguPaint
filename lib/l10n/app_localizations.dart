import 'package:flutter/material.dart';
import 'translations/zh_cn.dart';
import 'translations/en_us.dart';
import 'translations/ja_jp.dart';
import 'translations/zh_tw.dart';

/// 多语言管理类
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  /// 获取当前语言的翻译映射
  Map<String, String> get _localizedStrings {
    switch (locale.toString()) {
      case 'zh_CN':
        return zhCN;
      case 'en_US':
        return enUS;
      case 'ja_JP':
        return jaJP;
      case 'zh_TW':
        return zhTW;
      default:
        return zhCN; // 默认简体中文
    }
  }

  /// 获取翻译文本
  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }

  /// 静态方法：从 BuildContext 获取实例
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  /// 支持的语言列表
  static const List<Locale> supportedLocales = [
    Locale('zh', 'CN'),
    Locale('en', 'US'),
    Locale('ja', 'JP'),
    Locale('zh', 'TW'),
  ];

  /// 语言显示名称映射
  static const Map<String, String> languageNames = {
    'zh_CN': '简体中文',
    'en_US': 'English',
    'ja_JP': '日本語',
    'zh_TW': '繁體中文',
  };
}

/// LocalizationsDelegate 实现
class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['zh', 'en', 'ja'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(LocalizationsDelegate<AppLocalizations> old) => false;
}
