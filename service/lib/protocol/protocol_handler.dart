import 'dart:typed_data';
import 'dart:convert';

/// 消息类型定义
enum MessageType {
  // 客户端 -> 服务端
  loginRequest(0x01),
  heartbeat(0x02),
  disconnect(0x03),
  serverInfoRequest(0x10),
  createRoomRequest(0x20),
  roomListRequest(0x21),
  joinRoomRequest(0x22),
  leaveRoomRequest(0x23),
  roomMemberRequest(0x24),
  reconnectRoomRequest(0x33),
  collabDelta(0x34),
  collabSyncRequest(0x35),
  collabLayerOpRequest(0x36), // 图层操作请求（增删改重排）
  collabLayerDelta(0x37), // 带 layerId 的增量 delta
  chatMessage(0x30),
  updateRoomRequest(0x25), // 修改房间设置请求
  transferRoomRequest(0x26), // 转让房间请求
  readyRequest(0x27), // 准备/取消准备请求
  lexiconUpload(0x28), // 词库上传请求
  lexiconRequest(0x29), // 请求当前词库数据
  gameStart(0x2A), // 游戏开始请求（房主发起，含卡牌数据）
  cardPick(0x2B), // 卡牌选择请求
  drawingUpload(0x2C), // 绘画上传（PNG数据）
  guessSubmit(0x2D), // 猜测提交
  drawingComplete(0x2E), // 客户端通知绘画完成
  replayAck(0x32), // 客户端确认已收到复盘文件

