import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/utils/identity_utils.dart';

/// 连接状态
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticating,
  authenticated,
  error,
}

class CollabDeltaRequest {
  final int epoch;
  final int baseRev;
  final int x;
  final int y;
  final int width;
  final int height;
  final int flags;
  final Uint8List payload;

  CollabDeltaRequest({
    required this.epoch,
    required this.baseRev,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.flags,
    required this.payload,
  });

  Uint8List encode() {
    final buffer = BytesBuilder();
    final header = ByteData(4 + 4 + 2 + 2 + 2 + 2 + 1 + 4);
    header.setUint32(0, epoch, Endian.big);
    header.setUint32(4, baseRev, Endian.big);
    header.setUint16(8, x, Endian.big);
    header.setUint16(10, y, Endian.big);
    header.setUint16(12, width, Endian.big);
    header.setUint16(14, height, Endian.big);
    header.setUint8(16, flags);
    header.setUint32(17, payload.length, Endian.big);
    buffer.add(header.buffer.asUint8List());
    buffer.add(payload);
    return buffer.toBytes();
  }

  static CollabDeltaRequest decode(Uint8List data) {
    if (data.length < 21) {
      throw FormatException('collabDelta payload too short');
    }
    final header = ByteData.sublistView(data, 0, 21);
    final epoch = header.getUint32(0, Endian.big);
    final baseRev = header.getUint32(4, Endian.big);
    final x = header.getUint16(8, Endian.big);
    final y = header.getUint16(10, Endian.big);
    final width = header.getUint16(12, Endian.big);
    final height = header.getUint16(14, Endian.big);
    final flags = header.getUint8(16);
    final len = header.getUint32(17, Endian.big);
    if (data.length < 21 + len) {
      throw FormatException('collabDelta payload length mismatch');
    }
    final payload = data.sublist(21, 21 + len);
    return CollabDeltaRequest(
      epoch: epoch,
      baseRev: baseRev,
      x: x,
      y: y,
      width: width,
      height: height,
      flags: flags,
      payload: Uint8List.fromList(payload),
    );
  }
}

class CollabSyncRequest {
  final String requesterUsername;
  final int clientEpoch;
  final int clientRev;

  CollabSyncRequest({
    required this.requesterUsername,
    required this.clientEpoch,
    required this.clientRev,
  });

  Uint8List encode() {
    final userBytes = utf8.encode(requesterUsername);
    final userLen = userBytes.length.clamp(0, 255);
    final buffer = BytesBuilder();
    buffer.addByte(userLen);
    if (userLen > 0) {
      buffer.add(Uint8List.fromList(userBytes.sublist(0, userLen)));
    }
    final header = ByteData(8);
    header.setUint32(0, clientEpoch, Endian.big);
    header.setUint32(4, clientRev, Endian.big);
    buffer.add(header.buffer.asUint8List());
    return buffer.toBytes();
  }

  static CollabSyncRequest decode(Uint8List data) {
    if (data.isEmpty) {
      throw FormatException('collabSyncRequest payload too short');
    }
    int offset = 0;
    final userLen = data[offset++];
    if (data.length < offset + userLen + 4) {
      throw FormatException('collabSyncRequest payload too short');
    }
    final requesterUsername = utf8.decode(
      data.sublist(offset, offset + userLen),
    );
    offset += userLen;

    int clientEpoch = 0;
    int clientRev = 0;
    if (data.length >= offset + 8) {
      final header = ByteData.sublistView(data, offset, offset + 8);
      clientEpoch = header.getUint32(0, Endian.big);
      clientRev = header.getUint32(4, Endian.big);
    } else {
      final header = ByteData.sublistView(data, offset, offset + 4);
      clientRev = header.getUint32(0, Endian.big);
    }
    return CollabSyncRequest(
      requesterUsername: requesterUsername,
      clientEpoch: clientEpoch,
      clientRev: clientRev,
    );
  }
}

class CollabDeltaBroadcast {
  final int epoch;
  final int rev;
  final String senderId;
  final int x;
  final int y;
  final int width;
  final int height;
  final int flags;
  final Uint8List payload;

  CollabDeltaBroadcast({
    required this.epoch,
    required this.rev,
    required this.senderId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.flags,
    required this.payload,
  });

  Uint8List encode() {
    final senderBytes = utf8.encode(senderId);
    final senderLen = senderBytes.length.clamp(0, 255);
    final buffer = BytesBuilder();
    final fixed = ByteData(4 + 4 + 1);
    fixed.setUint32(0, epoch, Endian.big);
    fixed.setUint32(4, rev, Endian.big);
    fixed.setUint8(8, senderLen);
    buffer.add(fixed.buffer.asUint8List());
    if (senderLen > 0) {
      buffer.add(Uint8List.fromList(senderBytes.sublist(0, senderLen)));
    }

    final rest = ByteData(2 + 2 + 2 + 2 + 1 + 4);
    rest.setUint16(0, x, Endian.big);
    rest.setUint16(2, y, Endian.big);
    rest.setUint16(4, width, Endian.big);
    rest.setUint16(6, height, Endian.big);
    rest.setUint8(8, flags);
    rest.setUint32(9, payload.length, Endian.big);
    buffer.add(rest.buffer.asUint8List());
    buffer.add(payload);
    return buffer.toBytes();
  }

  static CollabDeltaBroadcast decode(Uint8List data) {
    if (data.length < 9) {
      throw FormatException('collabDeltaBroadcast payload too short');
    }
    int offset = 0;
    final epoch = ByteData.sublistView(
      data,
      offset,
      offset + 4,
    ).getUint32(0, Endian.big);
    offset += 4;
    final rev = ByteData.sublistView(
      data,
      offset,
      offset + 4,
    ).getUint32(0, Endian.big);
    offset += 4;
    final senderLen = data[offset++];
    if (data.length < offset + senderLen + 13) {
      throw FormatException('collabDeltaBroadcast payload too short');
    }
    final senderId = utf8.decode(data.sublist(offset, offset + senderLen));
    offset += senderLen;
    final rest = ByteData.sublistView(data, offset, offset + 13);
    final x = rest.getUint16(0, Endian.big);
    final y = rest.getUint16(2, Endian.big);
    final width = rest.getUint16(4, Endian.big);
    final height = rest.getUint16(6, Endian.big);
    final flags = rest.getUint8(8);
    final len = rest.getUint32(9, Endian.big);
    offset += 13;
    if (data.length < offset + len) {
      throw FormatException('collabDeltaBroadcast payload length mismatch');
    }
    final payload = data.sublist(offset, offset + len);
    return CollabDeltaBroadcast(
      epoch: epoch,
      rev: rev,
      senderId: senderId,
      x: x,
      y: y,
      width: width,
      height: height,
      flags: flags,
      payload: Uint8List.fromList(payload),
    );
  }
}

class CollabSyncRequired {
  final int authoritativeEpoch;
  final int authoritativeRev;

  CollabSyncRequired({
    required this.authoritativeEpoch,
    required this.authoritativeRev,
  });

  static CollabSyncRequired decode(Uint8List payload) {
    if (payload.length < 4) {
      throw FormatException('collabSyncRequired payload too short');
    }
    if (payload.length >= 8) {
      final data = ByteData.sublistView(payload, 0, 8);
      return CollabSyncRequired(
        authoritativeEpoch: data.getUint32(0, Endian.big),
        authoritativeRev: data.getUint32(4, Endian.big),
      );
    }
    final rev = ByteData.sublistView(payload, 0, 4).getUint32(0, Endian.big);
    return CollabSyncRequired(authoritativeEpoch: 0, authoritativeRev: rev);
  }
}

class CollabSnapshotFromOwner {
  final String targetUsername;
  final int rev;
  final int width;
  final int height;
  final int flags;
  final Uint8List rgbaZlib;

  CollabSnapshotFromOwner({
    required this.targetUsername,
    required this.rev,
    required this.width,
    required this.height,
    required this.flags,
    required this.rgbaZlib,
  });

  Uint8List encode() {
    final targetBytes = utf8.encode(targetUsername);
    final targetLen = targetBytes.length.clamp(0, 255);
    final buffer = BytesBuilder();
    buffer.addByte(targetLen);
    if (targetLen > 0) {
      buffer.add(Uint8List.fromList(targetBytes.sublist(0, targetLen)));
    }

    final header = ByteData(4 + 2 + 2 + 1 + 4);
    header.setUint32(0, rev, Endian.big);
    header.setUint16(4, width, Endian.big);
    header.setUint16(6, height, Endian.big);
    header.setUint8(8, flags);
    header.setUint32(9, rgbaZlib.length, Endian.big);
    buffer.add(header.buffer.asUint8List());
    buffer.add(rgbaZlib);
    return buffer.toBytes();
  }

  static CollabSnapshotFromOwner decode(Uint8List data) {
    if (data.isEmpty) {
      throw FormatException('collabSnapshotFromOwner payload too short');
    }
    int offset = 0;
    final targetLen = data[offset++];
    if (data.length < offset + targetLen + 13) {
      throw FormatException('collabSnapshotFromOwner payload too short');
    }
    final targetUsername = utf8.decode(
      data.sublist(offset, offset + targetLen),
    );
    offset += targetLen;
    final header = ByteData.sublistView(data, offset, offset + 13);
    final rev = header.getUint32(0, Endian.big);
    final width = header.getUint16(4, Endian.big);
    final height = header.getUint16(6, Endian.big);
    final flags = header.getUint8(8);
    final len = header.getUint32(9, Endian.big);
    offset += 13;
    if (data.length < offset + len) {
      throw FormatException('collabSnapshotFromOwner payload length mismatch');
    }
    final rgbaZlib = data.sublist(offset, offset + len);
    return CollabSnapshotFromOwner(
      targetUsername: targetUsername,
      rev: rev,
      width: width,
      height: height,
      flags: flags,
      rgbaZlib: Uint8List.fromList(rgbaZlib),
    );
  }
}

