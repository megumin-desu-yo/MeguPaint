import 'dart:convert';

import 'dart:io';

import 'dart:typed_data';

import '../protocol/protocol_handler.dart';

import '../room/room_data.dart';

import '../room/room_broadcaster.dart';

import '../room/client_session.dart';

import 'tcp_server_base.dart';

import 'perf_tracker.dart';

Uint8List _decodeMaybeZlib(Uint8List data, bool isCompressed) {
  if (!isCompressed) return data;

  return Uint8List.fromList(zlib.decode(data));
}

void _applyRegionDeltaToRgba({
  required Uint8List canvasRgba,
  required int canvasWidth,
  required int canvasHeight,
  required int x,
  required int y,
  required int width,
  required int height,
  required Uint8List deltaRgba,
}) {
  if (width <= 0 || height <= 0) return;

  if (x < 0 || y < 0) return;

  if (x + width > canvasWidth) return;

  if (y + height > canvasHeight) return;

  final expected = width * height * 4;

  if (deltaRgba.length != expected) return;

  final canvasStride = canvasWidth * 4;

  final rowBytes = width * 4;

  int deltaOffset = 0;

  int canvasOffset = (y * canvasStride) + (x * 4);

  for (int row = 0; row < height; row++) {
    for (int i = 0; i < rowBytes; i++) {
      canvasRgba[canvasOffset + i] ^= deltaRgba[deltaOffset + i];
    }

    deltaOffset += rowBytes;

    canvasOffset += canvasStride;
  }
}

/// 房间管理功能 Mixin

/// 包含：创建/加入/离开/列表/设置/转让/聊天

