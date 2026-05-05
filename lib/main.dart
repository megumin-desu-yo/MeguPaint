import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'services/input/native_pressure_service.dart';
import 'ui/screens/home/home_screen.dart';
import 'ui/screens/login/login_screen.dart';

/// 应用入口
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化Hive
  await Hive.initFlutter();

  // 尽早初始化原生压感服务，确保 EventChannel 在画布打开前已连接
  NativePressureService.instance.isSupported();

  runApp(const ProviderScope(child: MeguPaintApp()));
}

/// MeguPaint应用
class MeguPaintApp extends ConsumerWidget {
  const MeguPaintApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'MeguPaint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: settings.currentLocale,
      home: _FirstLaunchGate(
        child: authState.isLoggedIn
            ? const HomeScreen()
            : authState.isInitialized
            ? const LoginScreen()
            : const SplashScreen(),
      ),
    );
  }
}

class _FirstLaunchGate extends StatefulWidget {
  final Widget child;

  const _FirstLaunchGate({required this.child});

  @override
  State<_FirstLaunchGate> createState() => _FirstLaunchGateState();
}

class _FirstLaunchGateState extends State<_FirstLaunchGate> {
  static const String _prefsKey = 'first_launch_permission_asked';
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final asked = prefs.getBool(_prefsKey) ?? false;
      if (!asked && mounted) {
        final confirmed = await _showPermissionGuideDialog();
        await prefs.setBool(_prefsKey, true);
        if (confirmed && mounted) {
          await _requestAndroidStoragePermissions();
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isReady = true;
    });
  }

  Future<bool> _showPermissionGuideDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('权限申请'),
          content: const Text(
            '为了导入/导出作品，应用需要访问存储空间。\n\n'
            '你可以在系统设置中随时修改授权。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('去授权'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _requestAndroidStoragePermissions() async {
    final permissions = <Permission>[Permission.photos, Permission.storage];

    for (final p in permissions) {
      final status = await p.status;
      if (status.isGranted) continue;

      final next = await p.request();
      if (next.isPermanentlyDenied && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('需要手动开启权限'),
              content: const Text('你已选择“不再询问”。请到系统设置中为 MeguPaint 开启存储权限。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
                FilledButton(
                  onPressed: () {
                    openAppSettings();
                    Navigator.of(context).pop();
                  },
                  child: const Text('打开设置'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const SplashScreen();
    }
    return widget.child;
  }
}

/// 启动屏 (等待初始化)
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.palette,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