class CollabSnapshotFromServer {
  final int epoch;
  final int rev;
  final int width;
  final int height;
  final int flags;
  final Uint8List rgbaZlib;

  CollabSnapshotFromServer({
    required this.epoch,
    required this.rev,
    required this.width,
    required this.height,
    required this.flags,
    required this.rgbaZlib,
  });

  static CollabSnapshotFromServer decode(Uint8List data) {
    if (data.length < 17) {
      throw FormatException('collabSnapshotFromServer payload too short');
    }
    int offset = 0;
    final header = ByteData.sublistView(data, offset, offset + 17);
    final epoch = header.getUint32(0, Endian.big);
    final rev = header.getUint32(4, Endian.big);
    final width = header.getUint16(8, Endian.big);
    final height = header.getUint16(10, Endian.big);
    final flags = header.getUint8(12);
    final len = header.getUint32(13, Endian.big);
    offset += 17;
    if (data.length < offset + len) {
      throw FormatException('collabSnapshotFromServer payload length mismatch');
    }
    final rgbaZlib = data.sublist(offset, offset + len);
    return CollabSnapshotFromServer(
      epoch: epoch,
      rev: rev,
      width: width,
      height: height,
      flags: flags,
      rgbaZlib: Uint8List.fromList(rgbaZlib),
    );
  }
}

// ========== 多图层协同协议（客户端镜像） ==========

/// 图层操作类型
enum CollabLayerOpType {
  add(1),
  remove(2),
  rename(3),
  reorder(4),
  setVisibility(5),
  setOpacity(6),
  setLock(7);

  final int code;
  const CollabLayerOpType(this.code);

  static CollabLayerOpType fromCode(int code) {
    return CollabLayerOpType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => CollabLayerOpType.add,
    );
  }
}

/// 图层操作请求（客户端→服务端）
class CollabLayerOpRequest {
  final CollabLayerOpType opType;
  final Map<String, dynamic> payload;

  CollabLayerOpRequest({required this.opType, required this.payload});

  Uint8List encode() {
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final buffer = BytesBuilder();
    buffer.addByte(opType.code);
    final lenData = ByteData(2);
    lenData.setUint16(0, jsonBytes.length, Endian.big);
    buffer.add(lenData.buffer.asUint8List());
    buffer.add(jsonBytes);
    return buffer.toBytes();
  }
}

/// 图层操作广播（服务端→客户端）
class CollabLayerOpBroadcast {
  final CollabLayerOpType opType;
  final Map<String, dynamic> payload;

  CollabLayerOpBroadcast({required this.opType, required this.payload});

  static CollabLayerOpBroadcast decode(Uint8List data) {
    if (data.length < 3) {
      throw FormatException('collabLayerOpBroadcast payload too short');
    }
    final opType = CollabLayerOpType.fromCode(data[0]);
    final payloadLen = ByteData.sublistView(
      data,
      1,
      3,
    ).getUint16(0, Endian.big);
    if (data.length < 3 + payloadLen) {
      throw FormatException('collabLayerOpBroadcast payload length mismatch');
    }
    final jsonStr = utf8.decode(data.sublist(3, 3 + payloadLen));
    final payload = payloadLen > 0
        ? jsonDecode(jsonStr) as Map<String, dynamic>
        : <String, dynamic>{};
    return CollabLayerOpBroadcast(opType: opType, payload: payload);
  }
}

/// 带 layerId 的增量 delta 请求（客户端→服务端）
class CollabLayerDeltaRequest {
  final String layerId;
  final int epoch;
  final int baseRev;
  final int x;
  final int y;
  final int width;
  final int height;
  final int flags;
  final Uint8List payload;

  CollabLayerDeltaRequest({
    required this.layerId,
    required this.epoch,
    required this.baseRev,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.flags,
    required this.payload,
  });

  Uint8List encode() {
    final idBytes = utf8.encode(layerId);
    final idLen = idBytes.length.clamp(0, 255);
    final buffer = BytesBuilder();
    buffer.addByte(idLen);
    if (idLen > 0) buffer.add(Uint8List.fromList(idBytes.sublist(0, idLen)));
    final header = ByteData(4 + 4 + 2 + 2 + 2 + 2 + 1 + 4);
    header.setUint32(0, epoch, Endian.big);
    header.setUint32(4, baseRev, Endian.big);
    header.setUint16(8, x, Endian.big);
    header.setUint16(10, y, Endian.big);
    header.setUint16(12, width, Endian.big);
    header.setUint16(14, height, Endian.big);
    header.setUint8(16, flags);
    header.setUint32(17, payload.length, Endian.big);
    buffer.add(header.buffer.asUint8List());
    buffer.add(payload);
    return buffer.toBytes();
  }
}

/// 带 layerId 的增量 delta 广播（服务端→客户端）
class CollabLayerDeltaBroadcast {
  final String layerId;
  final int epoch;
  final int rev;
  final String senderId;
  final int x;
  final int y;
  final int width;
  final int height;
  final int flags;
  final Uint8List payload;

  CollabLayerDeltaBroadcast({
    required this.layerId,
    required this.epoch,
    required this.rev,
    required this.senderId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.flags,
    required this.payload,
  });

  static CollabLayerDeltaBroadcast decode(Uint8List data) {
    if (data.isEmpty) {
      throw FormatException('collabLayerDeltaBroadcast payload too short');
    }
    int offset = 0;
    final idLen = data[offset++];
    if (data.length < offset + idLen + 8) {
      throw FormatException('collabLayerDeltaBroadcast payload too short');
    }
    final layerId = utf8.decode(data.sublist(offset, offset + idLen));
    offset += idLen;
    final epochRev = ByteData.sublistView(data, offset, offset + 8);
    final epoch = epochRev.getUint32(0, Endian.big);
    final rev = epochRev.getUint32(4, Endian.big);
    offset += 8;
    final senderLen = data[offset++];
    if (data.length < offset + senderLen + 13) {
      throw FormatException('collabLayerDeltaBroadcast payload too short');
    }
    final senderId = utf8.decode(data.sublist(offset, offset + senderLen));
    offset += senderLen;
    final rest = ByteData.sublistView(data, offset, offset + 13);
    final x = rest.getUint16(0, Endian.big);
    final y = rest.getUint16(2, Endian.big);
    final width = rest.getUint16(4, Endian.big);
    final height = rest.getUint16(6, Endian.big);
    final flags = rest.getUint8(8);
    final len = rest.getUint32(9, Endian.big);
    offset += 13;
    if (data.length < offset + len) {
      throw FormatException(
        'collabLayerDeltaBroadcast payload length mismatch',
      );
    }
    final payload = data.sublist(offset, offset + len);
    return CollabLayerDeltaBroadcast(
      layerId: layerId,
      epoch: epoch,
      rev: rev,
      senderId: senderId,
      x: x,
      y: y,
      width: width,
      height: height,
      flags: flags,
      payload: Uint8List.fromList(payload),
    );
  }
}

/// 多图层快照（服务端→客户端）
class CollabMultiLayerSnapshot {
  final int epoch;
  final int canvasWidth;
  final int canvasHeight;
  final List<CollabLayerSnapshotEntry> layers;

  CollabMultiLayerSnapshot({
    required this.epoch,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.layers,
  });

  static CollabMultiLayerSnapshot decode(Uint8List data) {
    if (data.length < 10) {
      throw FormatException('collabMultiLayerSnapshot payload too short');
    }
    int offset = 0;
    final header = ByteData.sublistView(data, 0, 10);
    final epoch = header.getUint32(0, Endian.big);
    final canvasWidth = header.getUint16(4, Endian.big);
    final canvasHeight = header.getUint16(6, Endian.big);
    final layerCount = header.getUint16(8, Endian.big);
    offset += 10;
    final layers = <CollabLayerSnapshotEntry>[];
    for (int i = 0; i < layerCount; i++) {
      final result = CollabLayerSnapshotEntry.decodeFrom(data, offset);
      layers.add(result.entry);
      offset = result.nextOffset;
    }
    return CollabMultiLayerSnapshot(
      epoch: epoch,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      layers: layers,
    );
  }
}

/// 多图层快照中的单层条目
class CollabLayerSnapshotEntry {
  final String layerId;
  final String name;
  final String ownerId;
  final bool isVisible;
  final bool isLocked;
  final int opacity; // 0-255
  final int blendMode;
  final int rev;
  final int rgbaFlags;
  final Uint8List rgbaBytes;

  CollabLayerSnapshotEntry({
    required this.layerId,
    required this.name,
    required this.ownerId,
    required this.isVisible,
    required this.isLocked,
    required this.opacity,
    required this.blendMode,
    required this.rev,
    required this.rgbaFlags,
    required this.rgbaBytes,
  });

