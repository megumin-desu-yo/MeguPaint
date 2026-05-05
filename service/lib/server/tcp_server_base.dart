import 'dart:async';
import 'dart:io';

import '../auth/auth_service.dart';
import '../room/room_data.dart';
import '../room/client_session.dart';

/// TCP 服务端基类
/// 包含核心状态字段和基础方法，供 Mixin 使用
abstract class TcpServerBase {
  // ===== 配置参数 =====
  final int port;
  final String serverName;
  final int maxConnections;
  final int maxRooms;

  // ===== 核心状态 =====
  ServerSocket? serverSocket;
  final Map<Socket, ClientSession> clients = {};
  final Map<String, RoomData> rooms = {};
  bool isRunningFlag = false;

  // ===== 事件流 =====
  final StreamController<Socket> onClientConnectedController =
      StreamController<Socket>.broadcast();
  final StreamController<Socket> onClientDisconnectedController =
      StreamController<Socket>.broadcast();

  /// 认证服务（子类可访问）
  final AuthService authService;

  TcpServerBase({
    this.port = 9527,
    this.serverName = 'MeguPaint Server',
    AuthService? authService,
    this.maxConnections = 100,
    this.maxRooms = 20,
  }) : authService = authService ?? AuthService();

  /// 是否正在运行
  bool get isRunning => isRunningFlag;

  /// 当前连接数
  int get connectionCount => clients.length;

  /// 当前房间数
  int get roomCount => rooms.length;

  /// 日志方法（子类实现）
  void log(
    String message, {
    String? room,
    String? username,
    String? fingerprintHex,
    String? ip,
    String? action,
    String? content,
  });

  /// 发送错误消息（子类实现）
  void sendError(Socket socket, String errorMessage);

  /// 断开客户端连接（子类实现，需保证会同步清理房间状态）
  void disconnectClient(Socket socket, {String? reason});

  /// 广播房间成员列表（子类实现）
  void broadcastRoomMembers(String roomId);

  /// 广播房间设置（子类实现）
  void broadcastRoomSetting(String roomId);
}