  // 服务端 -> 客户端
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
  drawingPhaseBroadcast(0xAC), // 作画阶段广播（含分配的绘画词、倒计时）
  guessPhaseBroadcast(0xAD), // 猜测阶段广播（含卡牌列表）
  drawingImageData(0xAE), // 下发绘画PNG数据
  roundResultBroadcast(0xAF), // 回合结果广播
  gameEndBroadcast(0xB0), // 游戏结束广播
  guessResultBroadcast(0xB1), // 猜测结果广播（某人完成猜测）
  wordPickPhaseBroadcast(0xB2), // 词条翻牌阶段广播
  wordPickBroadcast(0xB3), // 词条翻牌选择广播
  wordPickResult(0xB4), // 词条翻牌结果（私发给选择者）
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
  reconnectRoomResponse(0xBF), // 断线重连响应
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
    if (data.length < 21)
      throw FormatException('collabDelta payload too short');
    final header = ByteData.sublistView(data, 0, 21);
    final epoch = header.getUint32(0, Endian.big);
    final baseRev = header.getUint32(4, Endian.big);
    final x = header.getUint16(8, Endian.big);
    final y = header.getUint16(10, Endian.big);
    final width = header.getUint16(12, Endian.big);
    final height = header.getUint16(14, Endian.big);
    final flags = header.getUint8(16);
    final len = header.getUint32(17, Endian.big);
    if (data.length < 21 + len)
      throw FormatException('collabDelta payload length mismatch');
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
    final requesterUsername =
        utf8.decode(data.sublist(offset, offset + userLen));
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
    final fixed = ByteData(4 + 4 + 1 + senderLen + 2 + 2 + 2 + 2 + 1 + 4);
    fixed.setUint32(0, epoch, Endian.big);
    fixed.setUint32(4, rev, Endian.big);
    fixed.setUint8(8, senderLen);
    final headerPrefix = fixed.buffer.asUint8List(0, 9);
    buffer.add(headerPrefix);
    if (senderLen > 0)
      buffer.add(Uint8List.fromList(senderBytes.sublist(0, senderLen)));

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
    if (data.length < 9)
      throw FormatException('collabDeltaBroadcast payload too short');
    int offset = 0;
    final epoch =
        ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);
    offset += 4;
    final rev =
        ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);
    offset += 4;
    final senderLen = data[offset++];
    if (data.length < offset + senderLen + 2 + 2 + 2 + 2 + 1 + 4) {
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
    if (data.length < offset + len)
      throw FormatException('collabDeltaBroadcast payload length mismatch');
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

  CollabSyncRequired(
      {required this.authoritativeEpoch, required this.authoritativeRev});

  Uint8List encode() {
    final buffer = ByteData(8);
    buffer.setUint32(0, authoritativeEpoch, Endian.big);
    buffer.setUint32(4, authoritativeRev, Endian.big);
    return buffer.buffer.asUint8List();
  }

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
    if (targetLen > 0)
      buffer.add(Uint8List.fromList(targetBytes.sublist(0, targetLen)));

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
    if (data.isEmpty)
      throw FormatException('collabSnapshotFromOwner payload too short');
    int offset = 0;
    final targetLen = data[offset++];
    if (data.length < offset + targetLen + 13) {
      throw FormatException('collabSnapshotFromOwner payload too short');
    }
    final targetUsername =
        utf8.decode(data.sublist(offset, offset + targetLen));
    offset += targetLen;
    final header = ByteData.sublistView(data, offset, offset + 13);
    final rev = header.getUint32(0, Endian.big);
    final width = header.getUint16(4, Endian.big);
    final height = header.getUint16(6, Endian.big);
    final flags = header.getUint8(8);
    final len = header.getUint32(9, Endian.big);
    offset += 13;
    if (data.length < offset + len)
      throw FormatException('collabSnapshotFromOwner payload length mismatch');
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

  Uint8List encode() {
    final buffer = BytesBuilder();
    final header = ByteData(4 + 4 + 2 + 2 + 1 + 4);
    header.setUint32(0, epoch, Endian.big);
    header.setUint32(4, rev, Endian.big);
    header.setUint16(8, width, Endian.big);
    header.setUint16(10, height, Endian.big);
    header.setUint8(12, flags);
    header.setUint32(13, rgbaZlib.length, Endian.big);
    buffer.add(header.buffer.asUint8List());
    buffer.add(rgbaZlib);
    return buffer.toBytes();
  }

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

// ========== 多图层协同协议 ==========

/// 图层操作类型
enum CollabLayerOpType {
  add(1), // 新增图层
  remove(2), // 删除图层
  rename(3), // 重命名图层
  reorder(4), // 重排图层
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
/// 格式: [opType(1)] [payloadLen(2)] [payload(JSON)]
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

  static CollabLayerOpRequest decode(Uint8List data) {
    if (data.length < 3) {
      throw FormatException('collabLayerOpRequest payload too short');
    }
    final opType = CollabLayerOpType.fromCode(data[0]);
    final payloadLen =
        ByteData.sublistView(data, 1, 3).getUint16(0, Endian.big);
    if (data.length < 3 + payloadLen) {
      throw FormatException('collabLayerOpRequest payload length mismatch');
    }
    final jsonStr = utf8.decode(data.sublist(3, 3 + payloadLen));
    final payload = payloadLen > 0
        ? jsonDecode(jsonStr) as Map<String, dynamic>
        : <String, dynamic>{};
    return CollabLayerOpRequest(opType: opType, payload: payload);
  }
}

/// 图层操作广播（服务端→客户端）
/// 格式: [opType(1)] [payloadLen(2)] [payload(JSON)]
/// payload 内容根据 opType:
///   add:    { layerId, name, ownerId, index, isVisible, isLocked, opacity, blendMode }
///   remove: { layerId }
///   rename: { layerId, name }
///   reorder: { order: [layerId, layerId, ...] }
///   setVisibility: { layerId, isVisible }
///   setOpacity: { layerId, opacity }
///   setLock: { layerId, isLocked }
class CollabLayerOpBroadcast {
  final CollabLayerOpType opType;
  final Map<String, dynamic> payload;

  CollabLayerOpBroadcast({required this.opType, required this.payload});

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

  static CollabLayerOpBroadcast decode(Uint8List data) {
    if (data.length < 3) {
      throw FormatException('collabLayerOpBroadcast payload too short');
    }
    final opType = CollabLayerOpType.fromCode(data[0]);
    final payloadLen =
        ByteData.sublistView(data, 1, 3).getUint16(0, Endian.big);
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
/// 格式: [layerIdLen(1)] [layerId] [epoch(4)] [baseRev(4)]
///        [x(2)] [y(2)] [w(2)] [h(2)] [flags(1)] [payloadLen(4)] [payload]
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

  static CollabLayerDeltaRequest decode(Uint8List data) {
    if (data.isEmpty) {
      throw FormatException('collabLayerDelta payload too short');
    }
    int offset = 0;
    final idLen = data[offset++];
    if (data.length < offset + idLen + 21) {
      throw FormatException('collabLayerDelta payload too short');
    }
    final layerId = utf8.decode(data.sublist(offset, offset + idLen));
    offset += idLen;
    final header = ByteData.sublistView(data, offset, offset + 21);
    final epoch = header.getUint32(0, Endian.big);
    final baseRev = header.getUint32(4, Endian.big);
    final x = header.getUint16(8, Endian.big);
    final y = header.getUint16(10, Endian.big);
    final width = header.getUint16(12, Endian.big);
    final height = header.getUint16(14, Endian.big);
    final flags = header.getUint8(16);
    final len = header.getUint32(17, Endian.big);
    offset += 21;
    if (data.length < offset + len) {
      throw FormatException('collabLayerDelta payload length mismatch');
    }
    final payload = data.sublist(offset, offset + len);
    return CollabLayerDeltaRequest(
      layerId: layerId,
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

/// 带 layerId 的增量 delta 广播（服务端→客户端）
/// 格式: [layerIdLen(1)] [layerId] [epoch(4)] [rev(4)]
///        [senderLen(1)] [senderId] [x(2)] [y(2)] [w(2)] [h(2)]
///        [flags(1)] [payloadLen(4)] [payload]
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

  Uint8List encode() {
    final idBytes = utf8.encode(layerId);
    final idLen = idBytes.length.clamp(0, 255);
    final senderBytes = utf8.encode(senderId);
    final senderLen = senderBytes.length.clamp(0, 255);
    final buffer = BytesBuilder();
    buffer.addByte(idLen);
    if (idLen > 0) buffer.add(Uint8List.fromList(idBytes.sublist(0, idLen)));
    final epochRev = ByteData(8);
    epochRev.setUint32(0, epoch, Endian.big);
    epochRev.setUint32(4, rev, Endian.big);
    buffer.add(epochRev.buffer.asUint8List());
    buffer.addByte(senderLen);
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
          'collabLayerDeltaBroadcast payload length mismatch');
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

/// 多图层快照（服务端→客户端，断线重连/首次同步）
/// 格式: [epoch(4)] [canvasWidth(2)] [canvasHeight(2)] [layerCount(2)]
///   每层: [layerIdLen(1)] [layerId] [nameLen(1)] [name]
///         [ownerIdLen(1)] [ownerId]
///         [visible(1)] [locked(1)] [opacity(1:0-255)] [blendMode(1)]
///         [rev(4)] [rgbaFlags(1)] [rgbaLen(4)] [rgbaBytes]
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

  Uint8List encode() {
    final buffer = BytesBuilder();
    final header = ByteData(4 + 2 + 2 + 2);
    header.setUint32(0, epoch, Endian.big);
    header.setUint16(4, canvasWidth, Endian.big);
    header.setUint16(6, canvasHeight, Endian.big);
    header.setUint16(8, layers.length, Endian.big);
    buffer.add(header.buffer.asUint8List());
    for (final layer in layers) {
      buffer.add(layer.encode());
    }
    return buffer.toBytes();
  }

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

  Uint8List encode() {
    final buffer = BytesBuilder();
    final idBytes = utf8.encode(layerId);
    final idLen = idBytes.length.clamp(0, 255);
    buffer.addByte(idLen);
    if (idLen > 0) buffer.add(Uint8List.fromList(idBytes.sublist(0, idLen)));

    final nameBytes = utf8.encode(name);
    final nameLen = nameBytes.length.clamp(0, 255);
    buffer.addByte(nameLen);
    if (nameLen > 0)
      buffer.add(Uint8List.fromList(nameBytes.sublist(0, nameLen)));

    final ownerBytes = utf8.encode(ownerId);
    final ownerLen = ownerBytes.length.clamp(0, 255);
    buffer.addByte(ownerLen);
    if (ownerLen > 0)
      buffer.add(Uint8List.fromList(ownerBytes.sublist(0, ownerLen)));

    buffer.addByte(isVisible ? 1 : 0);
    buffer.addByte(isLocked ? 1 : 0);
    buffer.addByte(opacity.clamp(0, 255));
    buffer.addByte(blendMode.clamp(0, 255));

    final tail = ByteData(4 + 1 + 4);
    tail.setUint32(0, rev, Endian.big);
    tail.setUint8(4, rgbaFlags);
    tail.setUint32(5, rgbaBytes.length, Endian.big);
    buffer.add(tail.buffer.asUint8List());
    buffer.add(rgbaBytes);
    return buffer.toBytes();
  }

  static ({CollabLayerSnapshotEntry entry, int nextOffset}) decodeFrom(
      Uint8List data, int offset) {
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

  static ReconnectRoomRequest decode(Uint8List payload) {
    if (payload.isEmpty) throw FormatException('断线重连请求负载为空');
    final len = payload[0];
    if (payload.length < 1 + len) throw FormatException('断线重连请求负载不足');
    final roomId = utf8.decode(payload.sublist(1, 1 + len));
    return ReconnectRoomRequest(roomId: roomId);
  }
}

/// 断线重连响应
/// 格式: [success(1字节)] [roomId长度(1字节)] [roomId] [error长度(1字节)] [error]
class ReconnectRoomResponse {
  final bool success;
  final String roomId;
  final String? errorMessage;

  ReconnectRoomResponse(
      {required this.success, required this.roomId, this.errorMessage});

  Uint8List encode() {
    final roomBytes = utf8.encode(roomId);
    final roomLen = roomBytes.length.clamp(0, 255);
    final errBytes = utf8.encode(errorMessage ?? '');
    final errLen = errBytes.length.clamp(0, 255);
    final buffer = BytesBuilder();
    buffer.addByte(success ? 1 : 0);
    buffer.addByte(roomLen);
    if (roomLen > 0) buffer.add(roomBytes.sublist(0, roomLen));
    buffer.addByte(errLen);
    if (errLen > 0) buffer.add(errBytes.sublist(0, errLen));
    return buffer.toBytes();
  }

  static ReconnectRoomResponse decode(Uint8List payload) {
    if (payload.isEmpty) {
      return ReconnectRoomResponse(
          success: false, roomId: '', errorMessage: '响应为空');
    }
    int offset = 0;
    final success = payload[offset++] == 1;
    if (offset >= payload.length) {
      return ReconnectRoomResponse(
          success: success,
          roomId: '',
          errorMessage: success ? null : '响应格式错误');
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

class ScorePodiumBroadcast {
  final String roomId;
  final int endAtMs;
  final List<Map<String, dynamic>> top3;

  ScorePodiumBroadcast({
    required this.roomId,
    required this.endAtMs,
    required this.top3,
  });

  Uint8List encode() {
    final map = {
      'roomId': roomId,
      'endAtMs': endAtMs,
      'top3': top3,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

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

  Uint8List encode() {
    final bytes = utf8.encode(roomId);
    final len = bytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len);
    buffer[0] = len;
    if (len > 0) buffer.setAll(1, bytes.sublist(0, len));
    return buffer;
  }

  static GameResetBroadcast decode(Uint8List payload) {
    if (payload.isEmpty) return GameResetBroadcast(roomId: '');
    final len = payload[0];
    final roomId = (payload.length >= 1 + len)
        ? utf8.decode(payload.sublist(1, 1 + len))
        : '';
    return GameResetBroadcast(roomId: roomId);
  }
}

class FavoriteSelectionStartBroadcast {
  final String pickerUsername;

  FavoriteSelectionStartBroadcast({required this.pickerUsername});

  Uint8List encode() {
    final bytes = utf8.encode(pickerUsername);
    final len = bytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len);
    buffer[0] = len;
    if (len > 0) buffer.setAll(1, bytes.sublist(0, len));
    return buffer;
  }

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

  Uint8List encode() {
    return Uint8List.fromList([drawingIndex.clamp(0, 255)]);
  }

  static FavoriteResultBroadcast decode(Uint8List payload) {
    if (payload.isEmpty) return FavoriteResultBroadcast(drawingIndex: 0);
    return FavoriteResultBroadcast(drawingIndex: payload[0]);
  }
}

class ReviewProgressBroadcast {
  final int pathIndex;
  final int stepIndex;

  ReviewProgressBroadcast({required this.pathIndex, required this.stepIndex});

  Uint8List encode() {
    final bd = ByteData(4);
    bd.setUint16(0, pathIndex.clamp(0, 65535), Endian.big);
    bd.setUint16(2, stepIndex.clamp(0, 65535), Endian.big);
    return bd.buffer.asUint8List();
  }

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

  static ReplayAck decode(Uint8List payload) {
    if (payload.isEmpty) return ReplayAck(replayId: '');
    final len = payload[0];
    final id = (payload.length >= 1 + len)
        ? utf8.decode(payload.sublist(1, 1 + len))
        : '';
    return ReplayAck(replayId: id);
  }
}

class ReplayFileBroadcast {
  final Map<String, dynamic> replay;

  ReplayFileBroadcast({required this.replay});

  Uint8List encode() {
    final json = jsonEncode(replay);
    return Uint8List.fromList(utf8.encode(json));
  }

  static ReplayFileBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return ReplayFileBroadcast(replay: map);
  }
}

class VoteSubmit {
  final bool isUp; // true为勾，false为叉

  VoteSubmit({required this.isUp});

  Uint8List encode() => Uint8List.fromList([isUp ? 1 : 0]);

  static VoteSubmit decode(Uint8List payload) {
    if (payload.isEmpty) return VoteSubmit(isUp: false);
    return VoteSubmit(isUp: payload[0] == 1);
  }
}

class VoteResultBroadcast {
  final String username;
  final bool isUp;

  VoteResultBroadcast({required this.username, required this.isUp});

  Uint8List encode() {
    final nameBytes = utf8.encode(username);
    final buffer = Uint8List(1 + nameBytes.length + 1);
    buffer[0] = nameBytes.length;
    buffer.setAll(1, nameBytes);
    buffer[1 + nameBytes.length] = isUp ? 1 : 0;
    return buffer;
  }

  static VoteResultBroadcast decode(Uint8List payload) {
    if (payload.isEmpty) return VoteResultBroadcast(username: '', isUp: false);
    final len = payload[0];
    final username = utf8.decode(payload.sublist(1, 1 + len));
    final isUp = payload[1 + len] == 1;
    return VoteResultBroadcast(username: username, isUp: isUp);
  }
}

class FavoriteSubmit {
  final int drawingIndex; // 被选中的画作索引

  FavoriteSubmit({required this.drawingIndex});

  Uint8List encode() => Uint8List.fromList([drawingIndex]);

  static FavoriteSubmit decode(Uint8List payload) {
    if (payload.isEmpty) return FavoriteSubmit(drawingIndex: 0);
    return FavoriteSubmit(drawingIndex: payload[0]);
  }
}

class ScoreUpdateBroadcast {
  final Map<String, int> scores; // username -> score

  ScoreUpdateBroadcast({required this.scores});

  Uint8List encode() {
    final jsonStr = jsonEncode(scores);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  static ScoreUpdateBroadcast decode(Uint8List payload) {
    final jsonStr = utf8.decode(payload);
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return ScoreUpdateBroadcast(
        scores: map.map((k, v) => MapEntry(k, v as int)));
  }
}

/// 协议处理器 - 二进制消息编解码
class ProtocolHandler {
  /// 消息头长度: 4字节长度 + 1字节类型
  static const int headerLength = 5;

  /// 封装消息
  /// 格式: [长度(4字节, 大端)] [类型(1字节)] [负载]
  static Uint8List encode(MessageType type, Uint8List payload) {
    final totalLength = headerLength + payload.length;
    final buffer = ByteData(totalLength);

    // 写入长度 (大端序)
    buffer.setUint32(0, totalLength, Endian.big);
    // 写入类型
    buffer.setUint8(4, type.code);
    // 写入负载
    buffer.buffer.asUint8List().setAll(headerLength, payload);

    return buffer.buffer.asUint8List();
  }

  /// 解析消息头
  /// 返回 (消息总长度, 消息类型) 或 null (数据不足)
  static (int, MessageType)? decodeHeader(Uint8List data) {
    if (data.length < headerLength) return null;

    final byteData = ByteData.sublistView(data);
    final totalLength = byteData.getUint32(0, Endian.big);
    final typeCode = byteData.getUint8(4);
    final type = MessageType.fromCode(typeCode);

    return (totalLength, type);
  }

  /// 提取负载
  static Uint8List extractPayload(Uint8List data) {
    if (data.length <= headerLength) return Uint8List(0);
    return data.sublist(headerLength);
  }
}

/// 登录请求消息
class LoginRequest {
  final String username;
  final Uint8List fingerprint; // 8字节

  LoginRequest({required this.username, required this.fingerprint});

  /// 编码
  /// 格式: [用户名长度(1字节)] [用户名(UTF-8)] [指纹(8字节)]
  Uint8List encode() {
    final usernameBytes = utf8.encode(username);
    final len = usernameBytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + len + 8);

    buffer[0] = len;
    if (len > 0) buffer.setAll(1, usernameBytes.sublist(0, len));
    buffer.setAll(1 + len, fingerprint);

    return buffer;
  }

  /// 解码
  static LoginRequest decode(Uint8List payload) {
    if (payload.isEmpty) {
      throw FormatException('负载为空');
    }

    final usernameLength = payload[0];
    if (payload.length < 1 + usernameLength + 8) {
      throw FormatException('负载长度不足');
    }

    final usernameBytes = payload.sublist(1, 1 + usernameLength);
    final username = utf8.decode(usernameBytes);
    final fingerprint =
        payload.sublist(1 + usernameLength, 1 + usernameLength + 8);

    return LoginRequest(username: username, fingerprint: fingerprint);
  }
}

/// 登录响应消息
class LoginResponse {
  final bool success;
  final String? errorMessage;

  LoginResponse({required this.success, this.errorMessage});

  /// 编码
  /// 格式: [状态码(1字节: 0x00成功, 0x01失败)] [错误消息长度(1字节, 可选)] [错误消息(UTF-8, 可选)]
  Uint8List encode() {
    if (success) {
      return Uint8List.fromList([0x00]);
    } else {
      final errorBytes = errorMessage != null
          ? Uint8List.fromList(utf8.encode(errorMessage!))
          : Uint8List(0);
      final buffer = Uint8List(2 + errorBytes.length);
      buffer[0] = 0x01;
      buffer[1] = errorBytes.length;
      buffer.setAll(2, errorBytes);
      return buffer;
    }
  }

  /// 解码
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
  final int timestamp; // Unix 时间戳 (秒)

  HeartbeatMessage({int? timestamp})
      : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// 编码
  Uint8List encode() {
    final buffer = ByteData(4);
    buffer.setUint32(0, timestamp, Endian.big);
    return buffer.buffer.asUint8List();
  }

  /// 解码
  static HeartbeatMessage decode(Uint8List payload) {
    if (payload.length < 4) {
      return HeartbeatMessage();
    }
    final byteData = ByteData.sublistView(payload);
    final timestamp = byteData.getUint32(0, Endian.big);
    return HeartbeatMessage(timestamp: timestamp);
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

  Uint8List encode() {
    final nameBytes = utf8.encode(serverName);
    final len = nameBytes.length.clamp(0, 255).toInt();
    // [名称长度(1)] [名称] [当前连接数(2)] [最大连接数(2)] [当前房间数(2)] [最大房间数(2)]
    final payload = Uint8List(1 + len + 2 + 2 + 2 + 2);
    final byteData = ByteData.sublistView(payload);
    payload[0] = len;
    if (len > 0) {
      payload.setAll(1, nameBytes.sublist(0, len));
    }
    int offset = 1 + len;
    byteData.setUint16(offset, currentConnections, Endian.big);
    offset += 2;
    byteData.setUint16(offset, maxConnections, Endian.big);
    offset += 2;
    byteData.setUint16(offset, currentRooms, Endian.big);
    offset += 2;
    byteData.setUint16(offset, maxRooms, Endian.big);
    return payload;
  }

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
      currentConnections = ByteData.sublistView(payload, offset, offset + 2)
          .getUint16(0, Endian.big);
      offset += 2;
    }
    if (payload.length >= offset + 2) {
      maxConnections = ByteData.sublistView(payload, offset, offset + 2)
          .getUint16(0, Endian.big);
      offset += 2;
    }
    if (payload.length >= offset + 2) {
      currentRooms = ByteData.sublistView(payload, offset, offset + 2)
          .getUint16(0, Endian.big);
      offset += 2;
    }
    if (payload.length >= offset + 2) {
      maxRooms = ByteData.sublistView(payload, offset, offset + 2)
          .getUint16(0, Endian.big);
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

/// 房间类型
enum RoomType {
  relay(0x01), // 接龙
  collab(0x02); // 协同绘画

  final int code;
  const RoomType(this.code);

  static RoomType fromCode(int code) {
    return RoomType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => RoomType.relay,
    );
  }

  String get displayName {
    switch (this) {
      case RoomType.relay:
        return '接龙';
      case RoomType.collab:
        return '协同';
    }
  }
}

/// 创建房间请求
/// 格式: [房间类型(1字节)] [房间名称长度(1字节)] [房间名称(UTF-8)] [人数上限(1字节)]
class CreateRoomRequest {
  final RoomType roomType;
  final String roomName;
  final int maxPlayers;

  CreateRoomRequest({
    required this.roomType,
    required this.roomName,
    required this.maxPlayers,
  });

  Uint8List encode() {
    final nameBytes = utf8.encode(roomName);
    final len = nameBytes.length.clamp(0, 255);
    final buffer = Uint8List(1 + 1 + len + 1);
    buffer[0] = roomType.code;
    buffer[1] = len;
    if (len > 0) buffer.setAll(2, nameBytes.sublist(0, len));
    buffer[2 + len] = maxPlayers.clamp(1, 16);
    return buffer;
  }

  static CreateRoomRequest decode(Uint8List payload) {
    if (payload.length < 3) throw FormatException('创建房间请求负载过短');
    final roomType = RoomType.fromCode(payload[0]);
    final nameLen = payload[1];
    if (payload.length < 2 + nameLen + 1) {
      throw FormatException('创建房间请求负载长度不足');
    }
    final roomName = utf8.decode(payload.sublist(2, 2 + nameLen));
    final maxPlayers = payload[2 + nameLen];
    return CreateRoomRequest(
      roomType: roomType,
      roomName: roomName,
      maxPlayers: maxPlayers,
    );
  }
}

/// 创建房间响应
/// 格式: [状态码(1字节: 0x00成功)] [房间代号长度(1字节)] [房间代号(UTF-8)] 或 [错误消息长度(1字节)] [错误消息]
class CreateRoomResponse {
  final bool success;
  final String? roomId;
  final String? errorMessage;

  CreateRoomResponse({required this.success, this.roomId, this.errorMessage});

  Uint8List encode() {
    if (success && roomId != null) {
      final idBytes = utf8.encode(roomId!);
      final len = idBytes.length.clamp(0, 255);
      final buffer = Uint8List(1 + 1 + len);
      buffer[0] = 0x00;
      buffer[1] = len;
      if (len > 0) buffer.setAll(2, idBytes.sublist(0, len));
      return buffer;
    } else {
      final errBytes = utf8.encode(errorMessage ?? '未知错误');
      final len = errBytes.length.clamp(0, 255);
      final buffer = Uint8List(1 + 1 + len);
      buffer[0] = 0x01;
      buffer[1] = len;
      if (len > 0) buffer.setAll(2, errBytes.sublist(0, len));
      return buffer;
    }
  }

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

/// 房间列表请求（无负载）
class RoomListRequest {
  Uint8List encode() => Uint8List(0);
}

/// 房间信息（用于列表中）
class RoomInfo {
  final String roomId;
  final String roomName;
  final RoomType roomType;
  final int currentPlayers;
  final int maxPlayers;
  final String ownerName;
  final int rounds;
  final int roundTime;
  final String lexiconKey;
  final bool isGameActive;

  RoomInfo({
    required this.roomId,
    required this.roomName,
    required this.roomType,
    required this.currentPlayers,
    required this.maxPlayers,
    required this.ownerName,
    this.rounds = 5,
    this.roundTime = 60,
    this.lexiconKey = '',
    this.isGameActive = false,
  });

  Uint8List encode() {
    final idBytes = utf8.encode(roomId);
    final nameBytes = utf8.encode(roomName);
    final ownerBytes = utf8.encode(ownerName);
    final lexiconKeyBytes = utf8.encode(lexiconKey);
    final idLen = idBytes.length.clamp(0, 255);
    final nameLen = nameBytes.length.clamp(0, 255);
    final ownerLen = ownerBytes.length.clamp(0, 255);
    final lexiconKeyLen = lexiconKeyBytes.length.clamp(0, 255);
    // [idLen(1)] [id] [nameLen(1)] [name] [type(1)] [current(1)] [max(1)] [ownerLen(1)] [owner] [rounds(1)] [roundTime(2)] [lexiconKeyLen(1)] [lexiconKey] [isGameActive(1)]
    final buffer = Uint8List(1 +
        idLen +
        1 +
        nameLen +
        1 +
        1 +
        1 +
        1 +
        ownerLen +
        1 +
        2 +
        1 +
        lexiconKeyLen +
        1);
    int offset = 0;
    buffer[offset++] = idLen;
    buffer.setAll(offset, idBytes.sublist(0, idLen));
    offset += idLen;
    buffer[offset++] = nameLen;
    buffer.setAll(offset, nameBytes.sublist(0, nameLen));
    offset += nameLen;
    buffer[offset++] = roomType.code;
    buffer[offset++] = currentPlayers;
    buffer[offset++] = maxPlayers;
    buffer[offset++] = ownerLen;
    buffer.setAll(offset, ownerBytes.sublist(0, ownerLen));
    offset += ownerLen;
    buffer[offset++] = rounds;
    // roundTime 使用2字节（大端序）
    final roundTimeData = ByteData.sublistView(buffer, offset, offset + 2);
    roundTimeData.setUint16(0, roundTime, Endian.big);
    offset += 2;
    buffer[offset++] = lexiconKeyLen;
    if (lexiconKeyLen > 0) {
      buffer.setAll(offset, lexiconKeyBytes.sublist(0, lexiconKeyLen));
      offset += lexiconKeyLen;
    }
    buffer[offset++] = isGameActive ? 1 : 0;
    return buffer;
  }

  static (RoomInfo, int) decodeAt(Uint8List data, int start) {
    int offset = start;
    final idLen = data[offset++];
    final roomId = utf8.decode(data.sublist(offset, offset + idLen));
    offset += idLen;
    final nameLen = data[offset++];
    final roomName = utf8.decode(data.sublist(offset, offset + nameLen));
    offset += nameLen;
    final roomType = RoomType.fromCode(data[offset++]);
    final currentPlayers = data[offset++];
    final maxPlayers = data[offset++];
    final ownerLen = data[offset++];
    final ownerName = utf8.decode(data.sublist(offset, offset + ownerLen));
    offset += ownerLen;
    final rounds = data[offset++];
    // roundTime 使用2字节（大端序）
    final roundTime =
        ByteData.sublistView(data, offset, offset + 2).getUint16(0, Endian.big);
    offset += 2;
    final lexiconKeyLen = data[offset++];
    final lexiconKey = lexiconKeyLen > 0
        ? utf8.decode(data.sublist(offset, offset + lexiconKeyLen))
        : '';
    offset += lexiconKeyLen;
    bool isGameActive = false;
    if (offset < data.length) {
      isGameActive = data[offset++] != 0;
    }
    return (
      RoomInfo(
        roomId: roomId,
        roomName: roomName,
        roomType: roomType,
        currentPlayers: currentPlayers,
        maxPlayers: maxPlayers,
        ownerName: ownerName,
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
/// 格式: [房间数量(1字节)] [房间信息1] [房间信息2] ...
class RoomListResponse {
  final List<RoomInfo> rooms;

  RoomListResponse({required this.rooms});

  Uint8List encode() {
    final parts = <int>[rooms.length.clamp(0, 255)];
    for (final room in rooms) {
      parts.addAll(room.encode());
    }
    return Uint8List.fromList(parts);
  }

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
/// 格式: [房间代号长度(1字节)] [房间代号(UTF-8)]
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

  static JoinRoomRequest decode(Uint8List payload) {
    if (payload.isEmpty) throw FormatException('加入房间请求负载为空');
    final len = payload[0];
    if (payload.length < 1 + len) throw FormatException('加入房间请求负载不足');
    final roomId = utf8.decode(payload.sublist(1, 1 + len));
    return JoinRoomRequest(roomId: roomId);
  }
}

/// 加入房间响应
/// 格式: [状态码(1字节)] [房间代号长度(1字节)] [房间代号] 或 [错误消息长度(1字节)] [错误消息]
class JoinRoomResponse {
  final bool success;
  final String? roomId;
  final String? errorMessage;

  JoinRoomResponse({required this.success, this.roomId, this.errorMessage});

  Uint8List encode() {
    if (success && roomId != null) {
      final idBytes = utf8.encode(roomId!);
      final len = idBytes.length.clamp(0, 255);
      final buffer = Uint8List(1 + 1 + len);
      buffer[0] = 0x00;
      buffer[1] = len;
      if (len > 0) buffer.setAll(2, idBytes.sublist(0, len));
      return buffer;
    } else {
      final errBytes = utf8.encode(errorMessage ?? '未知错误');
      final len = errBytes.length.clamp(0, 255);
      final buffer = Uint8List(1 + 1 + len);
      buffer[0] = 0x01;
      buffer[1] = len;
      if (len > 0) buffer.setAll(2, errBytes.sublist(0, len));
      return buffer;
    }
  }

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

  static LeaveRoomRequest decode(Uint8List payload) {
    if (payload.isEmpty) throw FormatException('离开房间请求负载为空');
    final len = payload[0];
    final roomId = utf8.decode(payload.sublist(1, 1 + len));
    return LeaveRoomRequest(roomId: roomId);
  }
}

/// 离开房间响应
class LeaveRoomResponse {
  final bool success;

  LeaveRoomResponse({required this.success});

  Uint8List encode() => Uint8List.fromList([success ? 0x00 : 0x01]);

  static LeaveRoomResponse decode(Uint8List payload) {
    if (payload.isEmpty) return LeaveRoomResponse(success: false);
    return LeaveRoomResponse(success: payload[0] == 0x00);
  }
}

class RoomMember {
  final String username;
  final String fingerprintHex;
  bool isReady;
  bool isOnline;

  RoomMember(
      {required this.username,
      required this.fingerprintHex,
      this.isReady = false,
      this.isOnline = true});

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
        isOnline: isOnline);
  }
}

/// 房间成员更新（服务端主动推送）
/// 格式: [房间代号长度(1字节)] [房间代号] [成员数量(1字节)] [成员1名字长度][成员1名字][成员1指纹长度][成员1指纹]...
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

  static RoomMemberRequest decode(Uint8List payload) {
    if (payload.isEmpty) throw FormatException('房间成员请求负载为空');
    final len = payload[0];
    if (payload.length < 1 + len) throw FormatException('房间成员请求负载不足');
    final roomId = utf8.decode(payload.sublist(1, 1 + len));
    return RoomMemberRequest(roomId: roomId);
  }
}

/// 聊天消息
/// 格式: [房间代号长度(1字节)] [房间代号] [发送者长度(1字节)] [发送者] [内容长度(2字节)] [内容]
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

    final contentLen = ByteData.sublistView(payload, offset, offset + 2)
        .getUint16(0, Endian.big);
    offset += 2;
    final content = utf8.decode(payload.sublist(offset, offset + contentLen));

    return ChatMessage(roomId: roomId, sender: sender, content: content);
  }
}

/// 房间转让通知
/// 格式: [旧房间ID长度][旧房间ID][新房间ID长度][新房间ID][新房主用户名长度][新房主用户名][新房主指纹长度][新房主指纹]
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

  Uint8List encode() {
    final oldIdBytes = utf8.encode(oldRoomId);
    final newIdBytes = utf8.encode(newRoomId);
    final userBytes = utf8.encode(newOwnerUsername);
    final fpBytes = utf8.encode(newOwnerFingerprintHex);

    final buffer = BytesBuilder();
    buffer.addByte(oldIdBytes.length);
    buffer.add(oldIdBytes);
    buffer.addByte(newIdBytes.length);
    buffer.add(newIdBytes);
    buffer.addByte(userBytes.length);
    buffer.add(userBytes);
    buffer.addByte(fpBytes.length);
    buffer.add(fpBytes);

    return buffer.toBytes();
  }

  static RoomOwnerTransfer decode(Uint8List payload) {
    int offset = 0;

    final oldIdLen = payload[offset++];
    final oldRoomId = utf8.decode(payload.sublist(offset, offset + oldIdLen));
    offset += oldIdLen;

    final newIdLen = payload[offset++];
    final newRoomId = utf8.decode(payload.sublist(offset, offset + newIdLen));
    offset += newIdLen;

    final userLen = payload[offset++];
    final newOwnerUsername =
        utf8.decode(payload.sublist(offset, offset + userLen));
    offset += userLen;

    final fpLen = payload[offset++];
    final newOwnerFingerprintHex =
        utf8.decode(payload.sublist(offset, offset + fpLen));

    return RoomOwnerTransfer(
      oldRoomId: oldRoomId,
      newRoomId: newRoomId,
      newOwnerUsername: newOwnerUsername,
      newOwnerFingerprintHex: newOwnerFingerprintHex,
    );
  }
}

/// 修改房间设置请求
/// 格式: [房间ID长度][房间ID][房间名称长度][房间名称][房间类型][最大人数][回合数][回合时间][词库key长度][词库key]
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

  static UpdateRoomRequest decode(Uint8List payload) {
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
    final roundTime = ByteData.sublistView(payload, offset, offset + 2)
        .getUint16(0, Endian.big);
    offset += 2;
    final lexiconKeyLen = payload[offset++];
    final lexiconKey = lexiconKeyLen > 0
        ? utf8.decode(payload.sublist(offset, offset + lexiconKeyLen))
        : '';

    offset += lexiconKeyLen;

    int canvasWidth = 1280;
    int canvasHeight = 720;
    if (payload.length >= offset + 4) {
      canvasWidth = ByteData.sublistView(payload, offset, offset + 2)
          .getUint16(0, Endian.big);
      canvasHeight = ByteData.sublistView(payload, offset + 2, offset + 4)
          .getUint16(0, Endian.big);
    }

    return UpdateRoomRequest(
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

/// 修改房间设置响应
/// 格式: [状态码][错误消息长度][错误消息]
class UpdateRoomResponse {
  final bool success;
  final String errorMessage;

  UpdateRoomResponse({required this.success, this.errorMessage = ''});

  Uint8List encode() {
    final msgBytes = utf8.encode(errorMessage);
    final buffer = Uint8List(2 + msgBytes.length);
    buffer[0] = success ? 0x00 : 0x01;
    buffer[1] = msgBytes.length;
    buffer.setAll(2, msgBytes);
    return buffer;
  }

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
/// 格式: [房间ID长度][房间ID][房间名称长度][房间名称][房间类型][最大人数][回合数][回合时间][词库key长度][词库key]
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
    return buffer.toBytes();
  }

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
    final roundTime = ByteData.sublistView(payload, offset, offset + 2)
        .getUint16(0, Endian.big);
    offset += 2;
    final lexiconKeyLen = payload[offset++];
    final lexiconKey = lexiconKeyLen > 0
        ? utf8.decode(payload.sublist(offset, offset + lexiconKeyLen))
        : '';

    offset += lexiconKeyLen;

    int canvasWidth = 1280;
    int canvasHeight = 720;
    if (payload.length >= offset + 4) {
      canvasWidth = ByteData.sublistView(payload, offset, offset + 2)
          .getUint16(0, Endian.big);
      canvasHeight = ByteData.sublistView(payload, offset + 2, offset + 4)
          .getUint16(0, Endian.big);
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
/// 格式: [房间ID长度][房间ID][新房主用户名长度][新房主用户名][新房主指纹长度][新房主指纹]
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

  static TransferRoomRequest decode(Uint8List payload) {
    int offset = 0;
    final idLen = payload[offset++];
    final roomId = utf8.decode(payload.sublist(offset, offset + idLen));
    offset += idLen;
    final userLen = payload[offset++];
    final newOwnerUsername =
        utf8.decode(payload.sublist(offset, offset + userLen));
    offset += userLen;
    final fpLen = payload[offset++];
    final newOwnerFingerprintHex =
        utf8.decode(payload.sublist(offset, offset + fpLen));
    return TransferRoomRequest(
      roomId: roomId,
      newOwnerUsername: newOwnerUsername,
      newOwnerFingerprintHex: newOwnerFingerprintHex,
    );
  }
}

/// 转让房间响应
/// 格式: [状态码][错误消息长度][错误消息]
class TransferRoomResponse {
  final bool success;
  final String errorMessage;

  TransferRoomResponse({required this.success, this.errorMessage = ''});

  Uint8List encode() {
    final msgBytes = utf8.encode(errorMessage);
    final buffer = Uint8List(2 + msgBytes.length);
    buffer[0] = success ? 0x00 : 0x01;
    buffer[1] = msgBytes.length;
    buffer.setAll(2, msgBytes);
    return buffer;
  }

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

/// 游戏开始消息（房主发起）
/// payload 为 JSON 字符串，包含卡牌索引列表
/// 格式: UTF-8 JSON => {"cardIndices": [3, 0, 7, 1, ...]}
class GameStartMessage {
  final List<int> cardIndices;

  GameStartMessage({required this.cardIndices});

  Uint8List encode() {
    final json = '{"cardIndices":${cardIndices.toString()}}';
    return Uint8List.fromList(utf8.encode(json));
  }

  static GameStartMessage decode(Uint8List payload) {
    final jsonStr = utf8.decode(payload);
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final indices = (map['cardIndices'] as List<dynamic>).cast<int>();
    return GameStartMessage(cardIndices: indices);
  }
}

/// 卡牌选择消息
/// 格式: [cardIndex(1字节)]
class CardPickMessage {
  final int cardIndex;

  CardPickMessage({required this.cardIndex});

  Uint8List encode() {
    return Uint8List.fromList([cardIndex]);
  }

  static CardPickMessage decode(Uint8List payload) {
    if (payload.isEmpty) throw FormatException('卡牌选择负载为空');
    return CardPickMessage(cardIndex: payload[0]);
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

  Uint8List encode() {
    final userBytes = utf8.encode(username);
    final fpBytes = utf8.encode(fingerprintHex);
    final buffer = BytesBuilder();
    buffer.addByte(cardIndex);
    buffer.addByte(userBytes.length);
    buffer.add(userBytes);
    buffer.addByte(fpBytes.length);
    buffer.add(fpBytes);
    return buffer.toBytes();
  }

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

/// 作画阶段广播消息
/// 服务端 → 每个客户端（每人收到自己的绘画词）
/// JSON格式: {"round": 1, "totalRounds": 5, "drawTime": 60, "word": "苹果",
///            "memberWords": {"fingerprint1": 0, "fingerprint2": 1, ...}}
/// memberWords: 每个成员指纹 → 词库索引（仅房主用于追踪，其他人只看自己的word）
class DrawingPhaseBroadcast {
  final int round;
  final int totalRounds;
  final int drawTime; // 作画时间（秒）
  final String word; // 当前用户分配的绘画词
  final Map<String, int> memberWords; // fingerprintHex -> lexicon index

  DrawingPhaseBroadcast({
    required this.round,
    required this.totalRounds,
    required this.drawTime,
    required this.word,
    this.memberWords = const {},
  });

  Uint8List encode() {
    final json = jsonEncode({
      'round': round,
      'totalRounds': totalRounds,
      'drawTime': drawTime,
      'word': word,
      'memberWords': memberWords,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  static DrawingPhaseBroadcast decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return DrawingPhaseBroadcast(
      round: map['round'] as int,
      totalRounds: map['totalRounds'] as int,
      drawTime: map['drawTime'] as int,
      word: map['word'] as String,
      memberWords: (map['memberWords'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
    );
  }
}

/// 猜测阶段广播消息
/// JSON格式: {"round": 1, "totalRounds": 5, "guessTime": 30, "cardPickTime": 10,
///            "cards": [{"label": "用户名", "fingerprintHex": "abc123"}, ...]}
/// 第一回合cards中label为成员名字，后续回合label为上一轮猜测文本
class GuessPhaseBroadcast {
  final int round;
  final int totalRounds;
  final int guessTime; // 猜测时间（秒）
  final int cardPickTime; // 抽卡时间（秒）
  final List<GuessCard> cards; // 卡牌列表（已打乱）

  GuessPhaseBroadcast({
    required this.round,
    required this.totalRounds,
    required this.guessTime,
    required this.cardPickTime,
    required this.cards,
  });

  Uint8List encode() {
    final json = jsonEncode({
      'round': round,
      'totalRounds': totalRounds,
      'guessTime': guessTime,
      'cardPickTime': cardPickTime,
      'cards': cards.map((c) => c.toJson()).toList(),
    });
    return Uint8List.fromList(utf8.encode(json));
  }

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
  final String label; // 卡牌显示文字（第一轮=用户名，后续=上轮猜测文本）
  final String fingerprintHex; // 对应绘画者的指纹
  final String username; // 对应绘画者的用户名

  GuessCard({
    required this.label,
    required this.fingerprintHex,
    required this.username,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'fingerprintHex': fingerprintHex,
        'username': username,
      };

  static GuessCard fromJson(Map<String, dynamic> json) => GuessCard(
        label: json['label'] as String,
        fingerprintHex: json['fingerprintHex'] as String,
        username: json['username'] as String,
      );
}

/// 绘画上传消息（客户端 → 服务端）
/// payload: 原始PNG字节数据
class DrawingUploadMessage {
  final Uint8List pngData;

  DrawingUploadMessage({required this.pngData});

  Uint8List encode() => pngData;

  static DrawingUploadMessage decode(Uint8List payload) {
    return DrawingUploadMessage(pngData: payload);
  }
}

/// 猜测提交消息（客户端 → 服务端）
/// JSON: {"cardIndex": 0, "guess": "苹果"}
class GuessSubmitMessage {
  final int cardIndex; // 所选卡牌索引
  final String guess; // 猜测文本

  GuessSubmitMessage({required this.cardIndex, required this.guess});

  Uint8List encode() {
    final json = jsonEncode({'cardIndex': cardIndex, 'guess': guess});
    return Uint8List.fromList(utf8.encode(json));
  }

  static GuessSubmitMessage decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return GuessSubmitMessage(
      cardIndex: map['cardIndex'] as int,
      guess: map['guess'] as String,
    );
  }
}

/// 绘画图片数据下发（服务端 → 客户端）
/// JSON头 + PNG数据
/// 格式: [jsonHeaderLen(4字节大端)] [jsonHeader] [pngData]
/// jsonHeader: {"fingerprintHex": "abc", "username": "user1"}
class DrawingImageData {
  final String fingerprintHex;
  final String username;
  final Uint8List pngData;

  DrawingImageData({
    required this.fingerprintHex,
    required this.username,
    required this.pngData,
  });

  Uint8List encode() {
    final header = jsonEncode({
      'fingerprintHex': fingerprintHex,
      'username': username,
    });
    final headerBytes = utf8.encode(header);
    final buffer = BytesBuilder();
    final lenData = ByteData(4);
    lenData.setUint32(0, headerBytes.length, Endian.big);
    buffer.add(lenData.buffer.asUint8List());
    buffer.add(headerBytes);
    buffer.add(pngData);
    return buffer.toBytes();
  }

  static DrawingImageData decode(Uint8List payload) {
    final headerLen =
        ByteData.sublistView(payload, 0, 4).getUint32(0, Endian.big);
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

/// 猜测结果广播（服务端 → 房间所有人）
/// JSON: {"fingerprintHex": "abc", "username": "user1", "cardIndex": 0,
///        "guess": "苹果", "targetFingerprintHex": "def", "targetUsername": "user2"}
class GuessResultBroadcast {
  final String fingerprintHex; // 猜测者
  final String username; // 猜测者名
  final int cardIndex;
  final String guess;
  final String targetFingerprintHex; // 被猜的绘画者
  final String targetUsername;

  GuessResultBroadcast({
    required this.fingerprintHex,
    required this.username,
    required this.cardIndex,
    required this.guess,
    required this.targetFingerprintHex,
    required this.targetUsername,
  });

  Uint8List encode() {
    final json = jsonEncode({
      'fingerprintHex': fingerprintHex,
      'username': username,
      'cardIndex': cardIndex,
      'guess': guess,
      'targetFingerprintHex': targetFingerprintHex,
      'targetUsername': targetUsername,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

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

/// 回合结果广播（服务端 → 房间所有人）
/// JSON: {"round": 1, "totalRounds": 5, "results": [...]}
class RoundResultBroadcast {
  final int round;
  final int totalRounds;
  final List<Map<String, dynamic>> results; // 每人的绘画词+猜测结果

  RoundResultBroadcast({
    required this.round,
    required this.totalRounds,
    required this.results,
  });

  Uint8List encode() {
    final json = jsonEncode({
      'round': round,
      'totalRounds': totalRounds,
      'results': results,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

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

/// 游戏结束广播（服务端 → 房间所有人）
/// JSON: {"message": "游戏结束", "allResults": [...]}
class GameEndBroadcast {
  final String message;
  final List<Map<String, dynamic>> allResults;

  GameEndBroadcast({required this.message, required this.allResults});

  Uint8List encode() {
    final json = jsonEncode({
      'message': message,
      'allResults': allResults,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

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

/// 词条翻牌阶段广播（服务端 → 每个客户端单独发送）
/// JSON: {"round": 1, "totalRounds": 5, "wordPickTime": 10, "cardCount": 4, "excludeCardIndex": -1}
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

  Uint8List encode() {
    final json = jsonEncode({
      'round': round,
      'totalRounds': totalRounds,
      'wordPickTime': wordPickTime,
      'cardCount': cardCount,
      'excludeCardIndex': excludeCardIndex,
      'ownerNames': ownerNames,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

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
/// JSON: {"word": "苹果"}
class WordPickResult {
  final String word;

  WordPickResult({required this.word});

  Uint8List encode() {
    final json = jsonEncode({'word': word});
    return Uint8List.fromList(utf8.encode(json));
  }

  static WordPickResult decode(Uint8List payload) {
    final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    return WordPickResult(word: map['word'] as String);
  }
}