  static ({CollabLayerSnapshotEntry entry, int nextOffset}) decodeFrom(
    Uint8List data,
    int offset,
  ) {
    final idLen = data[offset++];
    final layerId = utf8.decode(data.sublist(offset, offset + idLen));
    offset += idLen;

    final nameLen = data[offset++];
    final name = utf8.decode(data.sublist(offset, offset + nameLen));
    offset += nameLen;

    final ownerLen = data[offset++];
    final ownerId = utf8.decode(data.sublist(offset, offset + ownerLen));
    offset += ownerLen;

    final isVisible = data[offset++] == 1;
    final isLocked = data[offset++] == 1;
    final opacity = data[offset++];
    final blendMode = data[offset++];

    final tail = ByteData.sublistView(data, offset, offset + 9);
    final rev = tail.getUint32(0, Endian.big);
    final rgbaFlags = tail.getUint8(4);
    final rgbaLen = tail.getUint32(5, Endian.big);
    offset += 9;
    final rgbaBytes = data.sublist(offset, offset + rgbaLen);
    offset += rgbaLen;

    return (
      entry: CollabLayerSnapshotEntry(
        layerId: layerId,
        name: name,
        ownerId: ownerId,
        isVisible: isVisible,
        isLocked: isLocked,
        opacity: opacity,
        blendMode: blendMode,
        rev: rev,
        rgbaFlags: rgbaFlags,
        rgbaBytes: Uint8List.fromList(rgbaBytes),
      ),
      nextOffset: offset,
    );
  }
}

class ScorePodiumBroadcast {
  final String roomId;
  final int endAtMs;
  final List<Map<String, dynamic>> top3;

  ScorePodiumBroadcast({
    required this.roomId,
    required this.endAtMs,
    required this.top3,
  });

  static ScorePodiumBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    final top3Raw = map['top3'];
    final top3 = (top3Raw is List)
        ? top3Raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    return ScorePodiumBroadcast(
      roomId: (map['roomId'] ?? '').toString(),
      endAtMs: (map['endAtMs'] is int) ? map['endAtMs'] as int : 0,
      top3: top3,
    );
  }
}

class GameResetBroadcast {
  final String roomId;

  GameResetBroadcast({required this.roomId});

  static GameResetBroadcast decode(Uint8List payload) {
    if (payload.isEmpty) return GameResetBroadcast(roomId: '');
    final len = payload[0];
    final roomId = (payload.length >= 1 + len)
        ? utf8.decode(payload.sublist(1, 1 + len))
        : '';
    return GameResetBroadcast(roomId: roomId);
  }
}

class ReviewProgressBroadcast {
  final int pathIndex;
  final int stepIndex;

  ReviewProgressBroadcast({required this.pathIndex, required this.stepIndex});

  static ReviewProgressBroadcast decode(Uint8List payload) {
    if (payload.length < 4) {
      return ReviewProgressBroadcast(pathIndex: 0, stepIndex: 0);
    }
    final bd = ByteData.sublistView(payload);
    final path = bd.getUint16(0, Endian.big);
    final step = bd.getUint16(2, Endian.big);
    return ReviewProgressBroadcast(pathIndex: path, stepIndex: step);
  }
}

class FavoriteSelectionStartBroadcast {
  final String pickerUsername;

  FavoriteSelectionStartBroadcast({required this.pickerUsername});

  static FavoriteSelectionStartBroadcast decode(Uint8List payload) {
    if (payload.isEmpty) {
      return FavoriteSelectionStartBroadcast(pickerUsername: '');
    }
    final len = payload[0];
    final name = (payload.length >= 1 + len)
        ? utf8.decode(payload.sublist(1, 1 + len))
        : '';
    return FavoriteSelectionStartBroadcast(pickerUsername: name);
  }
}

class FavoriteResultBroadcast {
  final int drawingIndex;

  FavoriteResultBroadcast({required this.drawingIndex});

  static FavoriteResultBroadcast decode(Uint8List payload) {
    if (payload.isEmpty) return FavoriteResultBroadcast(drawingIndex: 0);
    return FavoriteResultBroadcast(drawingIndex: payload[0]);
  }
}

class ReplayAck {
  final String replayId;

  ReplayAck({required this.replayId});

  Uint8List encode() {
    final bytes = utf8.encode(replayId);
    final len = bytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len);
    buffer[0] = len;
    if (len > 0) buffer.setAll(1, bytes.sublist(0, len));
    return buffer;
  }
}

class ReplayFileBroadcast {
  final Map<String, dynamic> replay;

  ReplayFileBroadcast({required this.replay});

  static ReplayFileBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return ReplayFileBroadcast(replay: map);
  }
}

/// 连接状态信息
class ConnectionState {
  final ConnectionStatus status;
  final String serverIp;
  final int serverPort;
  final String serverName;
  final String? errorMessage;
  final bool isAuthenticated;
  final int currentConnections; // 当前连接数
  final int maxConnections; // 最大连接数
  final int currentRooms; // 当前房间数
  final int maxRooms; // 最大房间数

  const ConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.serverIp = '',
    this.serverPort = 9527,
    this.serverName = '',
    this.errorMessage,
    this.isAuthenticated = false,
    this.currentConnections = 0,
    this.maxConnections = 100,
    this.currentRooms = 0,
    this.maxRooms = 20,
  });

  /// 是否已连接
  bool get isConnected =>
      status == ConnectionStatus.connected ||
      status == ConnectionStatus.authenticating ||
      status == ConnectionStatus.authenticated;

  ConnectionState copyWith({
    ConnectionStatus? status,
    String? serverIp,
    int? serverPort,
    String? serverName,
    String? errorMessage,
    bool? isAuthenticated,
    int? currentConnections,
    int? maxConnections,
    int? currentRooms,
    int? maxRooms,
    bool clearError = false,
  }) {
    return ConnectionState(
      status: status ?? this.status,
      serverIp: serverIp ?? this.serverIp,
      serverPort: serverPort ?? this.serverPort,
      serverName: serverName ?? this.serverName,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      currentConnections: currentConnections ?? this.currentConnections,
      maxConnections: maxConnections ?? this.maxConnections,
      currentRooms: currentRooms ?? this.currentRooms,
      maxRooms: maxRooms ?? this.maxRooms,
    );
  }
}

class ChatMessage {
  final String roomId;
  final String sender;
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.roomId,
    required this.sender,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final senderBytes = utf8.encode(sender);
    final contentBytes = utf8.encode(content);

    final buffer = BytesBuilder();
    buffer.addByte(idBytes.length);
    buffer.add(idBytes);
    buffer.addByte(senderBytes.length);
    buffer.add(senderBytes);

    // 内容长度用2字节
    final contentLenData = ByteData(2);
    contentLenData.setUint16(0, contentBytes.length, Endian.big);
    buffer.add(contentLenData.buffer.asUint8List());
    buffer.add(contentBytes);

    return buffer.toBytes();
  }

  static ChatMessage decode(Uint8List payload) {
    int offset = 0;
    final idLen = payload[offset++];
    final roomId = utf8.decode(payload.sublist(offset, offset + idLen));
    offset += idLen;

    final senderLen = payload[offset++];
    final sender = utf8.decode(payload.sublist(offset, offset + senderLen));
    offset += senderLen;

    final contentLen = ByteData.sublistView(
      payload,
      offset,
      offset + 2,
    ).getUint16(0, Endian.big);
    offset += 2;
    final content = utf8.decode(payload.sublist(offset, offset + contentLen));

    return ChatMessage(roomId: roomId, sender: sender, content: content);
  }
}

/// TCP 客户端服务
class TcpClientService {
  Socket? _socket;
  final List<int> _buffer = [];

  ConnectionState _state = const ConnectionState();
  ConnectionState get state => _state;

  // 状态变更控制器
  final _stateController = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get onStateChanged => _stateController.stream;

  // 消息接收控制器
  final _messageController = StreamController<(int, Uint8List)>.broadcast();
  Stream<(int, Uint8List)> get onMessage => _messageController.stream;

  /// 连接服务器
  Future<bool> connect(String serverIp, {int port = 9527}) async {
    if (_state.isConnected) {
      await disconnect();
    }

    _updateState(
      _state.copyWith(
        status: ConnectionStatus.connecting,
        serverIp: serverIp,
        serverPort: port,
        clearError: true,
      ),
    );

    try {
      _socket = await Socket.connect(
        serverIp,
        port,
        timeout: const Duration(seconds: 5),
      );

      _buffer.clear();

      // 监听数据
      _socket!.listen(
        _handleData,
        onError: (error) {
          _handleError('连接错误: $error');
        },
        onDone: () {
          _handleError('连接已断开');
        },
      );

      _updateState(_state.copyWith(status: ConnectionStatus.connected));

      // 连接成功后请求服务器信息（名称）
      _requestServerInfo();

      return true;
    } catch (e) {
      _handleError('连接失败: $e');
      return false;
    }
  }

  /// 断线重连房间（仅限本局成员）
  Future<ReconnectRoomResponse?> reconnectRoom(String roomId) async {
    if (!_state.isConnected) return null;
    final request = ReconnectRoomRequest(roomId: roomId);
    _sendMessage(MessageType.reconnectRoomRequest, request.encode());
    try {
      final result = await onMessage
          .where((msg) => msg.$1 == MessageType.reconnectRoomResponse.code)
          .timeout(const Duration(seconds: 10))
          .first;
      return ReconnectRoomResponse.decode(result.$2);
    } catch (_) {
      return null;
    }
  }

