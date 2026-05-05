/// 协同 Delta 压测脚本
///
/// 用法：
///   dart run bin/bench_collab_delta.dart [options]
///
/// 选项（通过环境变量）：
///   HOST        服务端地址（默认 127.0.0.1）
///   PORT        服务端端口（默认 9527）
///   ROOMS       创建房间数（默认 3）
///   ROOM_SIZE   每个房间客户端数（默认 14，最大 16）
///   DELTA_HZ    每个客户端每秒发送 delta 次数（默认 20）
///   REGION_W    delta 区域宽度（默认 128）
///   REGION_H    delta 区域高度（默认 128）
///   COMPRESS    是否 zlib 压缩（默认 true）
///   DURATION_S  压测持续秒数（默认 30）
///   CANVAS_W    画布宽度（默认 1920）
///   CANVAS_H    画布高度（默认 1080）
///
/// 流程：
///   1. 按 ROOMS × ROOM_SIZE 创建所有客户端
///   2. 每个房间第一个客户端创建房间，其余加入
///   3. 所有客户端以 DELTA_HZ 频率并发发送 collabDelta
///   4. 压测结束后打印分房间摘要 + 全局汇总
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// ===== 配置 =====
final String host = Platform.environment['HOST'] ?? '127.0.0.1';
final int port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 9527;
final int roomCount = int.tryParse(Platform.environment['ROOMS'] ?? '') ?? 3;
final int roomSize =
    (int.tryParse(Platform.environment['ROOM_SIZE'] ?? '') ?? 14).clamp(2, 16);
final int deltaHz = int.tryParse(Platform.environment['DELTA_HZ'] ?? '') ?? 20;
final int regionW = int.tryParse(Platform.environment['REGION_W'] ?? '') ?? 128;
final int regionH = int.tryParse(Platform.environment['REGION_H'] ?? '') ?? 128;
final bool compress =
    (Platform.environment['COMPRESS'] ?? 'true').toLowerCase() == 'true';
final int durationSec =
    int.tryParse(Platform.environment['DURATION_S'] ?? '') ?? 30;
final int canvasW =
    int.tryParse(Platform.environment['CANVAS_W'] ?? '') ?? 1920;
final int canvasH =
    int.tryParse(Platform.environment['CANVAS_H'] ?? '') ?? 1080;

final int effectiveRegionW = regionW > canvasW ? canvasW : regionW;
final int effectiveRegionH = regionH > canvasH ? canvasH : regionH;

// ===== 协议常量 =====
const int _headerLen = 5; // 4 bytes length + 1 byte type

// MessageType codes
const int _loginRequest = 0x01;
const int _loginResponse = 0x81;
const int _createRoomRequest = 0x20;
const int _createRoomResponse = 0xA0;
const int _joinRoomRequest = 0x22;
const int _joinRoomResponse = 0xA2;
const int _collabDelta = 0x34;
const int _collabDeltaBroadcast = 0xC0;
const int _collabSyncRequired = 0xC1;

final _rng = Random();

// ===== 协议编解码工具 =====

Uint8List _encode(int typeCode, Uint8List payload) {
  final total = _headerLen + payload.length;
  final buf = ByteData(total);
  buf.setUint32(0, total, Endian.big);
  buf.setUint8(4, typeCode);
  final out = buf.buffer.asUint8List();
  out.setAll(_headerLen, payload);
  return out;
}

Uint8List _loginPayload(String username, Uint8List fingerprint8) {
  final nameBytes = utf8.encode(username);
  final len = nameBytes.length.clamp(0, 255);
  final buf = Uint8List(1 + len + 8);
  buf[0] = len;
  buf.setAll(1, nameBytes.sublist(0, len));
  buf.setAll(1 + len, fingerprint8);
  return buf;
}

Uint8List _createRoomPayload(String roomName, int maxPlayers) {
  // roomType = collab = 0x02
  final nameBytes = utf8.encode(roomName);
  final len = nameBytes.length.clamp(0, 255);
  final buf = Uint8List(1 + 1 + len + 1);
  buf[0] = 0x02; // collab
  buf[1] = len;
  if (len > 0) buf.setAll(2, nameBytes.sublist(0, len));
  buf[2 + len] = maxPlayers.clamp(1, 16);
  return buf;
}