mixin RoomMixin on TcpServerBase {
  void handleCollabDelta(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.currentRoomId == null) {
      log('拒绝协同delta: 未登录或不在房间',
          username: session.username, action: 'COLLAB_DELTA_REJECT');

      return;
    }

    final roomId = session.currentRoomId!;

    final room = rooms[roomId];

    if (room == null) {
      log('拒绝协同delta: 房间不存在',
          username: session.username,
          action: 'COLLAB_DELTA_NO_ROOM',
          room: roomId);

      return;
    }

    try {
      final perf = PerfTracker.instance;

      final swFull = perf.beginFullPipeline();

      final req = CollabDeltaRequest.decode(payload);

      if (req.epoch != room.collabEpoch) {
        final sync = CollabSyncRequired(
            authoritativeEpoch: room.collabEpoch,
            authoritativeRev: room.collabRev);

        socket.add(
          ProtocolHandler.encode(MessageType.collabSyncRequired, sync.encode()),
        );

        perf.countSyncRequired();

        log('协同delta epoch不匹配，要求同步',
            username: session.username,
            action: 'COLLAB_DELTA_EPOCH_MISMATCH',
            room: roomId,
            content:
                'epoch=${req.epoch}, authoritativeEpoch=${room.collabEpoch}');

        return;
      }

      // baseRev 宽松模式：XOR delta 可交换，直接 apply 而不拒绝，避免 SyncRequired 风暴

      if (req.baseRev != room.collabRev) {
        log('协同delta版本偏差，宽松 apply',
            username: session.username,
            action: 'COLLAB_DELTA_REV_SKEW',
            room: roomId,
            content:
                'baseRev=${req.baseRev}, authoritativeRev=${room.collabRev}');
      }

      final isCompressed = (req.flags & 0x01) != 0;

      final swDecompress = perf.beginDecompress();

      final deltaRgba = _decodeMaybeZlib(req.payload, isCompressed);

      perf.endDecompress(swDecompress,
          payloadBytes: req.payload.length, roomId: roomId);

      final swApply = perf.beginApply();

      _applyRegionDeltaToRgba(
        canvasRgba: room.collabRgba,
        canvasWidth: room.canvasWidth,
        canvasHeight: room.canvasHeight,
        x: req.x,
        y: req.y,
        width: req.width,
        height: req.height,
        deltaRgba: deltaRgba,
      );

      perf.endApply(swApply, pixelCount: req.width * req.height);

      room.collabRev += 1;

      final broadcast = CollabDeltaBroadcast(
        epoch: room.collabEpoch,
        rev: room.collabRev,
        senderId: session.username ?? '',
        x: req.x,
        y: req.y,
        width: req.width,
        height: req.height,
        flags: req.flags,
        payload: req.payload,
      );

      final swBroadcast = perf.beginBroadcast();

      final broadcastMsg = broadcast.encode();

      final successCount = RoomBroadcaster.broadcast(
        room,
        MessageType.collabDeltaBroadcast,
        broadcastMsg,
      );
      final targetCount = room.memberSockets.where((s) => s != null).length;
      perf.endBroadcast(
        swBroadcast,
        broadcastBytes: broadcastMsg.length * successCount,
        targetCount: targetCount,
        errors: (targetCount - successCount).clamp(0, 1 << 30),
        roomId: roomId,
      );

      perf.endFullPipeline(swFull);

      log('广播协同delta完成',
          username: session.username,
          action: 'COLLAB_DELTA_BROADCAST',
          room: roomId,
          content:
              'rev=${room.collabRev}, sent=$successCount/${room.memberSockets.length}');
    } catch (e) {
      log('处理协同delta失败: $e',
          username: session.username,
          action: 'COLLAB_DELTA_ERROR',
          room: roomId);
    }
  }

  void handleCollabSyncRequest(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.currentRoomId == null) {
      log('拒绝协同syncRequest: 未登录或不在房间',
          username: session.username, action: 'COLLAB_SYNC_REQ_REJECT');

      return;
    }

    final roomId = session.currentRoomId!;

    final room = rooms[roomId];

    if (room == null) {
      log('拒绝协同syncRequest: 房间不存在',
          username: session.username,
          action: 'COLLAB_SYNC_REQ_NO_ROOM',
          room: roomId);

      return;
    }

    try {
      final req = CollabSyncRequest.decode(payload);

      final requesterUsername = session.username ?? req.requesterUsername;

      final requesterIdx =
          room.members.indexWhere((m) => m.username == requesterUsername);

      if (requesterIdx < 0) {
        log('拒绝协同syncRequest: 找不到请求者成员',
            username: session.username,
            action: 'COLLAB_SYNC_REQ_NO_MEMBER',
            room: roomId,
            content: requesterUsername);

        return;
      }

      final requesterFp = room.members[requesterIdx].fingerprintHex;

      // 多图层模式：发送 collabMultiLayerSnapshot

      if (room.collabLayers.isNotEmpty) {
        sendMultiLayerSnapshot(room, requesterFp);

        log('服务端响应协同syncRequest（多图层快照）',
            username: session.username,
            action: 'COLLAB_SYNC_REQ_MULTI_SNAPSHOT',
            room: roomId,
            content:
                'to=$requesterUsername, epoch=${room.collabEpoch}, layers=${room.collabLayers.length}');
      } else {
        // 兼容：旧单层模式

        final rgbaZlib = Uint8List.fromList(zlib.encode(room.collabRgba));

        final snap = CollabSnapshotFromServer(
          epoch: room.collabEpoch,
          rev: room.collabRev,
          width: room.canvasWidth,
          height: room.canvasHeight,
          flags: 0x01,
          rgbaZlib: rgbaZlib,
        );

        final ok = RoomBroadcaster.sendToMember(
          room,
          requesterFp,
          MessageType.collabSnapshotFromServer,
          snap.encode(),
        );

        log('服务端响应协同syncRequest快照',
            username: session.username,
            action: 'COLLAB_SYNC_REQ_SNAPSHOT',
            room: roomId,
            content: ok
                ? 'to=$requesterUsername, epoch=${snap.epoch}, rev=${snap.rev}, bytes=${snap.rgbaZlib.length}'
                : 'failed');
      }
    } catch (e) {
      log('处理协同syncRequest失败: $e',
          username: session.username,
          action: 'COLLAB_SYNC_REQ_ERROR',
          room: roomId);
    }
  }

  void handleCollabSnapshotFromOwner(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.currentRoomId == null) {
      log('拒绝协同snapshot: 未登录或不在房间',
          username: session.username, action: 'COLLAB_SNAP_REJECT');

      return;
    }

    final roomId = session.currentRoomId!;

    final room = rooms[roomId];

    if (room == null) {
      log('拒绝协同snapshot: 房间不存在',
          username: session.username,
          action: 'COLLAB_SNAP_NO_ROOM',
          room: roomId);

      return;
    }

    // 只允许房主发送快照

    if (session.fingerprintHex != room.ownerFingerprintHex) {
      log('拒绝协同snapshot: 非房主',
          username: session.username,
          action: 'COLLAB_SNAP_NOT_OWNER',
          room: roomId);

      return;
    }

    try {
      final snap = CollabSnapshotFromOwner.decode(payload);

      final targetIdx =
          room.members.indexWhere((m) => m.username == snap.targetUsername);

      if (targetIdx < 0) {
        log('转发协同snapshot失败: 找不到目标成员',
            username: session.username,
            action: 'COLLAB_SNAP_TARGET_NOT_FOUND',
            room: roomId,
            content: snap.targetUsername);

        return;
      }

      final targetFp = room.members[targetIdx].fingerprintHex;

      final ok = RoomBroadcaster.sendToMember(
        room,
        targetFp,
        MessageType.collabSnapshotFromOwner,
        snap.encode(),
      );

      log('转发协同snapshot给目标成员',
          username: session.username,
          action: 'COLLAB_SNAP_FORWARD',
          room: roomId,
          content: ok
              ? 'to=${snap.targetUsername}, rev=${snap.rev}, bytes=${snap.rgbaZlib.length}'
              : 'failed');
    } catch (e) {
      log('处理协同snapshot失败: $e',
          username: session.username,
          action: 'COLLAB_SNAP_ERROR',
          room: roomId);
    }
  }

  // ========== 多图层协同处理 ==========

  /// 处理图层操作请求（增删改重排）

  void handleCollabLayerOp(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.currentRoomId == null) return;

    final roomId = session.currentRoomId!;

    final room = rooms[roomId];

    if (room == null) return;

    try {
      final req = CollabLayerOpRequest.decode(payload);

      final username = session.username ?? '';

      switch (req.opType) {
        case CollabLayerOpType.add:

          // 服务端生成 layerId，创建图层追加到末尾（视觉最上层）

          final layerId = room.generateLayerId();

          final name = (req.payload['name'] as String?) ?? '$username 的图层';

          final layer = CollabLayerInfo(
            layerId: layerId,
            name: name,
            ownerId: username,
            rgba: Uint8List(room.canvasWidth * room.canvasHeight * 4),
          );

          room.collabLayers.add(layer);

          final broadcast = CollabLayerOpBroadcast(
            opType: CollabLayerOpType.add,
            payload: {
              'layerId': layerId,
              'name': name,
              'ownerId': username,
              'index': room.collabLayers.length - 1,
              'isVisible': true,
              'isLocked': false,
              'opacity': 1.0,
              'blendMode': 0,
            },
          );

          RoomBroadcaster.broadcast(
            room,
            MessageType.collabLayerOpBroadcast,
            broadcast.encode(),
          );

          log('图层新增: $layerId ($name) by $username',
              action: 'LAYER_OP_ADD', room: roomId);

          break;

        case CollabLayerOpType.remove:
          final layerId = req.payload['layerId'] as String?;

          if (layerId == null) return;

          // 至少保留一个图层

          if (room.collabLayers.length <= 1) return;

          final idx = room.collabLayers.indexWhere((l) => l.layerId == layerId);

          if (idx < 0) return;

          room.collabLayers.removeAt(idx);

          final broadcast = CollabLayerOpBroadcast(
            opType: CollabLayerOpType.remove,
            payload: {'layerId': layerId},
          );

          RoomBroadcaster.broadcast(
            room,
            MessageType.collabLayerOpBroadcast,
            broadcast.encode(),
          );

          log('图层删除: $layerId by $username',
              action: 'LAYER_OP_REMOVE', room: roomId);

          break;

        case CollabLayerOpType.rename:
          final layerId = req.payload['layerId'] as String?;

          final newName = req.payload['name'] as String?;

          if (layerId == null || newName == null) return;

          final layer = room.collabLayers
              .cast<CollabLayerInfo?>()
              .firstWhere((l) => l!.layerId == layerId, orElse: () => null);

          if (layer == null) return;

          layer.name = newName;

          final broadcast = CollabLayerOpBroadcast(
            opType: CollabLayerOpType.rename,
            payload: {'layerId': layerId, 'name': newName},
          );

          RoomBroadcaster.broadcast(
            room,
            MessageType.collabLayerOpBroadcast,
            broadcast.encode(),
          );

          log('图层重命名: $layerId -> $newName by $username',
              action: 'LAYER_OP_RENAME', room: roomId);

          break;

        case CollabLayerOpType.reorder:
          final order = (req.payload['order'] as List?)?.cast<String>();

          if (order == null) return;

          // 按 order 重排 collabLayers

          final map = {for (final l in room.collabLayers) l.layerId: l};

          final reordered = <CollabLayerInfo>[];

          for (final id in order) {
            final l = map[id];

            if (l != null) reordered.add(l);
          }

          // 如果有遗漏的图层（容错），追加到末尾

          for (final l in room.collabLayers) {
            if (!reordered.contains(l)) reordered.add(l);
          }

          room.collabLayers
            ..clear()
            ..addAll(reordered);

          final broadcast = CollabLayerOpBroadcast(
            opType: CollabLayerOpType.reorder,
            payload: {
              'order': room.collabLayers.map((l) => l.layerId).toList()
            },
          );

          RoomBroadcaster.broadcast(
            room,
            MessageType.collabLayerOpBroadcast,
            broadcast.encode(),
          );

          log('图层重排 by $username', action: 'LAYER_OP_REORDER', room: roomId);

          break;

        case CollabLayerOpType.setVisibility:
          final layerId = req.payload['layerId'] as String?;

          final isVisible = req.payload['isVisible'] as bool?;

          if (layerId == null || isVisible == null) return;

          final layer = room.collabLayers
              .cast<CollabLayerInfo?>()
              .firstWhere((l) => l!.layerId == layerId, orElse: () => null);

          if (layer == null) return;

          layer.isVisible = isVisible;

          final broadcast = CollabLayerOpBroadcast(
            opType: CollabLayerOpType.setVisibility,
            payload: {'layerId': layerId, 'isVisible': isVisible},
          );

          RoomBroadcaster.broadcast(
            room,
            MessageType.collabLayerOpBroadcast,
            broadcast.encode(),
          );

          break;

        case CollabLayerOpType.setOpacity:
          final layerId = req.payload['layerId'] as String?;

          final opacity = (req.payload['opacity'] as num?)?.toDouble();

          if (layerId == null || opacity == null) return;

          final layer = room.collabLayers
              .cast<CollabLayerInfo?>()
              .firstWhere((l) => l!.layerId == layerId, orElse: () => null);

          if (layer == null) return;

          layer.opacity = opacity.clamp(0.0, 1.0);

          final broadcast = CollabLayerOpBroadcast(
            opType: CollabLayerOpType.setOpacity,
            payload: {'layerId': layerId, 'opacity': layer.opacity},
          );

          RoomBroadcaster.broadcast(
            room,
            MessageType.collabLayerOpBroadcast,
            broadcast.encode(),
          );

          break;

        case CollabLayerOpType.setLock:
          final layerId = req.payload['layerId'] as String?;

          final isLocked = req.payload['isLocked'] as bool?;

          if (layerId == null || isLocked == null) return;

          final layer = room.collabLayers
              .cast<CollabLayerInfo?>()
              .firstWhere((l) => l!.layerId == layerId, orElse: () => null);

          if (layer == null) return;

          layer.isLocked = isLocked;

          final broadcast = CollabLayerOpBroadcast(
            opType: CollabLayerOpType.setLock,
            payload: {'layerId': layerId, 'isLocked': isLocked},
          );

          RoomBroadcaster.broadcast(
            room,
            MessageType.collabLayerOpBroadcast,
            broadcast.encode(),
          );

          break;
      }
    } catch (e) {
      log('处理图层操作失败: $e',
          username: session.username, action: 'LAYER_OP_ERROR', room: roomId);
    }
  }

  /// 处理带 layerId 的增量 delta

  void handleCollabLayerDelta(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.currentRoomId == null) return;

    final roomId = session.currentRoomId!;

    final room = rooms[roomId];

    if (room == null) return;

    try {
      final req = CollabLayerDeltaRequest.decode(payload);

      // 找到对应图层

      final layer = room.collabLayers
          .cast<CollabLayerInfo?>()
          .firstWhere((l) => l!.layerId == req.layerId, orElse: () => null);

      if (layer == null) {
        log('协同layerDelta: 图层不存在 ${req.layerId}',
            username: session.username,
            action: 'LAYER_DELTA_NO_LAYER',
            room: roomId);

        return;
      }

      // epoch 校验（全局）

      if (req.epoch != room.collabEpoch) {
        final sync = CollabSyncRequired(
            authoritativeEpoch: room.collabEpoch, authoritativeRev: layer.rev);

        socket.add(
          ProtocolHandler.encode(MessageType.collabSyncRequired, sync.encode()),
        );

        return;
      }

      // 图层所有权校验：ownerId 非空时仅允许 owner 编辑

      final sender = session.username ?? '';

      if (layer.ownerId.isNotEmpty && layer.ownerId != sender) {
        log('拒绝非owner编辑图层: layerId=${req.layerId} owner=${layer.ownerId} sender=$sender',
            username: sender, action: 'LAYER_DELTA_FORBIDDEN', room: roomId);

        return;
      }

      // 应用 delta 到该图层的 rgba

      final perf = PerfTracker.instance;

      final swFull = perf.beginFullPipeline();

      final isCompressed = (req.flags & 0x01) != 0;

      final swDecompress = perf.beginDecompress();

      final deltaRgba = _decodeMaybeZlib(req.payload, isCompressed);

      perf.endDecompress(swDecompress,
          payloadBytes: req.payload.length, roomId: roomId);

      final swApply = perf.beginApply();

      _applyRegionDeltaToRgba(
        canvasRgba: layer.rgba,
        canvasWidth: room.canvasWidth,
        canvasHeight: room.canvasHeight,
        x: req.x,
        y: req.y,
        width: req.width,
        height: req.height,
        deltaRgba: deltaRgba,
      );

      perf.endApply(swApply, pixelCount: req.width * req.height);

      layer.rev += 1;

      // 广播

      final broadcast = CollabLayerDeltaBroadcast(
        layerId: req.layerId,
        epoch: room.collabEpoch,
        rev: layer.rev,
        senderId: session.username ?? '',
        x: req.x,
        y: req.y,
        width: req.width,
        height: req.height,
        flags: req.flags,
        payload: req.payload,
      );

      final swBroadcast = perf.beginBroadcast();

      final broadcastMsg = broadcast.encode();

      final sentCount = RoomBroadcaster.broadcast(
        room,
        MessageType.collabLayerDeltaBroadcast,
        broadcastMsg,
      );
      final targetCount = room.memberSockets.where((s) => s != null).length;
      perf.endBroadcast(
        swBroadcast,
        broadcastBytes: broadcastMsg.length * sentCount,
        targetCount: targetCount,
        errors: (targetCount - sentCount).clamp(0, 1 << 30),
        roomId: roomId,
      );

      perf.endFullPipeline(swFull);
    } catch (e) {
      log('处理layerDelta失败: $e',
          username: session.username,
          action: 'LAYER_DELTA_ERROR',
          room: roomId);
    }
  }

  /// 发送多图层快照给指定成员

  void sendMultiLayerSnapshot(RoomData room, String fingerprintHex) {
    final entries = <CollabLayerSnapshotEntry>[];

    for (final layer in room.collabLayers) {
      final rgbaZlib = Uint8List.fromList(zlib.encode(layer.rgba));

      entries.add(CollabLayerSnapshotEntry(
        layerId: layer.layerId,

        name: layer.name,

        ownerId: layer.ownerId,

        isVisible: layer.isVisible,

        isLocked: layer.isLocked,

        opacity: (layer.opacity * 255).round().clamp(0, 255),

        blendMode: layer.blendMode,

        rev: layer.rev,

        rgbaFlags: 0x01, // zlib compressed

        rgbaBytes: rgbaZlib,
      ));
    }

    final snap = CollabMultiLayerSnapshot(
      epoch: room.collabEpoch,
      canvasWidth: room.canvasWidth,
      canvasHeight: room.canvasHeight,
      layers: entries,
    );

    RoomBroadcaster.sendToMember(
      room,
      fingerprintHex,
      MessageType.collabMultiLayerSnapshot,
      snap.encode(),
    );
  }

  /// 处理创建房间

  void handleCreateRoom(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated) {
      final resp = CreateRoomResponse(success: false, errorMessage: '请先登录');

      socket.add(ProtocolHandler.encode(
          MessageType.createRoomResponse, resp.encode()));

      return;
    }

    try {
      final request = CreateRoomRequest.decode(payload);

      final roomId = '${session.username}_${session.fingerprintHex}';

      if (rooms.containsKey(roomId)) {
        final resp =
            CreateRoomResponse(success: false, errorMessage: '您已创建过房间');

        socket.add(ProtocolHandler.encode(
            MessageType.createRoomResponse, resp.encode()));

        return;
      }

      if (rooms.length >= maxRooms) {
        final resp = CreateRoomResponse(
            success: false, errorMessage: '服务器房间数已达上限($maxRooms)');

        socket.add(ProtocolHandler.encode(
            MessageType.createRoomResponse, resp.encode()));

        return;
      }

      final room = RoomData(
        roomId: roomId,
        roomName: request.roomName,
        roomType: request.roomType,
        maxPlayers: request.maxPlayers,
        creatorUsername: session.username!,
        creatorFingerprintHex: session.fingerprintHex!,
        ownerUsername: session.username!,
        ownerFingerprintHex: session.fingerprintHex!,
      );

      room.memberSockets.add(socket);

      room.members.add(RoomMember(
        username: session.username!,
        fingerprintHex: session.fingerprintHex!,
        isOnline: true,
      ));

      session.currentRoomId = roomId;

      rooms[roomId] = room;

      // 协同房间：初始化公共背景图层

      if (room.roomType.code == 0x02) {
        final initLayerId = room.generateLayerId();

        room.collabLayers.add(CollabLayerInfo(
          layerId: initLayerId,

          name: '${session.username} 的图层',

          ownerId: session.username!, // 房主署名图层，仅房主可编辑

          rgba: Uint8List(room.canvasWidth * room.canvasHeight * 4),
        ));
      }

      log('创建房间: $roomId (${request.roomName})',
          username: session.username,
          fingerprintHex: session.fingerprintHex,
          ip: session.ip);

      final resp = CreateRoomResponse(success: true, roomId: roomId);

      socket.add(ProtocolHandler.encode(
          MessageType.createRoomResponse, resp.encode()));

      // 立即下发房间设置（包含画布尺寸），避免客户端未收到设置导致画布尺寸为0

      try {
        final setting = RoomSettingUpdate(
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

        socket.add(ProtocolHandler.encode(
            MessageType.roomSettingUpdate, setting.encode()));
      } catch (_) {}

      broadcastRoomMembers(roomId);
    } catch (e) {
      final resp = CreateRoomResponse(success: false, errorMessage: '创建失败: $e');

      socket.add(ProtocolHandler.encode(
          MessageType.createRoomResponse, resp.encode()));
    }
  }

  /// 处理房间列表请求

  void handleRoomListRequest(Socket socket) {
    final roomInfos = rooms.values
        .map((r) => RoomInfo(
              roomId: r.roomId,
              roomName: r.roomName,
              roomType: r.roomType,
              currentPlayers: r.onlineCount,
              maxPlayers: r.maxPlayers,
              ownerName: r.ownerUsername,
              rounds: r.rounds,
              roundTime: r.roundTime,
              lexiconKey: r.lexiconKey,
              isGameActive: r.gamePhase != GamePhase.idle,
            ))
        .toList();

    final resp = RoomListResponse(rooms: roomInfos);

    socket.add(
        ProtocolHandler.encode(MessageType.roomListResponse, resp.encode()));
  }

  /// 处理加入房间

  void handleJoinRoom(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated) {
      final resp = JoinRoomResponse(success: false, errorMessage: '请先登录');

      socket.add(
          ProtocolHandler.encode(MessageType.joinRoomResponse, resp.encode()));

      return;
    }

    try {
      final request = JoinRoomRequest.decode(payload);

      final room = rooms[request.roomId];

      if (room == null) {
        final resp = JoinRoomResponse(success: false, errorMessage: '房间不存在');

        socket.add(ProtocolHandler.encode(
            MessageType.joinRoomResponse, resp.encode()));

        return;
      }

      if (room.onlineCount >= room.maxPlayers) {
        final resp = JoinRoomResponse(success: false, errorMessage: '房间已满');

        socket.add(ProtocolHandler.encode(
            MessageType.joinRoomResponse, resp.encode()));

        return;
      }

      final fp = session.fingerprintHex!;

      final existingIdx =
          room.members.indexWhere((m) => m.fingerprintHex == fp);

      if (existingIdx >= 0) {
        if (!room.members[existingIdx].isOnline) {
          // 重连

          room.members[existingIdx].isOnline = true;

          if (existingIdx < room.memberSockets.length) {
            room.memberSockets[existingIdx] = socket;
          } else {
            while (room.memberSockets.length < existingIdx) {
              room.memberSockets.add(null);
            }

            room.memberSockets.add(socket);
          }

          session.currentRoomId = room.roomId;

          final resp = JoinRoomResponse(success: true, roomId: room.roomId);

          socket.add(ProtocolHandler.encode(
              MessageType.joinRoomResponse, resp.encode()));

          // 立即下发房间设置（包含画布尺寸）

          try {
            final setting = RoomSettingUpdate(
              roomId: room.roomId,
              roomName: room.roomName,
              roomTypeCode: room.roomType.code,
              maxPlayers: room.maxPlayers,
              rounds: room.rounds,
              roundTime: room.roundTime,
              lexiconKey: room.lexiconKey,
              canvasWidth: room.canvasWidth,
              canvasHeight: room.canvasHeight,
            );

            socket.add(ProtocolHandler.encode(
                MessageType.roomSettingUpdate, setting.encode()));
          } catch (_) {}

          broadcastRoomMembers(room.roomId);

          syncStateAfterRebind(room, socket, session);

          return;
        }

        final resp = JoinRoomResponse(success: false, errorMessage: '您已在该房间中');

        socket.add(ProtocolHandler.encode(
            MessageType.joinRoomResponse, resp.encode()));

        return;
      }

      if (room.gamePhase != GamePhase.idle) {
        final resp =
            JoinRoomResponse(success: false, errorMessage: '游戏进行中，无法加入');

        socket.add(ProtocolHandler.encode(
            MessageType.joinRoomResponse, resp.encode()));

        return;
      }

      if (session.currentRoomId != null &&
          session.currentRoomId != request.roomId) {
        removeFromRoom(socket, session);
      }

      room.memberSockets.add(socket);

      room.members.add(RoomMember(
        username: session.username!,
        fingerprintHex: session.fingerprintHex!,
        isOnline: true,
      ));

      session.currentRoomId = request.roomId;

      log('加入房间: ${request.roomId}',
          username: session.username,
          fingerprintHex: session.fingerprintHex,
          ip: session.ip);

      final resp = JoinRoomResponse(success: true, roomId: request.roomId);

      socket.add(
          ProtocolHandler.encode(MessageType.joinRoomResponse, resp.encode()));

      // 立即下发房间设置（包含画布尺寸）

      try {
        final setting = RoomSettingUpdate(
          roomId: room.roomId,
          roomName: room.roomName,
          roomTypeCode: room.roomType.code,
          maxPlayers: room.maxPlayers,
          rounds: room.rounds,
          roundTime: room.roundTime,
          lexiconKey: room.lexiconKey,
          canvasWidth: room.canvasWidth,
          canvasHeight: room.canvasHeight,
        );

        socket.add(ProtocolHandler.encode(
            MessageType.roomSettingUpdate, setting.encode()));
      } catch (_) {}

      broadcastRoomMembers(request.roomId);
    } catch (e) {
      final resp = JoinRoomResponse(success: false, errorMessage: '加入失败: $e');

      socket.add(
          ProtocolHandler.encode(MessageType.joinRoomResponse, resp.encode()));
    }
  }

  /// 处理离开房间

  void handleLeaveRoom(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      removeFromRoom(socket, session);

      final resp = LeaveRoomResponse(success: true);

      socket.add(
          ProtocolHandler.encode(MessageType.leaveRoomResponse, resp.encode()));
    } catch (e) {
      final resp = LeaveRoomResponse(success: false);

      socket.add(
          ProtocolHandler.encode(MessageType.leaveRoomResponse, resp.encode()));
    }
  }

  /// 处理查询房间成员请求

  void handleRoomMemberRequest(Socket socket, Uint8List payload) {
    try {
      final request = RoomMemberRequest.decode(payload);

      broadcastRoomMembers(request.roomId);
    } catch (e) {
      log('处理房间成员请求失败: $e');
    }
  }

  /// 处理修改房间设置请求

  void handleUpdateRoomRequest(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.currentRoomId == null) {
      final resp = UpdateRoomResponse(success: false, errorMessage: '未登录或不在房间');

      socket.add(ProtocolHandler.encode(
          MessageType.updateRoomResponse, resp.encode()));

      return;
    }

    try {
      final request = UpdateRoomRequest.decode(payload);

      final room = rooms[session.currentRoomId];

      if (room == null) {
        final resp = UpdateRoomResponse(success: false, errorMessage: '房间不存在');

        socket.add(ProtocolHandler.encode(
            MessageType.updateRoomResponse, resp.encode()));

        return;
      }

      if (room.ownerUsername != session.username ||
          room.ownerFingerprintHex != session.fingerprintHex) {
        final resp =
            UpdateRoomResponse(success: false, errorMessage: '只有房主可以修改设置');

        socket.add(ProtocolHandler.encode(
            MessageType.updateRoomResponse, resp.encode()));

        return;
      }

      final oldCanvasWidth = room.canvasWidth;

      final oldCanvasHeight = room.canvasHeight;

      final sizeChanged = oldCanvasWidth != request.canvasWidth ||
          oldCanvasHeight != request.canvasHeight;

      room.roomName = request.roomName;

      room.maxPlayers = request.maxPlayers;

      room.rounds = request.rounds;

      room.roundTime = request.roundTime;

      room.lexiconKey = request.lexiconKey;

      if (sizeChanged) {
        final newCanvasWidth = request.canvasWidth;

        final newCanvasHeight = request.canvasHeight;

        final oldRgba = room.collabRgba;

        final newRgba = Uint8List(newCanvasWidth * newCanvasHeight * 4);

        final copyWidth =
            oldCanvasWidth < newCanvasWidth ? oldCanvasWidth : newCanvasWidth;

        final copyHeight = oldCanvasHeight < newCanvasHeight
            ? oldCanvasHeight
            : newCanvasHeight;

        final rowBytes = copyWidth * 4;

        for (int y = 0; y < copyHeight; y++) {
          final oldStart = (y * oldCanvasWidth) * 4;

          final newStart = (y * newCanvasWidth) * 4;

          newRgba.setRange(
            newStart,
            newStart + rowBytes,
            oldRgba,
            oldStart,
          );
        }

        room.canvasWidth = newCanvasWidth;

        room.canvasHeight = newCanvasHeight;

        room.collabRgba = newRgba;

        room.collabEpoch += 1;

        room.collabRev = 0;

        // 协同多图层：同步 resize 每个图层的 rgba（拷贝交集区域），并重置每层 rev

        if (room.collabLayers.isNotEmpty) {
          for (final layer in room.collabLayers) {
            final oldLayerRgba = layer.rgba;

            final newLayerRgba =
                Uint8List(newCanvasWidth * newCanvasHeight * 4);

            if (oldLayerRgba.length == oldCanvasWidth * oldCanvasHeight * 4) {
              for (int y = 0; y < copyHeight; y++) {
                final oldStart = (y * oldCanvasWidth) * 4;

                final newStart = (y * newCanvasWidth) * 4;

                newLayerRgba.setRange(
                  newStart,
                  newStart + rowBytes,
                  oldLayerRgba,
                  oldStart,
                );
              }
            }

            layer.rgba = newLayerRgba;

            layer.rev = 0;
          }
        }
      } else {
        room.canvasWidth = request.canvasWidth;

        room.canvasHeight = request.canvasHeight;
      }

      log('修改房间设置: ${session.currentRoomId}',
          username: session.username,
          fingerprintHex: session.fingerprintHex,
          action: 'UPDATE_ROOM');

      final resp = UpdateRoomResponse(success: true);

      socket.add(ProtocolHandler.encode(
          MessageType.updateRoomResponse, resp.encode()));

      broadcastRoomSetting(session.currentRoomId!);

      // 协同房间变更画布尺寸后：主动广播一次多图层快照，避免客户端等待/漏发 syncRequest

      if (sizeChanged &&
          room.roomType.code == 0x02 &&
          room.collabLayers.isNotEmpty) {
        for (final m in room.members) {
          sendMultiLayerSnapshot(room, m.fingerprintHex);
        }
      }
    } catch (e) {
      final resp = UpdateRoomResponse(success: false, errorMessage: '修改失败: $e');

      socket.add(ProtocolHandler.encode(
          MessageType.updateRoomResponse, resp.encode()));
    }
  }

  /// 处理转让房间请求

  void handleTransferRoomRequest(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.currentRoomId == null) {
      final resp =
          TransferRoomResponse(success: false, errorMessage: '未登录或不在房间');

      socket.add(ProtocolHandler.encode(
          MessageType.transferRoomResponse, resp.encode()));

      return;
    }

    try {
      final request = TransferRoomRequest.decode(payload);

      final room = rooms[session.currentRoomId];

      if (room == null) {
        final resp =
            TransferRoomResponse(success: false, errorMessage: '房间不存在');

        socket.add(ProtocolHandler.encode(
            MessageType.transferRoomResponse, resp.encode()));

        return;
      }

      // 协同房间：不允许转让房主

      if (room.roomType.code == 0x02) {
        final resp =
            TransferRoomResponse(success: false, errorMessage: '协同房间不允许转让房主');

        socket.add(ProtocolHandler.encode(
            MessageType.transferRoomResponse, resp.encode()));

        return;
      }

      if (room.ownerUsername != session.username ||
          room.ownerFingerprintHex != session.fingerprintHex) {
        final resp =
            TransferRoomResponse(success: false, errorMessage: '只有房主可以转让房间');

        socket.add(ProtocolHandler.encode(
            MessageType.transferRoomResponse, resp.encode()));

        return;
      }

      final newOwnerIndex = room.members.indexWhere(
        (m) =>
            m.username == request.newOwnerUsername &&
            m.fingerprintHex == request.newOwnerFingerprintHex,
      );

      if (newOwnerIndex < 0) {
        final resp =
            TransferRoomResponse(success: false, errorMessage: '该用户不在房间内');

        socket.add(ProtocolHandler.encode(
            MessageType.transferRoomResponse, resp.encode()));

        return;
      }

      if (request.newOwnerUsername == session.username &&
          request.newOwnerFingerprintHex == session.fingerprintHex) {
        final resp =
            TransferRoomResponse(success: false, errorMessage: '不能转让给自己');

        socket.add(ProtocolHandler.encode(
            MessageType.transferRoomResponse, resp.encode()));

        return;
      }

      final oldRoomId = room.roomId;

      final newOwner = room.members[newOwnerIndex];

      room.ownerUsername = newOwner.username;

      room.ownerFingerprintHex = newOwner.fingerprintHex;

      log('主动转让房间: $oldRoomId, 新房主: ${newOwner.username}',
          username: session.username,
          fingerprintHex: session.fingerprintHex,
          action: 'TRANSFER_ROOM');

      final resp = TransferRoomResponse(success: true);

      socket.add(ProtocolHandler.encode(
          MessageType.transferRoomResponse, resp.encode()));

      final transfer = RoomOwnerTransfer(
        oldRoomId: oldRoomId,
        newRoomId: oldRoomId,
        newOwnerUsername: newOwner.username,
        newOwnerFingerprintHex: newOwner.fingerprintHex,
      );

      final msg = ProtocolHandler.encode(
        MessageType.roomOwnerTransfer,
        transfer.encode(),
      );

      for (final e in clients.entries) {
        final s = e.key;

        final sess = e.value;

        if (!sess.isAuthenticated) continue;

        try {
          s.add(msg);
        } catch (_) {}
      }

      broadcastRoomMembers(oldRoomId);
    } catch (e) {
      final resp =
          TransferRoomResponse(success: false, errorMessage: '转让失败: $e');

      socket.add(ProtocolHandler.encode(
          MessageType.transferRoomResponse, resp.encode()));
    }
  }

  /// 处理聊天消息

  void handleChatMessage(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.currentRoomId == null) {
      log('拒绝聊天消息: 未登录或不在房间',
          username: session.username, action: 'CHAT_REJECT');

      return;
    }

    try {
      final incoming = ChatMessage.decode(payload);

      final roomId = session.currentRoomId!;

      final username = session.username!;

      log('收到聊天消息',
          username: username,
          fingerprintHex: session.fingerprintHex,
          ip: session.ip,
          action: 'CHAT_RECEIVE',
          room: roomId,
          content: incoming.content);

      final broadcastMsg = ChatMessage(
        roomId: roomId,
        sender: username,
        content: incoming.content,
      );

      final room = rooms[roomId];

      if (room != null) {
        final successCount = RoomBroadcaster.broadcast(
          room,
          MessageType.chatMessage,
          broadcastMsg.encode(),
        );

        log('广播聊天消息完成',
            username: username,
            action: 'CHAT_BROADCAST',
            room: roomId,
            content: '已发送至 $successCount/${room.memberSockets.length} 个成员');
      } else {
        log('找不到房间，无法广播',
            username: username, action: 'CHAT_ROOM_NOT_FOUND', room: roomId);
      }
    } catch (e) {
      log('处理聊天消息失败: $e', username: session.username, action: 'CHAT_ERROR');
    }
  }

  /// 将用户从当前房间移除

  void removeFromRoom(Socket socket, ClientSession session) {
    final roomId = session.currentRoomId;

    if (roomId == null) return;

    final room = rooms[roomId];

    if (room == null) return;

    if (room.gamePhase != GamePhase.idle) {
      final memberIdx = room.members
          .indexWhere((m) => m.fingerprintHex == session.fingerprintHex);

      if (memberIdx >= 0) {
        room.members[memberIdx].isOnline = false;

        if (memberIdx < room.memberSockets.length) {
          room.memberSockets[memberIdx] = null;
        }

        log('成员离线占位',
            username: session.username,
            fingerprintHex: session.fingerprintHex,
            room: roomId,
            action: 'MEMBER_OFFLINE');
      }

      session.currentRoomId = null;

      broadcastRoomMembers(roomId);

      return;
    }

    final memberIdx = room.members
        .indexWhere((m) => m.fingerprintHex == session.fingerprintHex);

    if (memberIdx >= 0) {
      room.members.removeAt(memberIdx);

      if (memberIdx < room.memberSockets.length) {
        room.memberSockets.removeAt(memberIdx);
      }
    }

    session.currentRoomId = null;

    log('离开房间: $roomId',
        username: session.username,
        fingerprintHex: session.fingerprintHex,
        action: 'LEAVE_ROOM');

    broadcastRoomMembers(roomId);

    if (room.members.isEmpty) {
      rooms.remove(roomId);

      log('房间已清空并移除: $roomId', action: 'ROOM_REMOVED');
    } else if (room.ownerUsername == session.username &&
        room.ownerFingerprintHex == session.fingerprintHex) {
      // 协同房间：房主离线不自动转让（保持 owner 信息，用于列表标注离线）

      if (room.roomType.code != 0x02) {
        _transferOwnerToFirstOnline(room);
      }
    }
  }

  /// 将房主转让给第一个在线成员

  void _transferOwnerToFirstOnline(RoomData room) {
    final firstOnline = room.members.firstWhere(
      (m) => m.isOnline,
      orElse: () => room.members.first,
    );

    room.ownerUsername = firstOnline.username;

    room.ownerFingerprintHex = firstOnline.fingerprintHex;

    log('房主离线，自动转让给 ${firstOnline.username}',
        room: room.roomId, action: 'AUTO_TRANSFER');

    final transfer = RoomOwnerTransfer(
      oldRoomId: room.roomId,
      newRoomId: room.roomId,
      newOwnerUsername: firstOnline.username,
      newOwnerFingerprintHex: firstOnline.fingerprintHex,
    );

    final msg = ProtocolHandler.encode(
      MessageType.roomOwnerTransfer,
      transfer.encode(),
    );

    for (final e in clients.entries) {
      final s = e.key;

      final sess = e.value;

      if (!sess.isAuthenticated) continue;

      try {
        s.add(msg);
      } catch (_) {}
    }

    broadcastRoomMembers(room.roomId);
  }

  /// 重连后同步状态（子类可重写）

  void syncStateAfterRebind(
    RoomData room,
    Socket socket,
    ClientSession session,
  ) {
    final fp = session.fingerprintHex;

    if (fp == null) return;

    // 补发词库

    if (room.lexiconJson != null && room.lexiconJson!.isNotEmpty) {
      try {
        socket.add(ProtocolHandler.encode(MessageType.lexiconData,
            Uint8List.fromList(utf8.encode(room.lexiconJson!))));
      } catch (_) {}
    }
  }

  /// 处理断线重连

  void handleReconnectRoom(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    if (!session.isAuthenticated || session.fingerprintHex == null) {
      final resp = ReconnectRoomResponse(
        success: false,
        roomId: '',
        errorMessage: '请先登录',
      );

      socket.add(ProtocolHandler.encode(
          MessageType.reconnectRoomResponse, resp.encode()));

      return;
    }

    try {
      final request = ReconnectRoomRequest.decode(payload);

      final room = rooms[request.roomId];

      if (room == null) {
        final resp = ReconnectRoomResponse(
          success: false,
          roomId: request.roomId,
          errorMessage: '房间不存在',
        );

        socket.add(ProtocolHandler.encode(
            MessageType.reconnectRoomResponse, resp.encode()));

        return;
      }

      final fp = session.fingerprintHex!;

      final memberIdx = room.members.indexWhere((m) => m.fingerprintHex == fp);

      if (memberIdx < 0) {
        final resp = ReconnectRoomResponse(
          success: false,
          roomId: request.roomId,
          errorMessage: '您不是该对局成员，无法重连',
        );

        socket.add(ProtocolHandler.encode(
            MessageType.reconnectRoomResponse, resp.encode()));

        return;
      }

      // 如果该用户之前在其他房间，先尝试离开

      if (session.currentRoomId != null &&
          session.currentRoomId != room.roomId) {
        removeFromRoom(socket, session);
      }

      // 重新绑定 socket 到原索引，并标记在线

      room.members[memberIdx].isOnline = true;

      if (memberIdx < room.memberSockets.length) {
        room.memberSockets[memberIdx] = socket;
      } else {
        while (room.memberSockets.length < memberIdx) {
          room.memberSockets.add(null);
        }

        room.memberSockets.add(socket);
      }

      session.currentRoomId = room.roomId;

      log('断线重连成功: ${room.roomId}',
          username: session.username,
          fingerprintHex: session.fingerprintHex,
          ip: session.ip,
          action: 'RECONNECT');

      final resp = ReconnectRoomResponse(success: true, roomId: room.roomId);

      socket.add(ProtocolHandler.encode(
          MessageType.reconnectRoomResponse, resp.encode()));

      broadcastRoomMembers(room.roomId);

      syncStateAfterRebind(room, socket, session);
    } catch (e) {
      final resp = ReconnectRoomResponse(
        success: false,
        roomId: '',
        errorMessage: '重连失败: $e',
      );

      socket.add(ProtocolHandler.encode(
          MessageType.reconnectRoomResponse, resp.encode()));
    }
  }
}
