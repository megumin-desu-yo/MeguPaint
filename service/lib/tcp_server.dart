import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'protocol/protocol_handler.dart';
import 'room/room_data.dart';
import 'room/room_broadcaster.dart';
import 'room/client_session.dart';
import 'server/tcp_server_base.dart';
import 'server/auth_mixin.dart';
import 'server/room_mixin.dart';
import 'server/game_mixin.dart';
import 'server/review_mixin.dart';
import 'server/game_phase_mixin.dart';
import 'server/perf_tracker.dart';

/// TCP 服务端
class TcpServer extends TcpServerBase
    with AuthMixin, RoomMixin, GameMixin, ReviewMixin, GamePhaseMixin {
  ServerSocket? _serverSocket;
  bool _isRunning = false;

  Timer? _idleSweepTimer;

  final Duration _idleSweepInterval;
  final Duration _handshakeTimeout;
  final Duration _authenticatedIdleTimeout;
  static const int _maxSessionBufferBytes = 1024 * 1024;
  static const int _maxPreAuthSessionBufferBytes = 64 * 1024;

  TcpServer({
    super.port,
    super.serverName,
    super.authService,
    super.maxConnections,
    super.maxRooms,
    Duration idleSweepInterval = const Duration(seconds: 10),
    Duration handshakeTimeout = const Duration(seconds: 30),
    Duration authenticatedIdleTimeout = const Duration(minutes: 90),
  })  : _idleSweepInterval = idleSweepInterval,
        _handshakeTimeout = handshakeTimeout,
        _authenticatedIdleTimeout = authenticatedIdleTimeout;

  /// 是否正在运行
  @override
  bool get isRunning => _isRunning;

  /// 当前连接数
  @override
  int get connectionCount => clients.length;

  /// 当前房间数
  @override
  int get roomCount => rooms.length;

  int get authenticatedIdleTimeoutSeconds =>
      _authenticatedIdleTimeout.inSeconds;

  List<Map<String, dynamic>> getClientsAdminSnapshot() {
    final now = DateTime.now();
    final entries = clients.entries.toList(growable: false);
    final out = <Map<String, dynamic>>[];
    for (final e in entries) {
      final socket = e.key;
      final session = e.value;
      final roomId = session.currentRoomId;
      final roomName = roomId == null ? null : rooms[roomId]?.roomName;
      out.add(<String, dynamic>{
        'ip': session.ip,
        'remotePort': socket.remotePort,
        'isAuthenticated': session.isAuthenticated,
        'username': session.username,
        'fingerprintHex': session.fingerprintHex,
        'connectedAt': session.connectedAt.toIso8601String(),
        'lastActiveAt': session.lastActiveAt.toIso8601String(),
        'idleSeconds': now.difference(session.lastActiveAt).inSeconds,
        'bufferBytes': session.buffer.length,
        'roomId': roomId,
        'roomName': roomName,
      });
    }
    out.sort((a, b) {
      final aAuth = a['isAuthenticated'] == true;
      final bAuth = b['isAuthenticated'] == true;
      if (aAuth != bAuth) return aAuth ? -1 : 1;
      final ai = (a['idleSeconds'] is int) ? (a['idleSeconds'] as int) : 0;
      final bi = (b['idleSeconds'] is int) ? (b['idleSeconds'] as int) : 0;
      return bi.compareTo(ai);
    });
    return out;
  }

  List<Map<String, dynamic>> getRoomsAdminSnapshot() {
    final now = DateTime.now();
    final roomList = rooms.values.toList(growable: false);
    return roomList
        .map((r) => <String, dynamic>{
              'roomId': r.roomId,
              'roomName': r.roomName,
              'roomType': r.roomType.toString(),
              'roomTypeCode': r.roomType.code,
              'maxPlayers': r.maxPlayers,
              'playerCount': r.members.length,
              'creatorUsername': r.creatorUsername,
              'creatorFingerprintHex': r.creatorFingerprintHex,
              'ownerUsername': r.ownerUsername,
              'ownerFingerprintHex': r.ownerFingerprintHex,
              'lexiconKey': r.lexiconKey,
              'lexiconLoaded':
                  (r.lexiconJson != null && r.lexiconJson!.isNotEmpty),
              'gamePhase': r.gamePhase.toString(),
              'currentRound': r.currentRound,
              'rounds': r.rounds,
              'phaseTimeLeftSec': r.phaseEndAt == null
                  ? null
                  : max(0, r.phaseEndAt!.difference(now).inSeconds),
              'memberDrawingsBytes': _calcMemberDrawingsBytes(r),
              'roundHistoryCount': r.roundHistory.length,
              'roundHistoryPngBytes': _calcRoomHistoryPngBytes(r),
              'collabLayersCount': r.collabLayers.length,
            })
        .toList(growable: false);
  }

  Map<String, dynamic>? getRoomAdminSnapshot(String roomId) {
    final room = rooms[roomId];
    if (room == null) return null;
    final now = DateTime.now();

    final members = room.members
        .map((m) => <String, dynamic>{
              'username': m.username,
              'fingerprintHex': m.fingerprintHex,
              'isReady': m.isReady,
            })
        .toList(growable: false);

    Map<String, dynamic> pickMapToUser(Map<int, String> picks) {
      final fpToName = {
        for (var m in room.members) m.fingerprintHex: m.username
      };
      return picks.map((k, v) {
        final name = fpToName[v] ?? 'unknown';
        return MapEntry(k.toString(), '$name ($v)');
      });
    }

    final fpToName = {for (var m in room.members) m.fingerprintHex: m.username};
    Map<int, String> parsePickMap(dynamic raw) {
      if (raw is Map<int, String>) return raw;
      if (raw is Map) {
        final out = <int, String>{};
        for (final e in raw.entries) {
          final k = int.tryParse(e.key.toString());
          if (k == null) continue;
          out[k] = e.value.toString();
        }
        return out;
      }
      return const <int, String>{};
    }

    List<Map<String, dynamic>> historySummary() {
      final out = <Map<String, dynamic>>[];
      for (final h in room.roundHistory) {
        final round = h['round'];
        final drawings = (h['memberDrawings'] is Map)
            ? (h['memberDrawings'] as Map)
            : const {};
        final drawingsList = <Map<String, dynamic>>[];
        for (final e in drawings.entries) {
          final fp = e.key.toString();
          final bytes = e.value;
          int size = 0;
          if (bytes is Uint8List) size = bytes.length;
          drawingsList.add({
            'fingerprintHex': fp,
            'username': fpToName[fp] ?? 'unknown',
            'pngBytes': size,
            'pngUrlPath':
                '/rooms/${Uri.encodeComponent(roomId)}/png/$round/$fp',
          });
        }
        drawingsList.sort((a, b) => (a['username'] ?? '')
            .toString()
            .compareTo((b['username'] ?? '').toString()));
        final submitHistory = <Map<String, dynamic>>[];
        final rawSubmitHistory = h['guessSubmitHistory'];
        if (rawSubmitHistory is Map) {
          for (final e in rawSubmitHistory.entries) {
            final fp = e.key.toString();
            final items = (e.value is List) ? (e.value as List) : const [];
            submitHistory.add({
              'fingerprintHex': fp,
              'username': fpToName[fp] ?? 'unknown',
              'submitCount': items.length,
              'submits': items,
            });
          }
        }
        submitHistory.sort((a, b) => (a['username'] ?? '')
            .toString()
            .compareTo((b['username'] ?? '').toString()));

        out.add({
          'round': round,
          'archivedAt': h['archivedAt'],
          'wordCardPicks': pickMapToUser(parsePickMap(h['wordCardPicks'])),
          'guessCardPicks': pickMapToUser(parsePickMap(h['guessCardPicks'])),
          'guessResults': h['guessResults'],
          'guessSubmitHistory': submitHistory,
          'drawings': drawingsList,
        });
      }
      return out;
    }

    final historyPngBytes = _calcRoomHistoryPngBytes(room);

    final replayId = room.lastReplayFile?['replayId']?.toString();
    int replayTrackCount = 0;
    final tracksRaw = room.lastReplayFile?['tracks'];
    if (tracksRaw is List) replayTrackCount = tracksRaw.length;

    return <String, dynamic>{
      'roomId': room.roomId,
      'roomName': room.roomName,
      'roomType': room.roomType.toString(),
      'maxPlayers': room.maxPlayers,
      'creatorUsername': room.creatorUsername,
      'creatorFingerprintHex': room.creatorFingerprintHex,
      'ownerUsername': room.ownerUsername,
      'ownerFingerprintHex': room.ownerFingerprintHex,
      'lexiconKey': room.lexiconKey,
      'lexiconJson': room.lexiconJson,
      'lexiconLoaded': room.lexiconJson != null && room.lexiconJson!.isNotEmpty,
      'memberCount': room.members.length,
      'members': members,
      'gamePhase': room.gamePhase.toString(),
      'currentRound': room.currentRound,
      'rounds': room.rounds,
      'roundTime': room.roundTime,
      'phaseEndAt': room.phaseEndAt?.toIso8601String(),
      'phaseTimeLeftSec': room.phaseEndAt == null
          ? null
          : max(0, room.phaseEndAt!.difference(now).inSeconds),
      'wordCardsCount': room.wordCards.length,
      'wordCardPicks': pickMapToUser(room.wordCardPicks),
      'guessCardsCount': room.guessCards.length,
      'guessCardPicks': pickMapToUser(room.guessCardPicks),
      'drawingUploadedCount': room.memberDrawings.length,
      'drawingCompletedCount': room.drawingCompletedMembers.length,
      'guessResultsCount': room.guessResults.length,
      'lastRoundGuessesCount': room.lastRoundGuesses.length,
      'allRoundResultsCount': room.allRoundResults.length,
      'roundHistoryCount': room.roundHistory.length,
      'roundHistoryPngBytes': historyPngBytes,
      'roundHistoryPngMB': (historyPngBytes / 1024 / 1024).toStringAsFixed(2),
      'roundHistory': historySummary(),
      'replayId': replayId,
      'replayTrackCount': replayTrackCount,
      'lastReplayFile': room.lastReplayFile,
      // 协同模式附加信息
      'roomTypeCode': room.roomType.code,
      'canvasWidth': room.canvasWidth,
      'canvasHeight': room.canvasHeight,
      'collabEpoch': room.collabEpoch,
      'collabLayers': room.collabLayers.map((l) {
        final encodedId = Uri.encodeComponent(l.layerId);
        final encodedRoom = Uri.encodeComponent(roomId);
        return <String, dynamic>{
          'layerId': l.layerId,
          'name': l.name,
          'ownerId': l.ownerId,
          'isVisible': l.isVisible,
          'isLocked': l.isLocked,
          'opacity': l.opacity,
          'blendMode': l.blendMode,
          'rev': l.rev,
          'rgbaBytes': l.rgba.length,
          'previewUrl': '/rooms/$encodedRoom/collab/layer/$encodedId.png',
        };
      }).toList(growable: false),
      'collabCompositeUrl': room.collabLayers.isNotEmpty
          ? '/rooms/${Uri.encodeComponent(roomId)}/collab/composite.png'
          : null,
    };
  }

  int _calcRoomHistoryPngBytes(RoomData room) {
    int sum = 0;
    for (final h in room.roundHistory) {
      final drawings = h['memberDrawings'];
      if (drawings is Map) {
        for (final v in drawings.values) {
          if (v is Uint8List) sum += v.length;
        }
      }
    }
    return sum;
  }

  int _calcMemberDrawingsBytes(RoomData room) {
    int sum = 0;
    for (final v in room.memberDrawings.values) {
      sum += v.length;
    }
    return sum;
  }

  /// 获取指定协同图层的 RGBA 原始数据（供 admin 预览使用）
  Map<String, dynamic>? getCollabLayerRgba(String roomId, String layerId) {
    final room = rooms[roomId];
    if (room == null) return null;
    final layer = room.collabLayers
        .cast<CollabLayerInfo?>()
        .firstWhere((l) => l!.layerId == layerId, orElse: () => null);
    if (layer == null) return null;
    return {
      'rgba': Uint8List.fromList(layer.rgba),
      'width': room.canvasWidth,
      'height': room.canvasHeight,
    };
  }

  /// 获取所有可见图层 alpha 合成后的 RGBA 数据（供 admin 预览使用）
  Map<String, dynamic>? getCollabCompositeRgba(String roomId) {
    final room = rooms[roomId];
    if (room == null || room.collabLayers.isEmpty) return null;
    final w = room.canvasWidth;
    final h = room.canvasHeight;
    final result = Uint8List(w * h * 4);
    for (final layer in room.collabLayers) {
      if (!layer.isVisible) continue;
      final src = layer.rgba;
      if (src.length != w * h * 4) continue;
      final alpha = layer.opacity;
      for (int p = 0; p < w * h; p++) {
        final pi = p * 4;
        final srcA = (src[pi + 3] / 255.0) * alpha;
        final dstA = result[pi + 3] / 255.0;
        final outA = srcA + dstA * (1.0 - srcA);
        if (outA < 1e-6) continue;
        for (int c = 0; c < 3; c++) {
          final srcC = src[pi + c] / 255.0;
          final dstC = result[pi + c] / 255.0;
          result[pi + c] =
              ((srcC * srcA + dstC * dstA * (1.0 - srcA)) / outA * 255.0)
                  .round()
                  .clamp(0, 255);
        }
        result[pi + 3] = (outA * 255.0).round().clamp(0, 255);
      }
    }
    return {'rgba': result, 'width': w, 'height': h};
  }

  int _calcReplayJsonBytes(dynamic replayFile) {
    if (replayFile == null) return 0;
    try {
      return utf8.encode(jsonEncode(replayFile)).length;
    } catch (_) {
      return 0;
    }
  }

  Map<String, dynamic> getMemoryAdminSnapshot() {
    final rssBytes = ProcessInfo.currentRss;

    int clientBufferBytes = 0;
    int preAuthClientCount = 0;
    int authClientCount = 0;
    final clientBufferTop = <Map<String, dynamic>>[];
    for (final e in clients.entries) {
      final session = e.value;
      final b = session.buffer.length;
      clientBufferBytes += b;
      if (session.isAuthenticated) {
        authClientCount++;
      } else {
        preAuthClientCount++;
      }
      clientBufferTop.add({
        'ip': session.ip,
        'username': session.username,
        'fingerprintHex': session.fingerprintHex,
        'isAuthenticated': session.isAuthenticated,
        'bufferBytes': b,
      });
    }
    clientBufferTop.sort((a, b) {
      final ai = (a['bufferBytes'] is int) ? (a['bufferBytes'] as int) : 0;
      final bi = (b['bufferBytes'] is int) ? (b['bufferBytes'] as int) : 0;
      return bi.compareTo(ai);
    });

    int roomsMemberDrawingsBytes = 0;
    int roomsRoundHistoryPngBytes = 0;
    int roomsReplayJsonBytes = 0;
    int roomsCollabLayersRgbaBytes = 0;

    final roomBreakdown = <Map<String, dynamic>>[];
    for (final r in rooms.values) {
      final memberDrawingsBytes = _calcMemberDrawingsBytes(r);
      final historyPngBytes = _calcRoomHistoryPngBytes(r);
      final replayJsonBytes = _calcReplayJsonBytes(r.lastReplayFile);

      int collabLayersRgbaBytes = 0;
      final collabLayerEntries = <Map<String, dynamic>>[];
      if (r.collabLayers.isNotEmpty) {
        for (final l in r.collabLayers) {
          final rgbaBytes = l.rgba.length;
          collabLayersRgbaBytes += rgbaBytes;
          collabLayerEntries.add({
            'layerId': l.layerId,
            'name': l.name,
            'ownerId': l.ownerId,
            'rgbaBytes': rgbaBytes,
            'rev': l.rev,
            'isVisible': l.isVisible,
            'isLocked': l.isLocked,
            'opacity': l.opacity,
            'blendMode': l.blendMode,
          });
        }
      }

      roomsMemberDrawingsBytes += memberDrawingsBytes;
      roomsRoundHistoryPngBytes += historyPngBytes;
      roomsReplayJsonBytes += replayJsonBytes;
      roomsCollabLayersRgbaBytes += collabLayersRgbaBytes;

      final totalBytes = memberDrawingsBytes +
          historyPngBytes +
          replayJsonBytes +
          collabLayersRgbaBytes;

      roomBreakdown.add({
        'roomId': r.roomId,
        'roomName': r.roomName,
        'gamePhase': r.gamePhase.toString(),
        'playerCount': r.members.length,
        'memberDrawingsBytes': memberDrawingsBytes,
        'roundHistoryPngBytes': historyPngBytes,
        'replayJsonBytes': replayJsonBytes,
        'collabLayersRgbaBytes': collabLayersRgbaBytes,
        'collabLayers': collabLayerEntries,
        'totalBytes': totalBytes,
      });
    }
    roomBreakdown.sort((a, b) {
      final ai = (a['totalBytes'] as int?) ?? 0;
      final bi = (b['totalBytes'] as int?) ?? 0;
      return bi.compareTo(ai);
    });

    final roomsTotalBytes = roomsMemberDrawingsBytes +
        roomsRoundHistoryPngBytes +
        roomsReplayJsonBytes +
        roomsCollabLayersRgbaBytes;

    return {
      'now': DateTime.now().toIso8601String(),
      'processRssBytes': rssBytes,
      'processRssMB': (rssBytes / 1024 / 1024).toStringAsFixed(2),
      'connections': connectionCount,
      'rooms': roomCount,
      'clients': {
        'authenticatedCount': authClientCount,
        'preAuthCount': preAuthClientCount,
        'totalBufferBytes': clientBufferBytes,
        'bufferTop': clientBufferTop.take(20).toList(growable: false),
      },
      'roomsTotal': {
        'memberDrawingsBytes': roomsMemberDrawingsBytes,
        'roundHistoryPngBytes': roomsRoundHistoryPngBytes,
        'replayJsonBytes': roomsReplayJsonBytes,
        'collabLayersRgbaBytes': roomsCollabLayersRgbaBytes,
        'totalBytes': roomsTotalBytes,
      },
      'roomBreakdown': roomBreakdown,
    };
  }

  Map<String, dynamic> getPerfSnapshot() => PerfTracker.instance.snapshot();

  Uint8List? getRoomHistoryPng(
      String roomId, int round, String fingerprintHex) {
    final room = rooms[roomId];
    if (room == null) return null;
    if (round <= 0) return null;

    Map<String, dynamic>? entry;
    for (final h in room.roundHistory) {
      final r = h['round'];
      if (r is int && r == round) {
        entry = h;
        break;
      }
      if (r != null && r.toString() == round.toString()) {
        entry = h;
        break;
      }
    }
    if (entry == null) return null;
    final drawings = entry['memberDrawings'];
    if (drawings is Map) {
      final v = drawings[fingerprintHex];
      if (v is Uint8List) return v;
    }
    return null;
  }

  /// 服务端启动事件
  final _onStartedController = StreamController<void>.broadcast();
  Stream<void> get onStarted => _onStartedController.stream;

  /// 服务端停止事件
  final _onStoppedController = StreamController<void>.broadcast();
  Stream<void> get onStopped => _onStoppedController.stream;

  /// 客户端连接事件
  final _onClientConnectedController = StreamController<Socket>.broadcast();
  Stream<Socket> get onClientConnected => _onClientConnectedController.stream;

  /// 客户端断开事件
  final _onClientDisconnectedController = StreamController<Socket>.broadcast();
  Stream<Socket> get onClientDisconnected =>
      _onClientDisconnectedController.stream;

  /// 格式化日志输出
  @override
  void log(
    String message, {
    String? room,
    String? username,
    String? fingerprintHex,
    String? ip,
    String? action,
    String? content,
  }) {
    _log(
      message,
      username: username,
      fingerprintHex: fingerprintHex,
      ip: ip,
      action: action,
      room: room,
      content: content,
    );
  }

  /// 内部日志实现
  void _log(String message,
      {String? username,
      String? fingerprintHex,
      String? ip,
      String? action,
      String? room,
      String? content}) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    StringBuffer sb = StringBuffer('[$timeStr]');

    String userStr = '未登录';
    if (username != null) {
      if (fingerprintHex != null) {
        userStr = '$username($fingerprintHex)';
      } else {
        userStr = username;
      }
      if (ip != null) {
        userStr = '$userStr@$ip';
      }
    }
    sb.write(' [用户: $userStr]');

    if (action != null) sb.write(' [操作: $action]');
    if (room != null) sb.write(' [房间: $room]');
    if (content != null) sb.write(' [内容: $content]');
    sb.write(' $message');

    print(sb.toString());
  }

  /// 启动服务
  Future<void> start() async {
    if (_isRunning) return;

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
      );

      _isRunning = true;
      _onStartedController.add(null);
      PerfTracker.instance.startDriftProbe();

      _log('TCP 服务端已启动, 端口: $port');

      // 监听连接
      _serverSocket!.listen(
        _handleConnection,
        onError: (error) {
          _log('服务端错误: $error');
        },
        onDone: () {
          stop();
        },
      );

      _idleSweepTimer?.cancel();
      _idleSweepTimer = Timer.periodic(_idleSweepInterval, (_) {
        if (!_isRunning) return;
        _sweepIdleClients();
      });
    } catch (e) {
      _log('启动服务端失败: $e');
      rethrow;
    }
  }

  /// 停止服务
  Future<void> stop() async {
    if (!_isRunning) return;

    _isRunning = false;
    PerfTracker.instance.stopDriftProbe();

    _idleSweepTimer?.cancel();
    _idleSweepTimer = null;

    // 关闭所有客户端连接
    for (final socket in clients.keys.toList()) {
      await socket.close();
    }
    clients.clear();

    for (final room in rooms.values) {
      room.phaseTimer?.cancel();
      room.phaseEndAt = null;
    }

    // 关闭服务端
    await _serverSocket?.close();
    _serverSocket = null;

    _onStoppedController.add(null);
    _log('TCP 服务端已停止');
  }

  void _sweepIdleClients() {
    final now = DateTime.now();
    final entries = clients.entries.toList(growable: false);
    for (final e in entries) {
      final socket = e.key;
      final session = e.value;

      if (!session.isAuthenticated) {
        if (now.difference(session.connectedAt) > _handshakeTimeout) {
          disconnectClient(socket, reason: 'HANDSHAKE_TIMEOUT');
        }
        continue;
      }

      if (now.difference(session.lastActiveAt) > _authenticatedIdleTimeout) {
        disconnectClient(socket, reason: 'IDLE_TIMEOUT');
      }
    }
  }

  /// 处理客户端连接
  void _handleConnection(Socket socket) {
    // 检查连接数限制
    if (clients.length >= maxConnections) {
      _log(
          '连接数已达上限($maxConnections)，拒绝新连接: ${socket.remoteAddress.address}:${socket.remotePort}');
      socket.destroy();
      return;
    }

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    final session = ClientSession();
    session.ip = socket.remoteAddress.address;
    clients[socket] = session;

    _log('客户端连接: ${socket.remoteAddress.address}:${socket.remotePort}');
    _onClientConnectedController.add(socket);

    socket.listen(
      (data) => _handleData(socket, session, data),
      onError: (error) {
        _log('客户端错误: $error',
            username: session.username,
            fingerprintHex: session.fingerprintHex,
            ip: session.ip);
        _removeClient(socket);
      },
      onDone: () {
        _removeClient(socket);
      },
    );

    // 写入错误可能不会进入 socket.listen 的 onError（在异步 write event 中触发）。
    // 这里兜底捕获，避免未处理异常导致服务端进程退出。
    socket.done.catchError((error) {
      _log('客户端写入错误: $error',
          username: session.username,
          fingerprintHex: session.fingerprintHex,
          ip: session.ip);
      _removeClient(socket);
    });
  }

  /// 处理接收的数据
  void _handleData(Socket socket, ClientSession session, Uint8List data) {
    // 将数据添加到缓冲区
    session.buffer.addAll(data);

    final maxBufferBytes = session.isAuthenticated
        ? _maxSessionBufferBytes
        : _maxPreAuthSessionBufferBytes;
    if (session.buffer.length > maxBufferBytes) {
      disconnectClient(
        socket,
        reason: session.isAuthenticated
            ? 'BUFFER_OVERFLOW'
            : 'BUFFER_OVERFLOW_PREAUTH',
      );
      return;
    }

    // 尝试解析消息
    while (session.buffer.length >= ProtocolHandler.headerLength) {
      final b0 = session.buffer[0];
      final b1 = session.buffer[1];
      final b2 = session.buffer[2];
      final b3 = session.buffer[3];
      final totalLength = ((b0 & 0xFF) << 24) |
          ((b1 & 0xFF) << 16) |
          ((b2 & 0xFF) << 8) |
          (b3 & 0xFF);
      final messageType = MessageType.fromCode(session.buffer[4] & 0xFF);

      if (totalLength < ProtocolHandler.headerLength) {
        disconnectClient(socket, reason: 'BAD_HEADER');
        return;
      }

      final maxMessageBytes = session.isAuthenticated
          ? _maxSessionBufferBytes
          : _maxPreAuthSessionBufferBytes;
      if (totalLength > maxMessageBytes) {
        disconnectClient(socket, reason: 'MESSAGE_TOO_LARGE');
        return;
      }

      // 检查是否收到完整消息
      if (session.buffer.length < totalLength) break;

      final payloadLen = totalLength - ProtocolHandler.headerLength;
      final payload = payloadLen <= 0
          ? Uint8List(0)
          : Uint8List.fromList(
              session.buffer.sublist(ProtocolHandler.headerLength, totalLength),
            );

      // 从缓冲区移除已处理的消息
      session.buffer.removeRange(0, totalLength);

      // 收到完整协议消息，更新最后活跃时间
      session.lastActiveAt = DateTime.now();

      // 处理消息
      _handleMessage(socket, session, messageType, payload);
    }
  }

  /// 处理消息
  void _handleMessage(
    Socket socket,
    ClientSession session,
    MessageType type,
    Uint8List payload,
  ) {
    PerfTracker.instance.countMessage(type.name);
    switch (type) {
      case MessageType.loginRequest:
        handleLoginRequest(socket, session, payload);
        break;

      case MessageType.serverInfoRequest:
        handleServerInfoRequest(socket);
        break;

      case MessageType.heartbeat:
        handleHeartbeat(socket, payload);
        break;

      case MessageType.createRoomRequest:
        handleCreateRoom(socket, session, payload);
        break;

      case MessageType.roomListRequest:
        handleRoomListRequest(socket);
        break;

      case MessageType.joinRoomRequest:
        handleJoinRoom(socket, session, payload);
        break;

      case MessageType.leaveRoomRequest:
        handleLeaveRoom(socket, session, payload);
        break;

      case MessageType.roomMemberRequest:
        handleRoomMemberRequest(socket, payload);
        break;

      case MessageType.reconnectRoomRequest:
        handleReconnectRoom(socket, session, payload);
        break;

      case MessageType.collabDelta:
        handleCollabDelta(socket, session, payload);
        break;

      case MessageType.collabSyncRequest:
        handleCollabSyncRequest(socket, session, payload);
        break;

      case MessageType.collabSnapshotFromOwner:
        handleCollabSnapshotFromOwner(socket, session, payload);
        break;

      case MessageType.collabLayerOpRequest:
        handleCollabLayerOp(socket, session, payload);
        break;

      case MessageType.collabLayerDelta:
        handleCollabLayerDelta(socket, session, payload);
        break;

      case MessageType.chatMessage:
        handleChatMessage(socket, session, payload);
        break;

      case MessageType.updateRoomRequest:
        handleUpdateRoomRequest(socket, session, payload);
        break;

      case MessageType.transferRoomRequest:
        handleTransferRoomRequest(socket, session, payload);
        break;

      case MessageType.readyRequest:
        _handleReadyRequest(socket, session, payload);
        break;

      case MessageType.lexiconUpload:
        _handleLexiconUpload(socket, session, payload);
        break;

      case MessageType.lexiconRequest:
        _handleLexiconRequest(socket, session);
        break;

      case MessageType.gameStart:
        _handleGameStart(socket, session, payload);
        break;

      case MessageType.cardPick:
        handleCardPick(socket, session, payload);
        break;

      case MessageType.drawingUpload:
        handleDrawingUpload(socket, session, payload);
        break;

      case MessageType.guessSubmit:
        handleGuessSubmit(socket, session, payload);
        break;

      case MessageType.drawingComplete:
        handleDrawingComplete(socket, session);
        break;

      case MessageType.replayAck:
        handleReplayAck(socket, session, payload);
        break;

      case MessageType.voteSubmit:
        handleVoteSubmit(socket, session, payload);
        break;

      case MessageType.favoriteSubmit:
        handleFavoriteSubmit(socket, session, payload);
        break;

      case MessageType.disconnect:
        _removeClient(socket);
        break;

      default:
        _sendError(socket, '未知消息类型: ${type.code}');
    }
  }

  /// 发送错误消息
  @override
  void sendError(Socket socket, String errorMessage) {
    _sendError(socket, errorMessage);
  }

  @override
  void disconnectClient(Socket socket, {String? reason}) {
    final session = clients[socket];
    _log(
      '断开连接${reason == null || reason.isEmpty ? "" : ": $reason"}',
      username: session?.username,
      fingerprintHex: session?.fingerprintHex,
      ip: session?.ip,
      action: 'DISCONNECT',
    );
    _removeClient(socket);
  }

  /// 移除客户端连接并清理状态
  void _removeClient(Socket socket) {
    final session = clients.remove(socket);
    if (session == null) return;

    // 离开所在房间
    _removeFromRoom(socket, session);

    _onClientDisconnectedController.add(socket);
    try {
      socket.destroy();
    } catch (_) {}
  }

  /// 内部发送错误实现
  void _sendError(Socket socket, String message) {
    final errorBytes = Uint8List.fromList(message.codeUnits);
    final payload = Uint8List(1 + errorBytes.length);
    payload[0] = errorBytes.length;
    payload.setAll(1, errorBytes);

    final messageData = ProtocolHandler.encode(MessageType.error, payload);
    socket.add(messageData);
  }

  int _secondsRemaining(DateTime? endAt, {int fallback = 1}) {
    if (endAt == null) return fallback;
    final diff = endAt.difference(DateTime.now()).inSeconds;
    if (diff <= 0) return 0;
    return diff;
  }

  @override
  void syncStateAfterRebind(
    RoomData room,
    Socket socket,
    ClientSession session,
  ) {
    final fp = session.fingerprintHex;
    if (fp == null) return;

    // 补发词库（如果有）
    if (room.lexiconJson != null && room.lexiconJson!.isNotEmpty) {
      try {
        socket.add(ProtocolHandler.encode(MessageType.lexiconData,
            Uint8List.fromList(utf8.encode(room.lexiconJson!))));
      } catch (_) {}
    }

    // 按当前阶段补发必要广播/私发
    if (room.gamePhase == GamePhase.wordPicking) {
      final fpToName = {
        for (final m in room.members) m.fingerprintHex: m.username
      };
      final ownerNames = room.wordCardOwnerFps
          .map((ownerFp) => fpToName[ownerFp] ?? '未知')
          .toList(growable: false);

      final excludeIdx = room.currentRound == 1
          ? -1
          : (room.wordCardGuesserFps.indexOf(fp) >= 0
              ? room.wordCardGuesserFps.indexOf(fp)
              : room.wordCardOwnerFps.indexOf(fp));

      final remaining = _secondsRemaining(room.phaseEndAt, fallback: 10);
      final phase = WordPickPhaseBroadcast(
        round: room.currentRound,
        totalRounds: room.rounds,
        wordPickTime: remaining,
        cardCount: room.wordCards.length,
        excludeCardIndex: excludeIdx,
        ownerNames: ownerNames,
      );
      try {
        socket.add(ProtocolHandler.encode(
            MessageType.wordPickPhaseBroadcast, phase.encode()));
      } catch (_) {}

      // 补发已发生的翻牌选择
      for (final entry in room.wordCardPicks.entries) {
        final cardIndex = entry.key;
        final pickerFp = entry.value;
        final pickerName = fpToName[pickerFp] ?? '';
        final pickBroadcast = CardPickBroadcast(
          cardIndex: cardIndex,
          username: pickerName,
          fingerprintHex: pickerFp,
        );
        try {
          socket.add(ProtocolHandler.encode(
              MessageType.wordPickBroadcast, pickBroadcast.encode()));
        } catch (_) {}
      }

      // 如果本人已分配词条，私发一次词条结果
      final myWord = room.memberDrawWords[fp];
      if (myWord != null && myWord.isNotEmpty) {
        final result = WordPickResult(word: myWord);
        try {
          socket.add(ProtocolHandler.encode(
              MessageType.wordPickResult, result.encode()));
        } catch (_) {}
      }
    } else if (room.gamePhase == GamePhase.drawing) {
      final remaining =
          _secondsRemaining(room.phaseEndAt, fallback: room.roundTime);
      final word = room.memberDrawWords[fp] ?? '';
      final broadcast = DrawingPhaseBroadcast(
        round: room.currentRound,
        totalRounds: room.rounds,
        drawTime: remaining,
        word: word,
        memberWords: room.memberDrawWords.map((k, v) =>
            MapEntry(k, room.members.indexWhere((m) => m.fingerprintHex == k))),
      );
      try {
        socket.add(ProtocolHandler.encode(
            MessageType.drawingPhaseBroadcast, broadcast.encode()));
      } catch (_) {}
    } else if (room.gamePhase == GamePhase.cardPicking ||
        room.gamePhase == GamePhase.guessing) {
      final remaining = _secondsRemaining(room.phaseEndAt, fallback: 10);
      final cards = room.guessCards;
      final phase = GuessPhaseBroadcast(
        round: room.currentRound,
        totalRounds: room.rounds,
        guessTime: room.gamePhase == GamePhase.guessing ? remaining : 30,
        cardPickTime: room.gamePhase == GamePhase.cardPicking ? remaining : 0,
        cards: cards,
      );
      try {
        socket.add(ProtocolHandler.encode(
            MessageType.guessPhaseBroadcast, phase.encode()));
      } catch (_) {}

      // 补发已发生的选牌
      for (final entry in room.guessCardPicks.entries) {
        final cardIndex = entry.key;
        final pickerFp = entry.value;
        final pickerName = room.members
            .firstWhere((m) => m.fingerprintHex == pickerFp,
                orElse: () =>
                    RoomMember(username: '', fingerprintHex: pickerFp))
            .username;
        final pickBroadcast = CardPickBroadcast(
          cardIndex: cardIndex,
          username: pickerName,
          fingerprintHex: pickerFp,
        );
        try {
          socket.add(ProtocolHandler.encode(
              MessageType.cardPickBroadcast, pickBroadcast.encode()));
        } catch (_) {}
      }

      // guessing 阶段：如果本人已选牌，补发图片
      if (room.gamePhase == GamePhase.guessing) {
        final myPickEntry = room.guessCardPicks.entries
            .where((e) => e.value == fp)
            .cast<MapEntry<int, String>>()
            .toList();
        if (myPickEntry.isNotEmpty) {
          final cardIndex = myPickEntry.first.key;
          if (cardIndex >= 0 && cardIndex < room.guessCards.length) {
            final card = room.guessCards[cardIndex];
            final drawerFp = card.fingerprintHex;
            final pngData = room.memberDrawings[drawerFp];
            if (pngData != null) {
              final imgData = DrawingImageData(
                fingerprintHex: drawerFp,
                username: card.username,
                pngData: pngData,
              );
              try {
                socket.add(ProtocolHandler.encode(
                    MessageType.drawingImageData, imgData.encode()));
              } catch (_) {}
            }
          }
        }
      }
    } else if (room.gamePhase == GamePhase.reviewing) {
      // 复盘阶段：保证客户端有复盘数据和进度
      try {
        socket.add(ProtocolHandler.encode(
            MessageType.reviewPhaseBroadcast, Uint8List(0)));
      } catch (_) {}
      if (room.lastReplayFile != null) {
        final replayBroadcast =
            ReplayFileBroadcast(replay: room.lastReplayFile!);
        try {
          socket.add(ProtocolHandler.encode(
              MessageType.replayFileBroadcast, replayBroadcast.encode()));
        } catch (_) {}
      }
      final progress = ReviewProgressBroadcast(
        pathIndex: room.currentReviewPathIndex,
        stepIndex: room.currentReviewStepIndex,
      );
      try {
        socket.add(ProtocolHandler.encode(
            MessageType.reviewProgressBroadcast, progress.encode()));
      } catch (_) {}

      if (room.reviewSubPhase == ReviewSubPhase.voting) {
        try {
          socket.add(ProtocolHandler.encode(
              MessageType.voteStartBroadcast, Uint8List(0)));
        } catch (_) {}
      }
    }
  }

  /// 处理准备/取消准备请求
  /// payload格式: [isReady(1字节)] 1=准备, 0=取消准备
  void _handleReadyRequest(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      if (payload.isEmpty) return;
      final isReady = payload[0] == 1;
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null) return;

      // 找到对应成员并更新准备状态
      for (final member in room.members) {
        if (member.fingerprintHex == session.fingerprintHex) {
          member.isReady = isReady;
          break;
        }
      }

      _log('${isReady ? "准备" : "取消准备"}: $roomId',
          username: session.username,
          fingerprintHex: session.fingerprintHex,
          action: 'READY');

      // 广播更新后的成员列表
      _broadcastRoomMembers(roomId);
    } catch (e) {
      _log('处理准备请求失败: $e', username: session.username, action: 'READY_ERROR');
    }
  }

  /// 处理词库上传
  /// payload格式: [lexiconJson UTF-8 bytes]
  void _handleLexiconUpload(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null) return;

      // 仅房主可上传词库
      if (session.fingerprintHex != room.ownerFingerprintHex) {
        _log('非房主尝试上传词库',
            username: session.username, action: 'LEXICON_UPLOAD_DENIED');
        return;
      }

      final lexiconJson = utf8.decode(payload);
      room.lexiconJson = lexiconJson;

      _log('词库已上传 (${payload.length} bytes)',
          username: session.username, action: 'LEXICON_UPLOAD', room: roomId);

      // 广播词库数据给所有房间成员
      _broadcastLexiconData(room);
    } catch (e) {
      _log('处理词库上传失败: $e',
          username: session.username, action: 'LEXICON_UPLOAD_ERROR');
    }
  }

  /// 处理词库请求（成员加入后请求当前词库）
  void _handleLexiconRequest(
    Socket socket,
    ClientSession session,
  ) {
    try {
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null) return;

      if (room.lexiconJson != null && room.lexiconJson!.isNotEmpty) {
        final data = utf8.encode(room.lexiconJson!);
        socket.add(ProtocolHandler.encode(
            MessageType.lexiconData, Uint8List.fromList(data)));
      }
    } catch (e) {
      _log('处理词库请求失败: $e',
          username: session.username, action: 'LEXICON_REQUEST_ERROR');
    }
  }

  /// 广播词库数据给房间所有成员
  void _broadcastLexiconData(RoomData room) {
    if (room.lexiconJson == null || room.lexiconJson!.isEmpty) return;
    final data = utf8.encode(room.lexiconJson!);
    RoomBroadcaster.broadcast(
        room, MessageType.lexiconData, Uint8List.fromList(data));
  }

  /// 处理游戏开始请求（房主发起，触发多回合游戏流程）
  void _handleGameStart(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null) return;

      // 仅房主可发起游戏
      if (session.fingerprintHex != room.ownerFingerprintHex) {
        _log('非房主尝试发起游戏',
            username: session.username, action: 'GAME_START_DENIED');
        return;
      }

      if (room.gamePhase != GamePhase.idle) {
        _log('游戏已在进行中',
            username: session.username, action: 'GAME_START_DENIED');
        return;
      }

      _log('游戏开始',
          username: session.username, action: 'GAME_START', room: roomId);

      // 广播游戏开始（兼容旧版客户端的卡牌选择）
      RoomBroadcaster.broadcast(room, MessageType.gameStartBroadcast, payload);

      // 启动多回合游戏流程：进入第一回合的作画阶段
      room.lastReplayFile = null;
      room.resetGame();
      startNextRound(room);
    } catch (e) {
      _log('处理游戏开始失败: $e',
          username: session.username, action: 'GAME_START_ERROR');
    }
  }

  /// 将用户从当前房间移除
  void _removeFromRoom(Socket socket, ClientSession session) {
    final roomId = session.currentRoomId;
    if (roomId == null) return;
    final room = rooms[roomId];
    if (room == null) return;

    // 游戏开始后：成员离开/断线只做“离线占位”，不移除成员列表
    if (room.gamePhase != GamePhase.idle) {
      final memberIdx = room.members
          .indexWhere((m) => m.fingerprintHex == session.fingerprintHex);
      if (memberIdx >= 0) {
        room.members[memberIdx].isOnline = false;

        // 将对应socket置空（优先按socket查找，否则按memberIdx对齐）
        final socketIdx = room.memberSockets.indexOf(socket);
        if (socketIdx >= 0) {
          room.memberSockets[socketIdx] = null;
        } else if (memberIdx < room.memberSockets.length) {
          room.memberSockets[memberIdx] = null;
        }

        _log('成员离线占位: $roomId',
            username: session.username,
            fingerprintHex: session.fingerprintHex,
            ip: session.ip,
            action: 'MEMBER_OFFLINE');

        _broadcastRoomMembers(roomId);
      }

      session.currentRoomId = null;
      return;
    }

    final isOwnerLeaving = room.ownerUsername == session.username &&
        room.ownerFingerprintHex == session.fingerprintHex;

    // idle阶段：协同房间的房主离线需要“占位”，用于客户端灰显；其他情况保持原逻辑
    final idx = room.memberSockets.indexOf(socket);
    if (idx >= 0) {
      if (room.roomType.code == 0x02 && isOwnerLeaving) {
        room.members[idx].isOnline = false;
        room.memberSockets[idx] = null;
      } else {
        room.memberSockets.removeAt(idx);
        room.members.removeAt(idx);
      }
    }
    session.currentRoomId = null;

    _log('离开房间: $roomId',
        username: session.username,
        fingerprintHex: session.fingerprintHex,
        ip: session.ip);

    // 如果房间空了，自动删除
    if (room.memberSockets.where((s) => s != null).isEmpty) {
      rooms.remove(roomId);
      _log('房间已空，自动删除: $roomId');
    } else if (isOwnerLeaving) {
      // 房主离开：协同房间不自动转让（保持 owner 信息，用于列表标注离线）
      if (room.roomType.code != 0x02) {
        _transferRoomOwnership(room);
      } else {
        _broadcastRoomMembers(roomId);
      }
    } else {
      _broadcastRoomMembers(roomId);
    }
  }

  /// 转让房间所有权
  void _transferRoomOwnership(RoomData room) {
    if (room.members.isEmpty) return;

    // 新房主是列表中的第一位
    final newOwner = room.members.first;
    final roomId = room.roomId;

    // 更新房间数据（roomId保持不变，只更新owner）
    room.ownerUsername = newOwner.username;
    room.ownerFingerprintHex = newOwner.fingerprintHex;

    _log('房间转让: $roomId, 新房主: ${newOwner.username}');

    // 广播转让通知
    final transfer = RoomOwnerTransfer(
      oldRoomId: roomId,
      newRoomId: roomId, // roomId不变
      newOwnerUsername: newOwner.username,
      newOwnerFingerprintHex: newOwner.fingerprintHex,
    );
    final msg = ProtocolHandler.encode(
      MessageType.roomOwnerTransfer,
      transfer.encode(),
    );
    // 推送给所有已登录客户端（包含大厅列表观察者）
    for (final e in clients.entries) {
      final s = e.key;
      final sess = e.value;
      if (!sess.isAuthenticated) continue;
      try {
        s.add(msg);
      } catch (_) {}
    }

    // 广播成员更新（使用新的房间ID）
    _broadcastRoomMembers(roomId);
  }

  /// 向房间内所有成员推送成员列表
  @override
  void broadcastRoomMembers(String roomId) {
    _broadcastRoomMembers(roomId);
  }

  void _broadcastRoomMembers(String roomId) {
    final room = rooms[roomId];
    if (room == null) return;

    final update = RoomMemberUpdate(
      roomId: roomId,
      members: room.members,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.roomMemberUpdate,
      update.encode(),
    );
  }

  /// 广播房间设置更新
  @override
  void broadcastRoomSetting(String roomId) {
    _broadcastRoomSetting(roomId);
  }

  void _broadcastRoomSetting(String roomId) {
    final room = rooms[roomId];
    if (room == null) return;

    final update = RoomSettingUpdate(
      roomId: roomId,
      roomName: room.roomName,
      roomTypeCode: room.roomType.code,
      maxPlayers: room.maxPlayers,
      rounds: room.rounds,
      roundTime: room.roundTime,
      lexiconKey: room.lexiconKey,
      canvasWidth: room.canvasWidth,
      canvasHeight: room.canvasHeight,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.roomSettingUpdate,
      update.encode(),
    );
  }

  /// 注册用户 (用于测试)
  void registerUser(String username, String privateKeyHex) {
    authService.registerUser(username, privateKeyHex);
  }
}
