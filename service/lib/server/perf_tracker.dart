import 'dart:async';

/// 单个指标的滑动窗口统计（过去 N 秒内的样本）
class _WindowStats {
  final int windowSeconds;
  final String name;

  // 以秒为 key，存该秒内所有样本（微秒）
  final Map<int, List<int>> _buckets = {};

  _WindowStats(this.name, {this.windowSeconds = 60});

  void record(int microseconds) {
    final key = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _buckets.putIfAbsent(key, () => []).add(microseconds);
    _evict(key);
  }

  void _evict(int nowKey) {
    final cutoff = nowKey - windowSeconds;
    _buckets.removeWhere((k, _) => k <= cutoff);
  }

  List<int> get _allSamples {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _evict(now);
    final out = <int>[];
    for (final v in _buckets.values) {
      out.addAll(v);
    }
    return out;
  }

  Map<String, dynamic> snapshot() {
    final samples = _allSamples;
    if (samples.isEmpty) {
      return {
        'name': name,
        'count': 0,
        'windowSec': windowSeconds,
        'p50_us': 0,
        'p90_us': 0,
        'p99_us': 0,
        'max_us': 0,
        'mean_us': 0,
      };
    }
    samples.sort();
    final count = samples.length;
    final p50 = samples[(count * 0.50).floor().clamp(0, count - 1)];
    final p90 = samples[(count * 0.90).floor().clamp(0, count - 1)];
    final p99 = samples[(count * 0.99).floor().clamp(0, count - 1)];
    final maxV = samples.last;
    final mean = samples.reduce((a, b) => a + b) ~/ count;
    return {
      'name': name,
      'count': count,
      'windowSec': windowSeconds,
      'p50_us': p50,
      'p90_us': p90,
      'p99_us': p99,
      'max_us': maxV,
      'mean_us': mean,
    };
  }
}

/// 每秒速率计数器（过去 60s 滑动窗口）
class _RateCounter {
  final String name;
  final Map<int, int> _buckets = {};

  _RateCounter(this.name);

  void add(int count) {
    final key = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _buckets[key] = (_buckets[key] ?? 0) + count;
    _evict(key);
  }

  void inc() => add(1);

  void _evict(int nowKey) {
    _buckets.removeWhere((k, _) => k < nowKey - 60);
  }

  Map<String, dynamic> snapshot() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _evict(now);

    int total60 = 0;
    int total10 = 0;
    int total1 = 0;
    for (final e in _buckets.entries) {
      total60 += e.value;
      if (e.key >= now - 10) total10 += e.value;
      if (e.key >= now - 1) total1 += e.value;
    }
    return {
      'name': name,
      'last1s': total1,
      'last10s': total10,
      'last60s': total60,
      'rate_per_sec_1s': total1,
      'rate_per_sec_10s': (total10 / 10).round(),
      'rate_per_sec_60s': (total60 / 60).round(),
    };
  }
}

/// 全局性能追踪器（单例）
///
/// 使用：
///   final t = PerfTracker.instance;
///   final sw = t.startCollabDecompress(payloadBytes: n, roomId: 'xxx');
///   // ... 执行 ...
///   t.endCollabDecompress(sw);
class PerfTracker {
  PerfTracker._();
  static final PerfTracker instance = PerfTracker._();

  // ===== Event Loop Drift =====
  final _WindowStats _loopDrift =
      _WindowStats('event_loop_drift', windowSeconds: 60);
  DateTime? _lastDriftCheck;
  Timer? _driftTimer;

  // ===== Delta 解压 =====
  final _WindowStats _decompress =
      _WindowStats('collab_decompress', windowSeconds: 60);
  final _RateCounter _decompressRate = _RateCounter('collab_decompress');
  final _RateCounter _decompressBytes = _RateCounter('collab_decompress_bytes');

  // ===== Delta Apply（XOR 写入）=====
  final _WindowStats _apply = _WindowStats('collab_apply', windowSeconds: 60);
  final _RateCounter _applyRate = _RateCounter('collab_apply');
  final _RateCounter _applyPixels = _RateCounter('collab_apply_pixels');

  // ===== Broadcast（广播分发）=====
  final _WindowStats _broadcast =
      _WindowStats('collab_broadcast', windowSeconds: 60);
  final _RateCounter _broadcastRate = _RateCounter('collab_broadcast');
  final _RateCounter _broadcastBytes = _RateCounter('collab_broadcast_bytes');
  final _RateCounter _broadcastErrors = _RateCounter('collab_broadcast_errors');
  final _WindowStats _broadcastTargetCount =
      _WindowStats('collab_broadcast_targets', windowSeconds: 60);
  String? _slowestBroadcastLog;
  int _maxBroadcastUs = 0;

  // ===== 全链路（从收包到广播完成）=====
  final _WindowStats _fullPipeline =
      _WindowStats('collab_full_pipeline', windowSeconds: 60);

  // ===== 全局消息计数 =====
  final Map<String, _RateCounter> _msgCounters = {};

  // ===== Sync 强制次数 =====
  final _RateCounter _syncRequired = _RateCounter('sync_required');

  // ===== 最近热房间（按 delta 频率排序）=====
  final Map<String, _RateCounter> _roomDeltaRates = {};

  // ========================================================
  // Event Loop Drift 探针
  // ========================================================