Uint8List _joinRoomPayload(String roomId) {
  final idBytes = utf8.encode(roomId);
  final len = idBytes.length.clamp(0, 255);
  final buf = Uint8List(1 + len);
  buf[0] = len;
  if (len > 0) buf.setAll(1, idBytes.sublist(0, len));
  return buf;
}

Uint8List _collabDeltaPayload({
  required int epoch,
  required int baseRev,
  required int x,
  required int y,
  required int width,
  required int height,
  required int flags,
  required Uint8List payload,
}) {
  final hdr = ByteData(4 + 4 + 2 + 2 + 2 + 2 + 1 + 4);
  hdr.setUint32(0, epoch, Endian.big);
  hdr.setUint32(4, baseRev, Endian.big);
  hdr.setUint16(8, x, Endian.big);
  hdr.setUint16(10, y, Endian.big);
  hdr.setUint16(12, width, Endian.big);
  hdr.setUint16(14, height, Endian.big);
  hdr.setUint8(16, flags);
  hdr.setUint32(17, payload.length, Endian.big);
  final out = BytesBuilder();
  out.add(hdr.buffer.asUint8List());
  out.add(payload);
  return out.toBytes();
}

Uint8List _randomDeltaRgba(int w, int h, bool doCompress) {
  // 生成随机 RGBA 区域（模拟 XOR delta）
  final raw = Uint8List(w * h * 4);
  for (int i = 0; i < raw.length; i++) {
    raw[i] = _rng.nextInt(256);
  }
  if (doCompress) {
    return Uint8List.fromList(zlib.encode(raw));
  }
  return raw;
}

// ===== 客户端模拟 =====

class BenchClient {
  final int index;
  final String username;
  final Uint8List fingerprint;
  Socket? _socket;
  bool _dead = false;
  final List<int> _buffer = [];
  int sentDeltas = 0;
  int writeFail = 0;
  int receivedBroadcasts = 0;
  int syncRequiredCount = 0;
  String? roomId;
  int epoch = 0;
  int rev = 0;
  bool loggedIn = false;
  bool inRoom = false;
  final Completer<void> _loginDone = Completer<void>();
  final Completer<void> _roomDone = Completer<void>();

  List<Uint8List>? _deltaPayloadPool;
  int _deltaPoolIndex = 0;

  BenchClient(this.index)
      : username = 'bench_$index',
        fingerprint = _makeFingerprint(index);

  static Uint8List _makeFingerprint(int idx) {
    final fp = Uint8List(8);
    fp[0] = 0xBE;
    fp[1] = 0xEF;
    // 填入 index
    fp[4] = (idx >> 24) & 0xFF;
    fp[5] = (idx >> 16) & 0xFF;
    fp[6] = (idx >> 8) & 0xFF;
    fp[7] = idx & 0xFF;
    return fp;
  }

  Future<void> connect() async {
    _socket = await Socket.connect(host, port);
    _socket!.done.catchError((e) {
      // 写入失败通常会在异步阶段冒泡（不一定能被 sendDelta 的 try-catch 捕获）
      writeFail++;
      _dead = true;
      print('[$username] socket done error: $e');
    });
    _socket!.listen(
      (data) => _onData(data),
      onError: (e) {
        writeFail++;
        _dead = true;
        print('[$username] socket error: $e');
      },
      onDone: () {
        _dead = true;
      },
    );
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    while (_buffer.length >= _headerLen) {
      final b0 = _buffer[0] & 0xFF;
      final b1 = _buffer[1] & 0xFF;
      final b2 = _buffer[2] & 0xFF;
      final b3 = _buffer[3] & 0xFF;
      final totalLen = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
      if (totalLen < _headerLen) {
        _buffer.clear();
        return;
      }
      if (_buffer.length < totalLen) break;

      final typeCode = _buffer[4] & 0xFF;
      // 性能关键：广播量很大时不要为每条消息分配 payload（避免 bench 本机成为瓶颈）
      if (typeCode == _collabDeltaBroadcast) {
        receivedBroadcasts++;
        _buffer.removeRange(0, totalLen);
        continue;
      }
      if (typeCode == _collabSyncRequired) {
        syncRequiredCount++;
        _buffer.removeRange(0, totalLen);
        continue;
      }

      final payload = Uint8List.fromList(_buffer.sublist(_headerLen, totalLen));
      _buffer.removeRange(0, totalLen);
      _onMessage(typeCode, payload);
    }
  }