  void _requestServerInfo() {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.serverInfoRequest, Uint8List(0));
  }

  /// 刷新服务器信息（连接数、房间数等）
  void requestServerInfo() {
    _requestServerInfo();
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_socket != null) {
      try {
        await _socket!.close();
      } catch (_) {}
      _socket = null;
    }
    _buffer.clear();
    // 断开连接时保留原有的 IP 和端口信息
    _updateState(
      ConnectionState(
        status: ConnectionStatus.disconnected,
        serverIp: _state.serverIp,
        serverPort: _state.serverPort,
        serverName: _state.serverName,
      ),
    );
  }

  /// 发送登录请求
  /// [username] 用户名
  /// [privateKeyHex] 私钥 (十六进制字符串)
  Future<bool> login(String username, String privateKeyHex) async {
    if (!_state.isConnected) {
      _handleError('未连接到服务器');
      return false;
    }

    _updateState(_state.copyWith(status: ConnectionStatus.authenticating));

    try {
      // 从私钥派生指纹
      final fingerprintHex = IdentityUtils.getUserFingerprintFromPrivateKey(
        privateKeyHex,
        bytes: 8,
      );
      final fingerprint = IdentityUtils.decodeHexToBytes(fingerprintHex);

      // 构建登录请求
      final request = LoginRequest(
        username: username,
        fingerprint: fingerprint,
      );

      // 发送消息
      _sendMessage(MessageType.loginRequest, request.encode());

      // 等待响应
      final response = await _waitForLoginResponse(
        timeout: const Duration(seconds: 10),
      );

      if (response != null && response.success) {
        _updateState(
          _state.copyWith(
            status: ConnectionStatus.authenticated,
            isAuthenticated: true,
          ),
        );
        return true;
      } else {
        _handleError(response?.errorMessage ?? '登录失败');
        return false;
      }
    } catch (e) {
      _handleError('登录异常: $e');
      return false;
    }
  }

  /// 发送心跳
  void sendHeartbeat() {
    if (!_state.isConnected) return;

    final heartbeat = HeartbeatMessage();
    _sendMessage(MessageType.heartbeat, heartbeat.encode());
  }

  /// 发送创建房间请求
  Future<CreateRoomResponse?> createRoom({
    required int roomTypeCode,
    required String roomName,
    required int maxPlayers,
  }) async {
    if (!_state.isConnected) return null;
    final request = CreateRoomRequest(
      roomTypeCode: roomTypeCode,
      roomName: roomName,
      maxPlayers: maxPlayers,
    );
    _sendMessage(MessageType.createRoomRequest, request.encode());
    try {
      final result = await onMessage
          .where((msg) => msg.$1 == MessageType.createRoomResponse.code)
          .timeout(const Duration(seconds: 10))
          .first;
      return CreateRoomResponse.decode(result.$2);
    } on TimeoutException {
      return null;
    }
  }

  /// 请求房间列表
  Future<RoomListResponse?> requestRoomList() async {
    if (!_state.isConnected) return null;
    _sendMessage(MessageType.roomListRequest, Uint8List(0));
    try {
      final result = await onMessage
          .where((msg) => msg.$1 == MessageType.roomListResponse.code)
          .timeout(const Duration(seconds: 10))
          .first;
      return RoomListResponse.decode(result.$2);
    } on TimeoutException {
      return null;
    }
  }

  /// 发送加入房间请求
  Future<JoinRoomResponse?> joinRoom(String roomId) async {
    if (!_state.isConnected) return null;
    final request = JoinRoomRequest(roomId: roomId);
    _sendMessage(MessageType.joinRoomRequest, request.encode());
    try {
      final result = await onMessage
          .where((msg) => msg.$1 == MessageType.joinRoomResponse.code)
          .timeout(const Duration(seconds: 10))
          .first;
      return JoinRoomResponse.decode(result.$2);
    } on TimeoutException {
      return null;
    }
  }

  /// 发送离开房间请求
  Future<void> leaveRoom(String roomId) async {
    if (!_state.isConnected) return;
    final request = LeaveRoomRequest(roomId: roomId);
    _sendMessage(MessageType.leaveRoomRequest, request.encode());
  }

  /// 请求同步房间成员列表
  void requestRoomMembers(String roomId) {
    if (!_state.isConnected) return;
    final request = RoomMemberRequest(roomId: roomId);
    _sendMessage(MessageType.roomMemberRequest, request.encode());
  }

  /// 发送准备/取消准备请求
  void sendReadyRequest(bool isReady) {
    if (!_state.isConnected) return;
    _sendMessage(
      MessageType.readyRequest,
      Uint8List.fromList([isReady ? 1 : 0]),
    );
  }

  /// 上传词库数据（JSON字符串）
  void uploadLexicon(String lexiconJson) {
    if (!_state.isConnected) return;
    final data = utf8.encode(lexiconJson);
    _sendMessage(MessageType.lexiconUpload, Uint8List.fromList(data));
  }

  /// 请求当前房间词库数据
  void requestLexicon() {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.lexiconRequest, Uint8List(0));
  }

  /// 发送游戏开始请求（房主发起，包含卡牌索引列表）
  void sendGameStart(List<int> cardIndices) {
    if (!_state.isConnected) return;
    final json = '{"cardIndices":${cardIndices.toString()}}';
    final data = utf8.encode(json);
    _sendMessage(MessageType.gameStart, Uint8List.fromList(data));
  }

  /// 发送卡牌选择请求
  void sendCardPick(int cardIndex) {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.cardPick, Uint8List.fromList([cardIndex]));
  }

  /// 上传绘画PNG数据
  void sendDrawingUpload(Uint8List pngData) {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.drawingUpload, pngData);
  }

  /// 提交猜测
  void sendGuessSubmit(int cardIndex, String guess) {
    if (!_state.isConnected) return;
    final json = '{"cardIndex":$cardIndex,"guess":"$guess"}';
    final data = utf8.encode(json);
    _sendMessage(MessageType.guessSubmit, Uint8List.fromList(data));
  }

  /// 通知服务端绘画完成
  void sendDrawingComplete() {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.drawingComplete, Uint8List(0));
  }

  /// 回执：已收到复盘文件
  void sendReplayAck(String replayId) {
    if (!_state.isConnected) return;
    final ack = ReplayAck(replayId: replayId);
    _sendMessage(MessageType.replayAck, ack.encode());
  }

  /// 协同：发送区域增量
  void sendCollabDelta(CollabDeltaRequest req) {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.collabDelta, req.encode());
  }

  /// 协同：请求同步（触发房主发快照）
  void sendCollabSyncRequest({
    required String requesterUsername,
    int clientEpoch = 0,
    required int clientRev,
  }) {
    if (!_state.isConnected) return;
    _sendMessage(
      MessageType.collabSyncRequest,
      CollabSyncRequest(
        requesterUsername: requesterUsername,
        clientEpoch: clientEpoch,
        clientRev: clientRev,
      ).encode(),
    );
  }

  /// 协同：房主发送快照（服务端转发给指定用户）
  void sendCollabSnapshotFromOwner(CollabSnapshotFromOwner snap) {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.collabSnapshotFromOwner, snap.encode());
  }

  /// 协同：发送图层操作请求（增删改重排）
  void sendCollabLayerOp(CollabLayerOpRequest req) {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.collabLayerOpRequest, req.encode());
  }

  /// 协同：发送带 layerId 的区域增量
  void sendCollabLayerDelta(CollabLayerDeltaRequest req) {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.collabLayerDelta, req.encode());
  }

  /// 提交投票（勾/叉）
  void sendVoteSubmit(bool isUp) {
    if (!_state.isConnected) return;
    _sendMessage(MessageType.voteSubmit, Uint8List.fromList([isUp ? 1 : 0]));
  }

  /// 提交最爱画作
  void sendFavoriteSubmit(int drawingIndex) {
    if (!_state.isConnected) return;
    _sendMessage(
      MessageType.favoriteSubmit,
      Uint8List.fromList([drawingIndex]),
    );
  }

  /// 发送聊天消息
  void sendChatMessage(String roomId, String content) {
    if (!_state.isConnected) return;
    final chat = ChatMessage(
      roomId: roomId,
      sender: '', // 发送者由服务端填充
      content: content,
    );
    _sendMessage(MessageType.chatMessage, chat.encode());
  }

  /// 更新房间设置
  Future<UpdateRoomResponse?> updateRoom({
    required String roomId,
    required String roomName,
    required int roomTypeCode,
    required int maxPlayers,
    int rounds = 5,
    int roundTime = 60,
    String lexiconKey = '',
    int canvasWidth = 1280,
    int canvasHeight = 720,
  }) async {
    if (!_state.isConnected) return null;
    final request = UpdateRoomRequest(
      roomId: roomId,
      roomName: roomName,
      roomTypeCode: roomTypeCode,
      maxPlayers: maxPlayers,
      rounds: rounds,
      roundTime: roundTime,
      lexiconKey: lexiconKey,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );
    _sendMessage(MessageType.updateRoomRequest, request.encode());
    try {
      final result = await onMessage
          .where((msg) => msg.$1 == MessageType.updateRoomResponse.code)
          .timeout(const Duration(seconds: 10))
          .first;
      return UpdateRoomResponse.decode(result.$2);
    } catch (_) {
      return null;
    }
  }

  /// 转让房间
  Future<TransferRoomResponse?> transferRoom({
    required String roomId,
    required String newOwnerUsername,
    required String newOwnerFingerprintHex,
  }) async {
    if (!_state.isConnected) return null;
    final request = TransferRoomRequest(
      roomId: roomId,
      newOwnerUsername: newOwnerUsername,
      newOwnerFingerprintHex: newOwnerFingerprintHex,
    );
    _sendMessage(MessageType.transferRoomRequest, request.encode());
    try {
      final result = await onMessage
          .where((msg) => msg.$1 == MessageType.transferRoomResponse.code)
          .timeout(const Duration(seconds: 10))
          .first;
      return TransferRoomResponse.decode(result.$2);
    } catch (_) {
      return null;
    }
  }

  /// 发送消息
  void _sendMessage(MessageType type, Uint8List payload) {
    final message = ProtocolHandler.encode(type, payload);
    _socket?.add(message);
  }

  /// 处理接收数据
  void _handleData(Uint8List data) {
    _buffer.addAll(data);

    // 解析消息
    while (_buffer.length >= ProtocolHandler.headerLength) {
      final header = ProtocolHandler.decodeHeader(Uint8List.fromList(_buffer));
      if (header == null) break;

      final (totalLength, messageType) = header;

      if (_buffer.length < totalLength) break;

      final messageData = Uint8List.fromList(_buffer.sublist(0, totalLength));
      final payload = ProtocolHandler.extractPayload(messageData);

      _buffer.removeRange(0, totalLength);

      // 通知消息
      _messageController.add((messageType.code, payload));

      // 内部处理服务器信息
      if (messageType == MessageType.serverInfoResponse) {
        try {
          final info = ServerInfoResponse.decode(payload);
          _updateState(
            _state.copyWith(
              serverName: info.serverName,
              currentConnections: info.currentConnections,
              maxConnections: info.maxConnections,
              currentRooms: info.currentRooms,
              maxRooms: info.maxRooms,
            ),
          );
        } catch (_) {}
      }
    }
  }

  /// 等待登录响应
  Future<LoginResponse?> _waitForLoginResponse({
    required Duration timeout,
  }) async {
    try {
      final result = await onMessage
          .where((msg) => msg.$1 == MessageType.loginResponse.code)
          .timeout(timeout)
          .first;

      return LoginResponse.decode(result.$2);
    } on TimeoutException {
      return null;
    }
  }

  /// 处理错误
  void _handleError(String message) {
    _updateState(
      _state.copyWith(status: ConnectionStatus.error, errorMessage: message),
    );
  }

  /// 更新状态
  void _updateState(ConnectionState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// 销毁
  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
  }
}

