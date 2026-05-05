import 'dart:typed_data';

import '../protocol/protocol_handler.dart';
import 'room_data.dart';

/// 房间广播工具类
/// 统一管理房间内的消息广播逻辑，减少重复代码
class RoomBroadcaster {
  /// 向房间所有在线成员广播消息
  ///
  /// [room] 房间数据
  /// [type] 消息类型
  /// [payload] 消息负载
  /// 返回成功发送的成员数量
  static int broadcast(RoomData room, MessageType type, Uint8List payload) {
    final msg = ProtocolHandler.encode(type, payload);
    int successCount = 0;

    for (final s in room.memberSockets) {
      if (s == null) continue;
      try {
        s.add(msg);
        successCount++;
      } catch (_) {
        // 忽略发送失败的 socket
      }
    }

    return successCount;
  }

  /// 向房间内特定成员发送消息（通过 fingerprintHex 查找）
  ///
  /// [room] 房间数据
  /// [fingerprintHex] 目标成员的指纹
  /// [type] 消息类型
  /// [payload] 消息负载
  /// 返回是否成功发送
  static bool sendToMember(
    RoomData room,
    String fingerprintHex,
    MessageType type,
    Uint8List payload,
  ) {
    final memberIdx = room.members.indexWhere(
      (m) => m.fingerprintHex == fingerprintHex,
    );
    if (memberIdx < 0 || memberIdx >= room.memberSockets.length) {
      return false;
    }

    final socket = room.memberSockets[memberIdx];
    if (socket == null) {
      return false;
    }

    try {
      final msg = ProtocolHandler.encode(type, payload);
      socket.add(msg);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 向房间内特定成员发送消息（通过 socket 索引）
  ///
  /// [room] 房间数据
  /// [memberIdx] 成员索引
  /// [type] 消息类型
  /// [payload] 消息负载
  /// 返回是否成功发送
  static bool sendToMemberByIndex(
    RoomData room,
    int memberIdx,
    MessageType type,
    Uint8List payload,
  ) {
    if (memberIdx < 0 || memberIdx >= room.memberSockets.length) {
      return false;
    }

    final socket = room.memberSockets[memberIdx];
    if (socket == null) {
      return false;
    }

    try {
      final msg = ProtocolHandler.encode(type, payload);
      socket.add(msg);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 向房间内多个成员广播消息
  ///
  /// [room] 房间数据
  /// [fingerprintHexList] 目标成员指纹列表
  /// [type] 消息类型
  /// [payload] 消息负载
  /// 返回成功发送的成员数量
  static int broadcastToMany(
    RoomData room,
    List<String> fingerprintHexList,
    MessageType type,
    Uint8List payload,
  ) {
    final msg = ProtocolHandler.encode(type, payload);
    int successCount = 0;

    for (final fp in fingerprintHexList) {
      final memberIdx = room.members.indexWhere(
        (m) => m.fingerprintHex == fp,
      );
      if (memberIdx < 0 || memberIdx >= room.memberSockets.length) {
        continue;
      }

      final socket = room.memberSockets[memberIdx];
      if (socket == null) {
        continue;
      }

      try {
        socket.add(msg);
        successCount++;
      } catch (_) {
        // 忽略发送失败的 socket
      }
    }

    return successCount;
  }

  /// 向房间内所有成员广播消息（排除特定成员）
  ///
  /// [room] 房间数据
  /// [excludeFingerprintHex] 要排除的成员指纹
  /// [type] 消息类型
  /// [payload] 消息负载
  /// 返回成功发送的成员数量
  static int broadcastExclude(
    RoomData room,
    String excludeFingerprintHex,
    MessageType type,
    Uint8List payload,
  ) {
    final msg = ProtocolHandler.encode(type, payload);
    int successCount = 0;

    for (int i = 0; i < room.memberSockets.length; i++) {
      final s = room.memberSockets[i];
      if (s == null) continue;

      // 检查是否需要排除
      if (i < room.members.length &&
          room.members[i].fingerprintHex == excludeFingerprintHex) {
        continue;
      }

      try {
        s.add(msg);
        successCount++;
      } catch (_) {
        // 忽略发送失败的 socket
      }
    }

    return successCount;
  }
}
