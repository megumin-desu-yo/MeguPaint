import 'dart:async';
import 'dart:io';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;

/// 开发模式下的热更新服务器包装器
/// 监听 service/lib 和 service/bin 目录下的文件变化并自动重启 server.dart
void main() async {
  final rootDir = Directory.current.path;
  final binDir = p.join(rootDir, 'bin');
  final libDir = p.join(rootDir, 'lib');
  final configDir = p.join(rootDir, 'config');
  final serverScript = p.join(binDir, 'server.dart');

  Process? currentProcess;
  Timer? debounceTimer;

  print('[热更新] 正在启动监视器...');
  print('[热更新] 监听目录: $libDir, $binDir, $configDir');

  void startServer() async {
    if (currentProcess != null) {
      print('[热更新] 正在停止旧进程 (PID: ${currentProcess!.pid})...');
      currentProcess!.kill();
      await currentProcess!.exitCode;
      currentProcess = null;
    }

    print('[热更新] 正在启动服务器: $serverScript');
    currentProcess = await Process.start(
      'dart',
      ['run', serverScript],
      mode: ProcessStartMode.inheritStdio,
    );

    currentProcess!.exitCode.then((code) {
      if (currentProcess != null) {
        print('[热更新] 服务器进程已退出，退出码: $code');
      }
    });
  }

  void handleEvent(WatchEvent event) {
    // 允许监听 .dart 和 .json 文件
    final ext = p.extension(event.path);
    if (ext != '.dart' && ext != '.json') return;

    print('[热更新] 检测到变化: ${event.type} ${event.path}');

    // 防抖处理：避免短时间内多次保存触发多次重启
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 500), () {
      print('[热更新] 准备重启...');
      startServer();
    });
  }

  // 初始启动
  startServer();

  // 监听 lib 目录
  final libWatcher = DirectoryWatcher(libDir);
  libWatcher.events.listen(handleEvent);

  // 监听 bin 目录
  final binWatcher = DirectoryWatcher(binDir);
  binWatcher.events.listen(handleEvent);

  // 监听 config 目录
  if (Directory(configDir).existsSync()) {
    final configWatcher = DirectoryWatcher(configDir);
    configWatcher.events.listen(handleEvent);
  }

  print('[热更新] 已就绪。按 Ctrl+C 停止。');
}