// ============ 协议相关类 (与 service 端一致) ============

/// 消息类型
enum MessageType {
  loginRequest(0x01),
  heartbeat(0x02),
  disconnect(0x03),
  serverInfoRequest(0x10),
  createRoomRequest(0x20),
  roomListRequest(0x21),
  joinRoomRequest(0x22),
  leaveRoomRequest(0x23),
  roomMemberRequest(0x24),
  chatMessage(0x30),
  reconnectRoomRequest(0x33),
  collabDelta(0x34),
  collabSyncRequest(0x35),
  collabLayerOpRequest(0x36), // 图层操作请求（增删改重排）
  collabLayerDelta(0x37), // 带 layerId 的增量 delta
  updateRoomRequest(0x25), // 修改房间设置请求
  transferRoomRequest(0x26), // 转让房间请求
  readyRequest(0x27), // 准备/取消准备请求
  lexiconUpload(0x28), // 词库上传请求
  lexiconRequest(0x29), // 请求当前词库数据
  gameStart(0x2A), // 游戏开始请求
  cardPick(0x2B), // 卡牌选择请求
  drawingUpload(0x2C), // 绘画上传（PNG数据）
  guessSubmit(0x2D), // 猜测提交
  drawingComplete(0x2E), // 客户端通知绘画完成
  replayAck(0x32), // 回执：已收到复盘文件
  loginResponse(0x81),
  heartbeatResponse(0x82),
  serverInfoResponse(0x90),
  createRoomResponse(0xA0),
  roomListResponse(0xA1),
  joinRoomResponse(0xA2),
  leaveRoomResponse(0xA3),
  roomMemberUpdate(0xA4),
  roomOwnerTransfer(0xA5), // 房间转让通知
  updateRoomResponse(0xA6), // 修改房间设置响应
  roomSettingUpdate(0xA7), // 房间设置更新广播
  transferRoomResponse(0xA8), // 转让房间响应
  lexiconData(0xA9), // 词库数据广播/下发
  gameStartBroadcast(0xAA), // 游戏开始广播
  cardPickBroadcast(0xAB), // 卡牌选择广播
  drawingPhaseBroadcast(0xAC), // 作画阶段广播
  guessPhaseBroadcast(0xAD), // 猜测阶段广播
  drawingImageData(0xAE), // 绘画PNG数据下发
  roundResultBroadcast(0xAF), // 回合结果广播
  gameEndBroadcast(0xB0), // 游戏结束广播
  guessResultBroadcast(0xB1), // 猜测结果广播
  wordPickPhaseBroadcast(0xB2), // 词条翻牌阶段广播
  wordPickBroadcast(0xB3), // 词条翻牌选择广播
  wordPickResult(0xB4), // 词条翻牌结果（私发）
  replayFileBroadcast(0xB5), // 复盘文件广播（游戏结束时下发）
  reviewPhaseBroadcast(0xB6), // 进入复盘阶段广播
  voteStartBroadcast(0xB7), // 投票开始广播
  voteSubmit(0x2F), // 提交投票（勾/叉）
  voteResultBroadcast(0xB8), // 投票结果广播（弹幕）
  favoriteSelectionStart(0xB9), // 最爱画作选择开始（全员同步，携带picker用户名）
  favoriteSubmit(0x31), // 提交最爱画作
  scoreUpdateBroadcast(0xBA), // 积分更新广播
  reviewProgressBroadcast(0xBB), // 复盘进度广播（pathIndex/stepIndex）
  favoriteResultBroadcast(0xBC), // 最爱画作结果广播（全员同步，携带drawingIndex）
  scorePodiumBroadcast(0xBD), // 结算领奖台广播（top3 + 倒计时结束时间）
  gameResetBroadcast(0xBE), // 服务端通知客户端回到idle并清空对局状态
  reconnectRoomResponse(0xBF),
  collabDeltaBroadcast(0xC0),
  collabSyncRequired(0xC1),
  collabSnapshotFromOwner(0xC2),
  collabSnapshotFromServer(0xC3),
  collabLayerOpBroadcast(0xC4), // 图层操作广播
  collabLayerDeltaBroadcast(0xC5), // 带 layerId 的增量广播
  collabMultiLayerSnapshot(0xC6), // 多图层快照（断线重连/首次同步）
  error(0xFF);

  final int code;
  const MessageType(this.code);

  static MessageType fromCode(int code) {
    return MessageType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => MessageType.error,
    );
  }
}

/// 协议处理器
class ProtocolHandler {
  static const int headerLength = 5;

  static Uint8List encode(MessageType type, Uint8List payload) {
    final totalLength = headerLength + payload.length;
    final buffer = ByteData(totalLength);

    buffer.setUint32(0, totalLength, Endian.big);
    buffer.setUint8(4, type.code);
    buffer.buffer.asUint8List().setAll(headerLength, payload);

    return buffer.buffer.asUint8List();
  }

  static (int, MessageType)? decodeHeader(Uint8List data) {
    if (data.length < headerLength) return null;

    final byteData = ByteData.sublistView(data);
    final totalLength = byteData.getUint32(0, Endian.big);
    final typeCode = byteData.getUint8(4);
    final type = MessageType.fromCode(typeCode);

    return (totalLength, type);
  }

  static Uint8List extractPayload(Uint8List data) {
    if (data.length <= headerLength) return Uint8List(0);
    return data.sublist(headerLength);
  }
}

class VoteResultBroadcast {
  final String username;
  final bool isUp;

  VoteResultBroadcast({required this.username, required this.isUp});

  static VoteResultBroadcast decode(Uint8List payload) {
    if (payload.isEmpty) return VoteResultBroadcast(username: '', isUp: false);
    final len = payload[0];
    final username = utf8.decode(payload.sublist(1, 1 + len));
    final isUp = payload[1 + len] == 1;
    return VoteResultBroadcast(username: username, isUp: isUp);
  }
}

class ScoreUpdateBroadcast {
  final Map<String, int> scores;

  ScoreUpdateBroadcast({required this.scores});

  static ScoreUpdateBroadcast decode(Uint8List payload) {
    final jsonStr = utf8.decode(payload);
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return ScoreUpdateBroadcast(
      scores: map.map((k, v) => MapEntry(k, v as int)),
    );
  }
}

/// 登录请求
class LoginRequest {
  final String username;
  final Uint8List fingerprint;

  LoginRequest({required this.username, required this.fingerprint});

  Uint8List encode() {
    final usernameBytes = utf8.encode(username);
    final len = usernameBytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len + 8);

    buffer[0] = len;
    if (len > 0) buffer.setAll(1, usernameBytes.sublist(0, len));
    buffer.setAll(1 + len, fingerprint);

    return buffer;
  }
}

/// 登录响应
class LoginResponse {
  final bool success;
  final String? errorMessage;

  LoginResponse({required this.success, this.errorMessage});