  /// 启动 drift 探针（在 TcpServer.start() 里调用）
  void startDriftProbe() {
    _driftTimer?.cancel();
    const interval = Duration(milliseconds: 1000);
    _lastDriftCheck = DateTime.now();
    _driftTimer = Timer.periodic(interval, (_) {
      final now = DateTime.now();
      if (_lastDriftCheck != null) {
        final actualMs = now.difference(_lastDriftCheck!).inMicroseconds;
        final driftUs = (actualMs - interval.inMicroseconds).abs();
        _loopDrift.record(driftUs);
      }
      _lastDriftCheck = now;
    });
  }

  /// 停止 drift 探针
  void stopDriftProbe() {
    _driftTimer?.cancel();
    _driftTimer = null;
  }

  // ========================================================
  // 全局消息计数
  // ========================================================

  void countMessage(String typeName) {
    _msgCounters.putIfAbsent(typeName, () => _RateCounter(typeName)).inc();
  }

  // ========================================================
  // Collab Delta 链路追踪（手动计时）
  // ========================================================

  /// 开始计时（返回 Stopwatch，用于后续 end 调用）
  Stopwatch _sw() => Stopwatch()..start();

  Stopwatch beginDecompress() => _sw();

  void endDecompress(Stopwatch sw, {int payloadBytes = 0, String? roomId}) {
    sw.stop();
    _decompress.record(sw.elapsedMicroseconds);
    _decompressRate.inc();
    _decompressBytes.add(payloadBytes);
    if (roomId != null) {
      _roomDeltaRates.putIfAbsent(roomId, () => _RateCounter(roomId)).inc();
    }
  }

  Stopwatch beginApply() => _sw();

  void endApply(Stopwatch sw, {int pixelCount = 0}) {
    sw.stop();
    _apply.record(sw.elapsedMicroseconds);
    _applyRate.inc();
    _applyPixels.add(pixelCount);
  }

  Stopwatch beginBroadcast() => _sw();

  void endBroadcast(Stopwatch sw,
      {int broadcastBytes = 0,
      int targetCount = 0,
      int errors = 0,
      String? roomId}) {
    sw.stop();
    final us = sw.elapsedMicroseconds;
    _broadcast.record(us);
    _broadcastRate.inc();
    _broadcastBytes.add(broadcastBytes);
    _broadcastErrors.add(errors);
    _broadcastTargetCount.record(targetCount);

    if (us > _maxBroadcastUs || us > 50000) {
      // 记录超过 50ms 的广播长尾详细信息
      _maxBroadcastUs = us;
      _slowestBroadcastLog =
          '${DateTime.now().toIso8601String()} | ${us}us | targets: $targetCount | room: $roomId | bytes: $broadcastBytes';
    }
  }

  Stopwatch beginFullPipeline() => _sw();

  void endFullPipeline(Stopwatch sw) {
    sw.stop();
    _fullPipeline.record(sw.elapsedMicroseconds);
  }

  // sync_required 计数
  void countSyncRequired() => _syncRequired.inc();

  // ========================================================
  // 快照输出
  // ========================================================

  Map<String, dynamic> snapshot() {
    final now = DateTime.now().toIso8601String();

    // top 房间（按 last10s delta 次数排序）
    final roomRates = _roomDeltaRates.entries.map((e) {
      final s = e.value.snapshot();
      return {'roomId': e.key, ...s};
    }).toList();
    roomRates.sort((a, b) =>
        ((b['last10s'] as int?) ?? 0).compareTo((a['last10s'] as int?) ?? 0));

    // 全局消息速率 top
    final msgRates = _msgCounters.entries.map((e) {
      final s = e.value.snapshot();
      return {'type': e.key, ...s};
    }).toList();
    msgRates.sort((a, b) =>
        ((b['last10s'] as int?) ?? 0).compareTo((a['last10s'] as int?) ?? 0));

    // Decompress / Apply / Broadcast 详细（包含 rate/throughput 子指标，供 /perf 页面渲染）
    final decompressSnap = {
      ..._decompress.snapshot(),
      'rate': _decompressRate.snapshot(),
      'bytesRate': _decompressBytes.snapshot(),
    };

    final applySnap = {
      ..._apply.snapshot(),
      'rate': _applyRate.snapshot(),
      'pixelsRate': _applyPixels.snapshot(),
    };

    // 广播详细
    final broadcastSnap = _broadcast.snapshot();
    final broadcastErrors = _broadcastErrors.snapshot();
    final broadcastTargets = _broadcastTargetCount.snapshot();

    // 构造更友好的广播快照
    final collabBroadcast = {
      ...broadcastSnap,
      'rate': _broadcastRate.snapshot(),
      'bytesRate': _broadcastBytes.snapshot(),
      'errors_total': broadcastErrors['last60s'],
      'errors_rate_10s': broadcastErrors['rate_per_sec_10s'],
      'targets_p50': broadcastTargets['p50_us'], // 这里借用 p50_us 字段存数量
      'targets_max': broadcastTargets['max_us'],
      'slowestLog': _slowestBroadcastLog,
    };

    return {
      'snapshotAt': now,
      'eventLoopDrift': _loopDrift.snapshot(),
      'collabDecompress': decompressSnap,
      'collabDecompressBytes': _decompressBytes.snapshot(),
      'collabApply': applySnap,
      'collabApplyPixels': _applyPixels.snapshot(),
      'collabBroadcast': collabBroadcast,
      'collabFullPipeline': _fullPipeline.snapshot(),
      'syncRequired': _syncRequired.snapshot(),
      'hotRooms': roomRates,
      'messageRates': msgRates,
    };
  }
}