  void _onMessage(int type, Uint8List payload) {
    if (type == _loginResponse) {
      loggedIn = payload.isNotEmpty && payload[0] == 0x00;
      if (!_loginDone.isCompleted) _loginDone.complete();
    } else if (type == _createRoomResponse) {
      if (payload.isNotEmpty && payload[0] == 0x00 && payload.length >= 2) {
        final idLen = payload[1];
        if (payload.length >= 2 + idLen) {
          roomId = utf8.decode(payload.sublist(2, 2 + idLen));
        }
      }
      inRoom = roomId != null;
      if (!_roomDone.isCompleted) _roomDone.complete();
    } else if (type == _joinRoomResponse) {
      if (payload.isNotEmpty && payload[0] == 0x00) {
        inRoom = true;
      }
      if (!_roomDone.isCompleted) _roomDone.complete();
    }
  }

  Future<void> login() async {
    _socket!.add(_encode(_loginRequest, _loginPayload(username, fingerprint)));
    await _loginDone.future.timeout(const Duration(seconds: 5));
    if (!loggedIn) throw Exception('[$username] login failed');
  }

  Future<void> createRoom(String name, int maxPlayers) async {
    _socket!
        .add(_encode(_createRoomRequest, _createRoomPayload(name, maxPlayers)));
    await _roomDone.future.timeout(const Duration(seconds: 5));
    if (!inRoom) throw Exception('[$username] create room failed');
  }

  Future<void> joinRoom(String targetRoomId) async {
    roomId = targetRoomId;
    _socket!.add(_encode(_joinRoomRequest, _joinRoomPayload(targetRoomId)));
    await _roomDone.future.timeout(const Duration(seconds: 5));
    if (!inRoom) throw Exception('[$username] join room failed');
  }

  Uint8List _nextDeltaPayload() {
    // 预生成 payload，避免每次 send 都做 random + zlib（否则压测瓶颈变成本机 CPU）
    final pool = _deltaPayloadPool;
    if (pool == null) {
      final created = <Uint8List>[];
      // pool 大小不宜太大，避免内存过高；4 个样本足够模拟
      for (int i = 0; i < 4; i++) {
        created.add(
            _randomDeltaRgba(effectiveRegionW, effectiveRegionH, compress));
      }
      _deltaPayloadPool = created;
      _deltaPoolIndex = 0;
      return created[0];
    }
    final v = pool[_deltaPoolIndex];
    _deltaPoolIndex = (_deltaPoolIndex + 1) % pool.length;
    return v;
  }

  void sendDelta() {
    if (_socket == null || !inRoom || _dead) return;
    try {
      final maxX = (canvasW - effectiveRegionW).clamp(0, canvasW);
      final maxY = (canvasH - effectiveRegionH).clamp(0, canvasH);
      final x = maxX > 0 ? _rng.nextInt(maxX) : 0;
      final y = maxY > 0 ? _rng.nextInt(maxY) : 0;

      final rgbaPayload = _nextDeltaPayload();
      final flags = compress ? 0x01 : 0x00;

      final deltaPayload = _collabDeltaPayload(
        epoch: epoch,
        baseRev: rev,
        x: x,
        y: y,
        width: effectiveRegionW,
        height: effectiveRegionH,
        flags: flags,
        payload: rgbaPayload,
      );
      _socket!.add(_encode(_collabDelta, deltaPayload));
      sentDeltas++;
    } catch (_) {
      // socket 已断开，静默跳过
      writeFail++;
      _dead = true;
    }
  }

  Future<void> close() async {
    await _socket?.close();
  }
}

// ===== 主流程 =====