  static LoginResponse decode(Uint8List payload) {
    if (payload.isEmpty) {
      return LoginResponse(success: false, errorMessage: '响应为空');
    }

    final statusCode = payload[0];
    if (statusCode == 0x00) {
      return LoginResponse(success: true);
    } else {
      if (payload.length >= 2) {
        final errorLength = payload[1];
        if (payload.length >= 2 + errorLength && errorLength > 0) {
          final errorBytes = payload.sublist(2, 2 + errorLength);
          return LoginResponse(
            success: false,
            errorMessage: utf8.decode(errorBytes),
          );
        }
      }
      return LoginResponse(success: false, errorMessage: '未知错误');
    }
  }
}

/// 心跳消息
class HeartbeatMessage {
  final int timestamp;

  HeartbeatMessage({int? timestamp})
    : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Uint8List encode() {
    final buffer = ByteData(4);
    buffer.setUint32(0, timestamp, Endian.big);
    return buffer.buffer.asUint8List();
  }
}

class ServerInfoResponse {
  final String serverName;
  final int currentConnections; // 当前连接数
  final int maxConnections; // 最大连接数
  final int currentRooms; // 当前房间数
  final int maxRooms; // 最大房间数

  ServerInfoResponse({
    required this.serverName,
    this.currentConnections = 0,
    this.maxConnections = 100,
    this.currentRooms = 0,
    this.maxRooms = 20,
  });

  static ServerInfoResponse decode(Uint8List payload) {
    if (payload.isEmpty) {
      return ServerInfoResponse(serverName: '');
    }
    final len = payload[0];
    if (payload.length < 1 + len) {
      return ServerInfoResponse(serverName: '');
    }
    final nameBytes = payload.sublist(1, 1 + len);
    final serverName = utf8.decode(nameBytes);

    // 解析连接数和房间数
    int offset = 1 + len;
    int currentConnections = 0;
    int maxConnections = 100;
    int currentRooms = 0;
    int maxRooms = 20;

    if (payload.length >= offset + 2) {
      currentConnections = ByteData.sublistView(
        payload,
        offset,
        offset + 2,
      ).getUint16(0, Endian.big);
      offset += 2;
    }
    if (payload.length >= offset + 2) {
      maxConnections = ByteData.sublistView(
        payload,
        offset,
        offset + 2,
      ).getUint16(0, Endian.big);
      offset += 2;
    }
    if (payload.length >= offset + 2) {
      currentRooms = ByteData.sublistView(
        payload,
        offset,
        offset + 2,
      ).getUint16(0, Endian.big);
      offset += 2;
    }
    if (payload.length >= offset + 2) {
      maxRooms = ByteData.sublistView(
        payload,
        offset,
        offset + 2,
      ).getUint16(0, Endian.big);
    }

    return ServerInfoResponse(
      serverName: serverName,
      currentConnections: currentConnections,
      maxConnections: maxConnections,
      currentRooms: currentRooms,
      maxRooms: maxRooms,
    );
  }
}

/// 创建房间请求
class CreateRoomRequest {
  final int roomTypeCode;
  final String roomName;
  final int maxPlayers;

  CreateRoomRequest({
    required this.roomTypeCode,
    required this.roomName,
    required this.maxPlayers,
  });

  Uint8List encode() {
    final nameBytes = utf8.encode(roomName);
    final len = nameBytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + 1 + len + 1);
    buffer[0] = roomTypeCode;
    buffer[1] = len;
    if (len > 0) buffer.setAll(2, nameBytes.sublist(0, len));
    buffer[2 + len] = maxPlayers.clamp(1, 16);
    return buffer;
  }
}

/// 创建房间响应
class CreateRoomResponse {
  final bool success;
  final String? roomId;
  final String? errorMessage;

  CreateRoomResponse({required this.success, this.roomId, this.errorMessage});

  static CreateRoomResponse decode(Uint8List payload) {
    if (payload.isEmpty) {
      return CreateRoomResponse(success: false, errorMessage: '响应为空');
    }
    final status = payload[0];
    if (payload.length < 2) {
      return CreateRoomResponse(
        success: status == 0x00,
        errorMessage: status != 0x00 ? '响应格式错误' : null,
      );
    }
    final len = payload[1];
    final str = (payload.length >= 2 + len && len > 0)
        ? utf8.decode(payload.sublist(2, 2 + len))
        : '';
    if (status == 0x00) {
      return CreateRoomResponse(success: true, roomId: str);
    } else {
      return CreateRoomResponse(success: false, errorMessage: str);
    }
  }
}

/// 房间信息
class RoomInfo {
  final String roomId;
  final String roomName;
  final int roomTypeCode;
  final int currentPlayers;
  final int maxPlayers;
  final String ownerName;
  final String serverKey; // 所属服务器key
  final int rounds;
  final int roundTime;
  final String lexiconKey;
  final bool isGameActive;

  RoomInfo({
    required this.roomId,
    required this.roomName,
    required this.roomTypeCode,
    required this.currentPlayers,
    required this.maxPlayers,
    required this.ownerName,
    required this.serverKey,
    this.rounds = 5,
    this.roundTime = 60,
    this.lexiconKey = '',
    this.isGameActive = false,
  });

  RoomInfo copyWith({
    String? roomId,
    String? roomName,
    int? roomTypeCode,
    int? currentPlayers,
    int? maxPlayers,
    String? ownerName,
    String? serverKey,
    int? rounds,
    int? roundTime,
    String? lexiconKey,
    bool? isGameActive,
  }) {
    return RoomInfo(
      roomId: roomId ?? this.roomId,
      roomName: roomName ?? this.roomName,
      roomTypeCode: roomTypeCode ?? this.roomTypeCode,
      currentPlayers: currentPlayers ?? this.currentPlayers,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      ownerName: ownerName ?? this.ownerName,
      serverKey: serverKey ?? this.serverKey,
      rounds: rounds ?? this.rounds,
      roundTime: roundTime ?? this.roundTime,
      lexiconKey: lexiconKey ?? this.lexiconKey,
      isGameActive: isGameActive ?? this.isGameActive,
    );
  }

  String get roomTypeName {
    switch (roomTypeCode) {
      case 0x01:
        return '接龙';
      case 0x02:
        return '协同';
      default:
        return '未知';
    }
  }

  static (RoomInfo, int) decodeAt(Uint8List data, int start) {
    int offset = start;
    final idLen = data[offset++];
    final roomId = utf8.decode(data.sublist(offset, offset + idLen));
    offset += idLen;
    final nameLen = data[offset++];
    final roomName = utf8.decode(data.sublist(offset, offset + nameLen));
    offset += nameLen;
    final roomTypeCode = data[offset++];
    final currentPlayers = data[offset++];
    final maxPlayers = data[offset++];
    final ownerLen = data[offset++];
    final ownerName = utf8.decode(data.sublist(offset, offset + ownerLen));
    offset += ownerLen;

    int rounds = 5;
    int roundTime = 60;
    String lexiconKey = '';

    if (offset < data.length) {
      rounds = data[offset++];
    }
    if (offset + 1 < data.length) {
      // roundTime 使用2字节（大端序）
      roundTime = ByteData.sublistView(
        data,
        offset,
        offset + 2,
      ).getUint16(0, Endian.big);
      offset += 2;
    }
    if (offset < data.length) {
      final lexLen = data[offset++];
      if (offset + lexLen <= data.length) {
        lexiconKey = utf8.decode(data.sublist(offset, offset + lexLen));
        offset += lexLen;
      }
    }
    bool isGameActive = false;
    if (offset < data.length) {
      isGameActive = data[offset++] != 0;
    }

    return (
      RoomInfo(
        roomId: roomId,
        roomName: roomName,
        roomTypeCode: roomTypeCode,
        currentPlayers: currentPlayers,
        maxPlayers: maxPlayers,
        ownerName: ownerName,
        serverKey: '',
        rounds: rounds,
        roundTime: roundTime,
        lexiconKey: lexiconKey,
        isGameActive: isGameActive,
      ),
      offset,
    );
  }
}

/// 房间列表响应
class RoomListResponse {
  final List<RoomInfo> rooms;

  RoomListResponse({required this.rooms});

  static RoomListResponse decode(Uint8List payload) {
    if (payload.isEmpty) return RoomListResponse(rooms: []);
    final count = payload[0];
    final rooms = <RoomInfo>[];
    int offset = 1;
    for (int i = 0; i < count && offset < payload.length; i++) {
      final (room, newOffset) = RoomInfo.decodeAt(payload, offset);
      rooms.add(room);
      offset = newOffset;
    }
    return RoomListResponse(rooms: rooms);
  }
}

/// 加入房间请求
class JoinRoomRequest {
  final String roomId;

  JoinRoomRequest({required this.roomId});

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final len = idBytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len);
    buffer[0] = len;
    if (len > 0) buffer.setAll(1, idBytes.sublist(0, len));
    return buffer;
  }
}

/// 加入房间响应
class JoinRoomResponse {
  final bool success;
  final String? roomId;
  final String? errorMessage;

  JoinRoomResponse({required this.success, this.roomId, this.errorMessage});

  static JoinRoomResponse decode(Uint8List payload) {
    if (payload.isEmpty) {
      return JoinRoomResponse(success: false, errorMessage: '响应为空');
    }
    final status = payload[0];
    if (payload.length < 2) {
      return JoinRoomResponse(
        success: status == 0x00,
        errorMessage: status != 0x00 ? '响应格式错误' : null,
      );
    }
    final len = payload[1];
    final str = (payload.length >= 2 + len && len > 0)
        ? utf8.decode(payload.sublist(2, 2 + len))
        : '';
    if (status == 0x00) {
      return JoinRoomResponse(success: true, roomId: str);
    } else {
      return JoinRoomResponse(success: false, errorMessage: str);
    }
  }
}

