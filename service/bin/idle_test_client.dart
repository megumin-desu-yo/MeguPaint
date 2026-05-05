import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  String host = '127.0.0.1';
  int port = 9500;
  int holdSeconds = 120;
  bool sendGarbage = false;
  int garbageBytesPerSecond = 0;
  int garbageBytesOnce = 0;

  String mode = 'hold';
  int durationSeconds = 30;
  int connections = 100;
  int concurrency = 50;
  int connectTimeoutMs = 2000;
  int minHoldMs = 50;
  int maxHoldMs = 200;
  int pauseAfterSeconds = 0;

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--host' && i + 1 < args.length) {
      host = args[++i];
    } else if (a == '--port' && i + 1 < args.length) {
      port = int.tryParse(args[++i]) ?? port;
    } else if (a == '--hold' && i + 1 < args.length) {
      holdSeconds = int.tryParse(args[++i]) ?? holdSeconds;
    } else if (a == '--mode' && i + 1 < args.length) {
      mode = args[++i];
    } else if (a == '--duration' && i + 1 < args.length) {
      durationSeconds = int.tryParse(args[++i]) ?? durationSeconds;
    } else if (a == '--connections' && i + 1 < args.length) {
      connections = int.tryParse(args[++i]) ?? connections;
    } else if (a == '--concurrency' && i + 1 < args.length) {
      concurrency = int.tryParse(args[++i]) ?? concurrency;
    } else if (a == '--connectTimeoutMs' && i + 1 < args.length) {
      connectTimeoutMs = int.tryParse(args[++i]) ?? connectTimeoutMs;
    } else if (a == '--minHoldMs' && i + 1 < args.length) {
      minHoldMs = int.tryParse(args[++i]) ?? minHoldMs;
    } else if (a == '--maxHoldMs' && i + 1 < args.length) {
      maxHoldMs = int.tryParse(args[++i]) ?? maxHoldMs;
    } else if (a == '--pauseAfter' && i + 1 < args.length) {
      pauseAfterSeconds = int.tryParse(args[++i]) ?? 0;
    } else if (a == '--garbage') {
      sendGarbage = true;
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        garbageBytesPerSecond = int.tryParse(args[++i]) ?? 0;
      }
    } else if (a == '--garbageOnce') {
      sendGarbage = true;
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        garbageBytesOnce = int.tryParse(args[++i]) ?? 0;
      } else {
        garbageBytesOnce = 256;
      }
    }
  }

  if (mode == 'hold') {
    final socket = await Socket.connect(host, port);
    socket.listen(
      (_) {},
      onError: (e) => stderr.writeln('socket error: $e'),
      onDone: () => stdout.writeln('socket done'),
      cancelOnError: true,
    );

    stdout.writeln(
        'connected to $host:$port, hold=${holdSeconds}s, garbage=$sendGarbage(perSec=$garbageBytesPerSecond, once=$garbageBytesOnce)');

    Timer? garbageTimer;
    if (sendGarbage && garbageBytesPerSecond > 0) {
      final rnd = Random();
      garbageTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        int bytes = (garbageBytesPerSecond / 10).ceil();
        bytes = max(1, min(bytes, 8192));
        final data = Uint8List(bytes);
        for (int i = 0; i < data.length; i++) {
          data[i] = rnd.nextInt(256);
        }
        socket.add(data);
      });
    }

    if (sendGarbage && garbageBytesOnce > 0) {
      final rnd = Random();
      final data = Uint8List(garbageBytesOnce.clamp(1, 1024 * 1024));
      for (int i = 0; i < data.length; i++) {
        data[i] = rnd.nextInt(256);
      }
      socket.add(data);
    }

    await Future<void>.delayed(Duration(seconds: holdSeconds));
    garbageTimer?.cancel();

    stdout.writeln('closing');
    await socket.close();
    return;
  }

  if (mode != 'storm') {
    stderr.writeln('unknown mode: $mode (use hold|storm)');
    exitCode = 2;
    return;
  }

  concurrency = max(1, concurrency);
  connections = max(1, connections);
  durationSeconds = max(1, durationSeconds);
  minHoldMs = max(0, minHoldMs);
  maxHoldMs = max(minHoldMs, maxHoldMs);

  final rnd = Random();
  final startedAt = DateTime.now();
  final endAt = startedAt.add(Duration(seconds: durationSeconds));

  int attempt = 0;
  int ok = 0;
  int failed = 0;
  int bytesSent = 0;
  int closed = 0;
  int alive = 0;
  final aliveSockets = <Socket>[];

  Future<void> oneConnection(int idx) async {
    final now = DateTime.now();
    if (now.isAfter(endAt)) return;
    if (attempt >= connections) return;
    attempt++;

    Socket? socket;
    try {
      socket = await Socket.connect(host, port)
          .timeout(Duration(milliseconds: connectTimeoutMs));
      ok++;
      alive++;

      if (sendGarbage && garbageBytesOnce > 0) {
        final n = garbageBytesOnce.clamp(1, 1024 * 1024);
        final data = Uint8List(n);
        for (int i = 0; i < data.length; i++) {
          data[i] = rnd.nextInt(256);
        }
        socket.add(data);
        bytesSent += n;
      }

      Timer? garbageTimer;
      if (sendGarbage && garbageBytesPerSecond > 0) {
        garbageTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          int bytes = (garbageBytesPerSecond / 10).ceil();
          bytes = max(1, min(bytes, 8192));
          final data = Uint8List(bytes);
          for (int i = 0; i < data.length; i++) {
            data[i] = rnd.nextInt(256);
          }
          socket?.add(data);
          bytesSent += bytes;
        });
      }

      final holdMs = (maxHoldMs <= minHoldMs)
          ? minHoldMs
          : (minHoldMs + rnd.nextInt(maxHoldMs - minHoldMs + 1));
      if (holdMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: holdMs));
      }

      garbageTimer?.cancel();

      if (pauseAfterSeconds > 0) {
        aliveSockets.add(socket);
      } else {
        await socket.close();
        closed++;
        alive--;
      }
    } catch (_) {
      failed++;
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  stdout.writeln(
      'storm $host:$port duration=${durationSeconds}s connections=$connections concurrency=$concurrency holdMs=[$minHoldMs,$maxHoldMs] garbage=$sendGarbage(perSec=$garbageBytesPerSecond, once=$garbageBytesOnce) pauseAfter=${pauseAfterSeconds}s');

  final progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    stdout.writeln(
        't=${elapsed}s attempt=$attempt ok=$ok failed=$failed closed=$closed alive=$alive bytesSent=$bytesSent');
  });

  try {
    while (DateTime.now().isBefore(endAt) && attempt < connections) {
      final remaining = connections - attempt;
      final batch = min(concurrency, remaining);
      final futures = <Future<void>>[];
      for (int i = 0; i < batch; i++) {
        futures.add(oneConnection(i));
      }
      await Future.wait(futures);
    }
  } finally {
    progressTimer.cancel();
  }

  if (pauseAfterSeconds > 0 && aliveSockets.isNotEmpty) {
    stdout.writeln(
        'storm phase done, holding ${aliveSockets.length} connections for ${pauseAfterSeconds}s — check /memory now');
    final holdTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      stdout.writeln(
          't=${elapsed}s [HOLD] alive=${aliveSockets.length} bytesSent=$bytesSent');
    });
    await Future<void>.delayed(Duration(seconds: pauseAfterSeconds));
    holdTimer.cancel();
    stdout.writeln('closing ${aliveSockets.length} held connections...');
    for (final s in aliveSockets) {
      try {
        await s.close();
        closed++;
        alive--;
      } catch (_) {}
    }
    aliveSockets.clear();
  }

  final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
  stdout.writeln(
      'done elapsedMs=$elapsedMs attempt=$attempt ok=$ok failed=$failed closed=$closed bytesSent=$bytesSent');
}