void main() async {
  runZonedGuarded(() async {
    final totalClients = roomCount * roomSize;
    print('====== Collab Delta Benchmark ======');
    print('Target:   $host:$port');
    print(
        'Rooms:    $roomCount  x  $roomSize clients/room  =  $totalClients total clients');
    print('DeltaHz:  $deltaHz/client/s  =>  ${totalClients * deltaHz}/s total');
    print('Region:   ${regionW}x$regionH px, Compress: $compress');
    print('Canvas:   ${canvasW}x$canvasH');
    print('Duration: ${durationSec}s');
    print('');

    // 1. 创建并连接所有客户端
    final allClients = List.generate(totalClients, (i) => BenchClient(i));
    print('Connecting $totalClients clients...');
    await Future.wait(allClients.map((c) => c.connect()));
    print('All connected.');

    // 2. Login（全部并发）
    print('Logging in...');
    await Future.wait(allClients.map((c) => c.login()));
    print('All logged in.');

    // 3. 按 roomSize 分组，每组创建一个协同房间
    final groups = <List<BenchClient>>[];
    for (int r = 0; r < roomCount; r++) {
      groups.add(allClients.sublist(r * roomSize, (r + 1) * roomSize));
    }

    print('Setting up $roomCount rooms...');
    await Future.wait(groups.asMap().entries.map((entry) async {
      final r = entry.key;
      final group = entry.value;
      final creator = group[0];
      await creator.createRoom('bench_room_$r', roomSize);
      if (group.length > 1) {
        await Future.wait(
            group.sublist(1).map((c) => c.joinRoom(creator.roomId!)));
      }
    }));
    print('All rooms ready:');
    for (int r = 0; r < roomCount; r++) {
      print(
          '  room[$r]: ${groups[r][0].roomId}  (${groups[r].length} clients)');
    }

    // 等待加入广播稳定
    await Future.delayed(const Duration(milliseconds: 800));

    // 4. 开始压测（所有客户端并发）
    print('');
    print('=== Starting benchmark for ${durationSec}s ===');
    final intervalMs = (1000 / deltaHz).round().clamp(1, 1000);
    final startTime = DateTime.now();

    final timers = <Timer>[];
    for (final client in allClients) {
      final offsetMs = _rng.nextInt(intervalMs);
      timers.add(Timer(Duration(milliseconds: offsetMs), () {
        timers.add(Timer.periodic(Duration(milliseconds: intervalMs), (_) {
          if (DateTime.now().difference(startTime).inSeconds >= durationSec)
            return;
          client.sendDelta();
        }));
      }));
    }

    // 5. 等待压测结束 + 额外 2s 让广播落地
    await Future.delayed(Duration(seconds: durationSec + 2));
    for (final t in timers) {
      t.cancel();
    }

    // 6. 统计
    final elapsed = DateTime.now().difference(startTime);
    int gTotalSent = 0;
    int gTotalRecv = 0;
    int gTotalSync = 0;
    int gTotalWriteFail = 0;

    print('');
    print('====== Results ======');
    print('Elapsed: ${elapsed.inMilliseconds}ms');
    print('');

    for (int r = 0; r < roomCount; r++) {
      final group = groups[r];
      int rSent = 0, rRecv = 0, rSync = 0;
      int rWriteFail = 0;
      for (final c in group) {
        rSent += c.sentDeltas;
        rRecv += c.receivedBroadcasts;
        rSync += c.syncRequiredCount;
        rWriteFail += c.writeFail;
      }
      gTotalSent += rSent;
      gTotalRecv += rRecv;
      gTotalSync += rSync;
      gTotalWriteFail += rWriteFail;
      final syncPct =
          rSent > 0 ? (rSync / rSent * 100).toStringAsFixed(1) : '0.0';
      print('Room[$r] ${groups[r][0].roomId}');
      print(
          '  sent=$rSent  recv=$rRecv  sync=$rSync  syncRatio=$syncPct%  writeFail=$rWriteFail');
      print('  rate=${(rSent / elapsed.inSeconds).round()}/s');
    }

    final gSyncPct = gTotalSent > 0
        ? (gTotalSync / gTotalSent * 100).toStringAsFixed(1)
        : '0.0';
    print('');
    print('--- Global ---');
    print('Total clients:       $totalClients');
    print('Total deltas sent:   $gTotalSent');
    print('Total broadcasts:    $gTotalRecv');
    print('Total syncRequired:  $gTotalSync  ($gSyncPct%)');
    print('Total writeFail:     $gTotalWriteFail');
    print('Effective rate:      ${(gTotalSent / elapsed.inSeconds).round()}/s');
    print('');
    print('Tip: http://$host:9090/perf');

    await Future.wait(allClients.map((c) => c.close()));
    print('Done.');
  }, (e, st) {
    // 兜底：避免单个 socket 的异步写入异常导致整个压测进程崩溃
    stderr.writeln('Unhandled bench error: $e');
  });
}