/// 离开房间请求
class LeaveRoomRequest {
  final String roomId;

  LeaveRoomRequest({required this.roomId});

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final len = idBytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len);
    buffer[0] = len;
    if (len > 0) buffer.setAll(1, idBytes.sublist(0, len));
    return buffer;
  }
}

/// 断线重连请求
/// 格式: [房间代号长度(1字节)] [房间代号]
class ReconnectRoomRequest {
  final String roomId;

  ReconnectRoomRequest({required this.roomId});

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final len = idBytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len);
    buffer[0] = len;
    if (len > 0) buffer.setAll(1, idBytes.sublist(0, len));
    return buffer;
  }
}

/// 断线重连响应
/// 格式: [success(1字节)] [roomId长度(1字节)] [roomId] [error长度(1字节)] [error]
class ReconnectRoomResponse {
  final bool success;
  final String roomId;
  final String? errorMessage;

  ReconnectRoomResponse({
    required this.success,
    required this.roomId,
    this.errorMessage,
  });

  static ReconnectRoomResponse decode(Uint8List payload) {
    if (payload.isEmpty) {
      return ReconnectRoomResponse(
        success: false,
        roomId: '',
        errorMessage: '响应为空',
      );
    }
    int offset = 0;
    final success = payload[offset++] == 1;
    if (offset >= payload.length) {
      return ReconnectRoomResponse(
        success: success,
        roomId: '',
        errorMessage: success ? null : '响应格式错误',
      );
    }
    final roomLen = payload[offset++];
    final roomId = (offset + roomLen <= payload.length)
        ? utf8.decode(payload.sublist(offset, offset + roomLen))
        : '';
    offset += roomLen;
    final errLen = (offset < payload.length) ? payload[offset++] : 0;
    final err = (errLen > 0 && offset + errLen <= payload.length)
        ? utf8.decode(payload.sublist(offset, offset + errLen))
        : '';
    return ReconnectRoomResponse(
      success: success,
      roomId: roomId,
      errorMessage: err.isNotEmpty ? err : null,
    );
  }
}

class RoomMember {
  final String username;
  final String fingerprintHex;
  final bool isReady;
  final bool isOnline;

  RoomMember({
    required this.username,
    required this.fingerprintHex,
    this.isReady = false,
    this.isOnline = true,
  });

  Uint8List encode() {
    final userBytes = utf8.encode(username);
    final fpBytes = utf8.encode(fingerprintHex);
    final buffer = BytesBuilder();
    buffer.addByte(userBytes.length);
    buffer.add(userBytes);
    buffer.addByte(fpBytes.length);
    buffer.add(fpBytes);
    buffer.addByte(isReady ? 1 : 0);
    buffer.addByte(isOnline ? 1 : 0);
    return buffer.toBytes();
  }

  static RoomMember decode(Uint8List payload, int offset, List<int> newOffset) {
    final userLen = payload[offset++];
    final username = utf8.decode(payload.sublist(offset, offset + userLen));
    offset += userLen;
    final fpLen = payload[offset++];
    final fingerprintHex = utf8.decode(payload.sublist(offset, offset + fpLen));
    offset += fpLen;
    final isReady = (offset < payload.length) ? payload[offset++] == 1 : false;
    // 兼容旧版本：缺少在线标记时默认在线
    final isOnline = (offset < payload.length) ? payload[offset++] == 1 : true;
    newOffset[0] = offset;
    return RoomMember(
      username: username,
      fingerprintHex: fingerprintHex,
      isReady: isReady,
      isOnline: isOnline,
    );
  }
}

/// 房间成员更新
class RoomMemberUpdate {
  final String roomId;
  final List<RoomMember> members;

  RoomMemberUpdate({required this.roomId, required this.members});

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final buffer = BytesBuilder();
    buffer.addByte(idBytes.length);
    buffer.add(idBytes);
    buffer.addByte(members.length);
    for (final member in members) {
      buffer.add(member.encode());
    }
    return buffer.toBytes();
  }

  static RoomMemberUpdate decode(Uint8List payload) {
    if (payload.isEmpty) {
      return RoomMemberUpdate(roomId: '', members: []);
    }
    int offset = 0;
    final idLen = payload[offset++];
    final roomId = utf8.decode(payload.sublist(offset, offset + idLen));
    offset += idLen;
    if (offset >= payload.length) {
      return RoomMemberUpdate(roomId: roomId, members: []);
    }
    final count = payload[offset++];
    final members = <RoomMember>[];
    for (int i = 0; i < count && offset < payload.length; i++) {
      final newOffset = [offset];
      members.add(RoomMember.decode(payload, offset, newOffset));
      offset = newOffset[0];
    }
    return RoomMemberUpdate(roomId: roomId, members: members);
  }
}

/// 房间成员请求
class RoomMemberRequest {
  final String roomId;

  RoomMemberRequest({required this.roomId});

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final len = idBytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len);
    buffer[0] = len;
    if (len > 0) buffer.setAll(1, idBytes.sublist(0, len));
    return buffer;
  }
}

/// 房间转让通知
class RoomOwnerTransfer {
  final String oldRoomId;
  final String newRoomId;
  final String newOwnerUsername;
  final String newOwnerFingerprintHex;

  RoomOwnerTransfer({
    required this.oldRoomId,
    required this.newRoomId,
    required this.newOwnerUsername,
    required this.newOwnerFingerprintHex,
  });

  static RoomOwnerTransfer decode(Uint8List payload) {
    int offset = 0;

    final oldIdLen = payload[offset++];
    final oldRoomId = utf8.decode(payload.sublist(offset, offset + oldIdLen));
    offset += oldIdLen;

    final newIdLen = payload[offset++];
    final newRoomId = utf8.decode(payload.sublist(offset, offset + newIdLen));
    offset += newIdLen;

    final userLen = payload[offset++];
    final newOwnerUsername = utf8.decode(
      payload.sublist(offset, offset + userLen),
    );
    offset += userLen;

    final fpLen = payload[offset++];
    final newOwnerFingerprintHex = utf8.decode(
      payload.sublist(offset, offset + fpLen),
    );

    return RoomOwnerTransfer(
      oldRoomId: oldRoomId,
      newRoomId: newRoomId,
      newOwnerUsername: newOwnerUsername,
      newOwnerFingerprintHex: newOwnerFingerprintHex,
    );
  }
}

/// 修改房间设置请求
class UpdateRoomRequest {
  final String roomId;
  final String roomName;
  final int roomTypeCode;
  final int maxPlayers;
  final int rounds;
  final int roundTime;
  final String lexiconKey;
  final int canvasWidth;
  final int canvasHeight;

  UpdateRoomRequest({
    required this.roomId,
    required this.roomName,
    required this.roomTypeCode,
    required this.maxPlayers,
    this.rounds = 5,
    this.roundTime = 60,
    this.lexiconKey = '',
    this.canvasWidth = 1280,
    this.canvasHeight = 720,
  });

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final nameBytes = utf8.encode(roomName);
    final lexiconKeyBytes = utf8.encode(lexiconKey);
    final buffer = BytesBuilder();
    buffer.addByte(idBytes.length);
    buffer.add(idBytes);
    buffer.addByte(nameBytes.length);
    buffer.add(nameBytes);
    buffer.addByte(roomTypeCode);
    buffer.addByte(maxPlayers);
    buffer.addByte(rounds);
    // roundTime 使用2字节（大端序），支持0-65535秒
    final roundTimeData = ByteData(2);
    roundTimeData.setUint16(0, roundTime, Endian.big);
    buffer.add(roundTimeData.buffer.asUint8List());
    buffer.addByte(lexiconKeyBytes.length);
    buffer.add(lexiconKeyBytes);

    final canvasData = ByteData(4);
    canvasData.setUint16(0, canvasWidth, Endian.big);
    canvasData.setUint16(2, canvasHeight, Endian.big);
    buffer.add(canvasData.buffer.asUint8List());
    return buffer.toBytes();
  }
}

/// 修改房间设置响应
class UpdateRoomResponse {
  final bool success;
  final String errorMessage;

  UpdateRoomResponse({required this.success, this.errorMessage = ''});

  static UpdateRoomResponse decode(Uint8List payload) {
    if (payload.isEmpty) {
      return UpdateRoomResponse(success: false, errorMessage: '无效响应');
    }
    final success = payload[0] == 0x00;
    if (payload.length < 2) {
      return UpdateRoomResponse(success: success);
    }
    final msgLen = payload[1];
    final errorMessage = payload.length > 2 + msgLen
        ? utf8.decode(payload.sublist(2, 2 + msgLen))
        : '';
    return UpdateRoomResponse(success: success, errorMessage: errorMessage);
  }
}

/// 房间设置更新广播
class RoomSettingUpdate {
  final String roomId;
  final String roomName;
  final int roomTypeCode;
  final int maxPlayers;
  final int rounds;
  final int roundTime;
  final String lexiconKey;
  final int canvasWidth;
  final int canvasHeight;

  RoomSettingUpdate({
    required this.roomId,
    required this.roomName,
    required this.roomTypeCode,
    required this.maxPlayers,
    required this.rounds,
    required this.roundTime,
    required this.lexiconKey,
    required this.canvasWidth,
    required this.canvasHeight,
  });

  static RoomSettingUpdate decode(Uint8List payload) {
    int offset = 0;
    final idLen = payload[offset++];
    final roomId = utf8.decode(payload.sublist(offset, offset + idLen));
    offset += idLen;
    final nameLen = payload[offset++];
    final roomName = utf8.decode(payload.sublist(offset, offset + nameLen));
    offset += nameLen;
    final roomTypeCode = payload[offset++];
    final maxPlayers = payload[offset++];
    final rounds = payload[offset++];
    // roundTime 使用2字节（大端序）
    final roundTime = ByteData.sublistView(
      payload,
      offset,
      offset + 2,
    ).getUint16(0, Endian.big);
    offset += 2;
    final lexiconKeyLen = payload[offset++];
    final lexiconKey = lexiconKeyLen > 0
        ? utf8.decode(payload.sublist(offset, offset + lexiconKeyLen))
        : '';

    offset += lexiconKeyLen;

    int canvasWidth = 1280;
    int canvasHeight = 720;
    if (payload.length >= offset + 4) {
      canvasWidth = ByteData.sublistView(
        payload,
        offset,
        offset + 2,
      ).getUint16(0, Endian.big);
      canvasHeight = ByteData.sublistView(
        payload,
        offset + 2,
        offset + 4,
      ).getUint16(0, Endian.big);
    }
    return RoomSettingUpdate(
      roomId: roomId,
      roomName: roomName,
      roomTypeCode: roomTypeCode,
      maxPlayers: maxPlayers,
      rounds: rounds,
      roundTime: roundTime,
      lexiconKey: lexiconKey,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );
  }
}

/// 转让房间请求
class TransferRoomRequest {
  final String roomId;
  final String newOwnerUsername;
  final String newOwnerFingerprintHex;

  TransferRoomRequest({
    required this.roomId,
    required this.newOwnerUsername,
    required this.newOwnerFingerprintHex,
  });

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final userBytes = utf8.encode(newOwnerUsername);
    final fpBytes = utf8.encode(newOwnerFingerprintHex);
    final buffer = BytesBuilder();
    buffer.addByte(idBytes.length);
    buffer.add(idBytes);
    buffer.addByte(userBytes.length);
    buffer.add(userBytes);
    buffer.addByte(fpBytes.length);
    buffer.add(fpBytes);
    return buffer.toBytes();
  }
}

/// 转让房间响应
class TransferRoomResponse {
  final bool success;
  final String errorMessage;

  TransferRoomResponse({required this.success, this.errorMessage = ''});

  static TransferRoomResponse decode(Uint8List payload) {
    if (payload.isEmpty) {
      return TransferRoomResponse(success: false, errorMessage: '无效响应');
    }
    final success = payload[0] == 0x00;
    if (payload.length < 2) {
      return TransferRoomResponse(success: success);
    }
    final msgLen = payload[1];
    final errorMessage = payload.length > 2 + msgLen
        ? utf8.decode(payload.sublist(2, 2 + msgLen))
        : '';
    return TransferRoomResponse(success: success, errorMessage: errorMessage);
  }
}

/// 卡牌选择广播消息
/// 格式: [cardIndex(1字节)] [usernameLen(1字节)] [username] [fingerprintLen(1字节)] [fingerprint]
class CardPickBroadcast {
  final int cardIndex;
  final String username;
  final String fingerprintHex;

  CardPickBroadcast({
    required this.cardIndex,
    required this.username,
    required this.fingerprintHex,
  });

  static CardPickBroadcast decode(Uint8List payload) {
    int offset = 0;
    final cardIndex = payload[offset++];
    final userLen = payload[offset++];
    final username = utf8.decode(payload.sublist(offset, offset + userLen));
    offset += userLen;
    final fpLen = payload[offset++];
    final fingerprintHex = utf8.decode(payload.sublist(offset, offset + fpLen));
    return CardPickBroadcast(
      cardIndex: cardIndex,
      username: username,
      fingerprintHex: fingerprintHex,
    );
  }
}

/// 作画阶段广播消息（服务端 → 客户端）
class DrawingPhaseBroadcast {
  final int round;
  final int totalRounds;
  final int drawTime;
  final String word;
  final Map<String, int> memberWords;

  DrawingPhaseBroadcast({
    required this.round,
    required this.totalRounds,
    required this.drawTime,
    required this.word,
    this.memberWords = const {},
  });

  static DrawingPhaseBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return DrawingPhaseBroadcast(
      round: map['round'] as int,
      totalRounds: map['totalRounds'] as int,
      drawTime: map['drawTime'] as int,
      word: map['word'] as String,
      memberWords:
          (map['memberWords'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as int),
          ) ??
          {},
    );
  }
}

/// 猜测阶段广播消息（服务端 → 客户端）
class GuessPhaseBroadcast {
  final int round;
  final int totalRounds;
  final int guessTime;
  final int cardPickTime;
  final List<GuessCard> cards;

  GuessPhaseBroadcast({
    required this.round,
    required this.totalRounds,
    required this.guessTime,
    required this.cardPickTime,
    required this.cards,
  });

  static GuessPhaseBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return GuessPhaseBroadcast(
      round: map['round'] as int,
      totalRounds: map['totalRounds'] as int,
      guessTime: map['guessTime'] as int,
      cardPickTime: map['cardPickTime'] as int,
      cards: (map['cards'] as List<dynamic>)
          .map((c) => GuessCard.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 猜测阶段卡牌
class GuessCard {
  final String label;
  final String fingerprintHex;
  final String username;

  GuessCard({
    required this.label,
    required this.fingerprintHex,
    required this.username,
  });

  static GuessCard fromJson(Map<String, dynamic> json) => GuessCard(
    label: json['label'] as String,
    fingerprintHex: json['fingerprintHex'] as String,
    username: json['username'] as String,
  );
}

/// 绘画图片数据下发（服务端 → 客户端）
class DrawingImageData {
  final String fingerprintHex;
  final String username;
  final Uint8List pngData;

  DrawingImageData({
    required this.fingerprintHex,
    required this.username,
    required this.pngData,
  });

  static DrawingImageData decode(Uint8List payload) {
    final headerLen = ByteData.sublistView(
      payload,
      0,
      4,
    ).getUint32(0, Endian.big);
    final headerBytes = payload.sublist(4, 4 + headerLen);
    final map = jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
    final pngData = payload.sublist(4 + headerLen);
    return DrawingImageData(
      fingerprintHex: map['fingerprintHex'] as String,
      username: map['username'] as String,
      pngData: Uint8List.fromList(pngData),
    );
  }
}

/// 猜测结果广播（服务端 → 客户端）
class GuessResultBroadcast {
  final String fingerprintHex;
  final String username;
  final int cardIndex;
  final String guess;
  final String targetFingerprintHex;
  final String targetUsername;

  GuessResultBroadcast({
    required this.fingerprintHex,
    required this.username,
    required this.cardIndex,
    required this.guess,
    required this.targetFingerprintHex,
    required this.targetUsername,
  });

  static GuessResultBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return GuessResultBroadcast(
      fingerprintHex: map['fingerprintHex'] as String,
      username: map['username'] as String,
      cardIndex: map['cardIndex'] as int,
      guess: map['guess'] as String,
      targetFingerprintHex: map['targetFingerprintHex'] as String,
      targetUsername: map['targetUsername'] as String,
    );
  }
}

/// 回合结果广播（服务端 → 客户端）
class RoundResultBroadcast {
  final int round;
  final int totalRounds;
  final List<Map<String, dynamic>> results;

  RoundResultBroadcast({
    required this.round,
    required this.totalRounds,
    required this.results,
  });

  static RoundResultBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return RoundResultBroadcast(
      round: map['round'] as int,
      totalRounds: map['totalRounds'] as int,
      results: (map['results'] as List<dynamic>)
          .map((r) => r as Map<String, dynamic>)
          .toList(),
    );
  }
}

/// 游戏结束广播（服务端 → 客户端）
class GameEndBroadcast {
  final String message;
  final List<Map<String, dynamic>> allResults;

  GameEndBroadcast({required this.message, required this.allResults});

  static GameEndBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return GameEndBroadcast(
      message: map['message'] as String,
      allResults: (map['allResults'] as List<dynamic>)
          .map((r) => r as Map<String, dynamic>)
          .toList(),
    );
  }
}

/// 词条翻牌阶段广播（服务端 → 客户端，每人单独发送）
class WordPickPhaseBroadcast {
  final int round;
  final int totalRounds;
  final int wordPickTime;
  final int cardCount;
  final int excludeCardIndex; // 该玩家需排除的卡牌索引，-1表示无排除
  final List<String> ownerNames; // 与卡牌索引对应的所属者用户名列表

  WordPickPhaseBroadcast({
    required this.round,
    required this.totalRounds,
    required this.wordPickTime,
    required this.cardCount,
    this.excludeCardIndex = -1,
    this.ownerNames = const [],
  });

  static WordPickPhaseBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return WordPickPhaseBroadcast(
      round: map['round'] as int,
      totalRounds: map['totalRounds'] as int,
      wordPickTime: map['wordPickTime'] as int,
      cardCount: map['cardCount'] as int,
      excludeCardIndex: (map['excludeCardIndex'] as int?) ?? -1,
      ownerNames: ((map['ownerNames'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }
}

/// 词条翻牌结果（服务端 → 单个客户端，私发）
class WordPickResult {
  final String word;

  WordPickResult({required this.word});

  static WordPickResult decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return WordPickResult(word: map['word'] as String);
  }
}
