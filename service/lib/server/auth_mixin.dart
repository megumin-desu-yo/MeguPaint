import 'dart:io';
import 'dart:typed_data';

import '../protocol/protocol_handler.dart';
import '../room/client_session.dart';
import 'tcp_server_base.dart';

/// 认证相关功能 Mixin
/// 包含：登录、心跳、服务器信息
mixin AuthMixin on TcpServerBase {
  /// 处理登录请求
  void handleLoginRequest(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      final request = LoginRequest.decode(payload);
      final fingerprintHex = request.fingerprint
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      log('收到登录请求',
          username: request.username, ip: session.ip, action: 'LOGIN_REQUEST');

      // 验证登录
      final (isValid, errorMsg) =
          authService.verifyLogin(request.username, request.fingerprint);

      if (!isValid) {
        log('登录失败: $errorMsg',
            username: request.username, action: 'LOGIN_FAILED');
        final resp =
            LoginResponse(success: false, errorMessage: errorMsg ?? '验证失败');
        socket.add(
            ProtocolHandler.encode(MessageType.loginResponse, resp.encode()));
        return;
      }

      // 检查是否已在其他连接登录
      String? oldIp;
      for (final entry in clients.entries) {
        if (entry.value.username == request.username &&
            entry.value.fingerprintHex == fingerprintHex) {
          oldIp = entry.value.ip;
          // 踢掉旧连接
          log('踢掉旧连接',
              username: request.username, ip: oldIp, action: 'KICK_OLD');
          disconnectClient(entry.key, reason: 'KICK_OLD');
          break;
        }
      }

      // 更新会话信息
      session.isAuthenticated = true;
      session.username = request.username;
      session.fingerprintHex = fingerprintHex;

      log('登录成功',
          username: request.username,
          fingerprintHex: fingerprintHex,
          ip: session.ip,
          action: 'LOGIN_SUCCESS');

      final resp = LoginResponse(success: true);
      socket.add(
          ProtocolHandler.encode(MessageType.loginResponse, resp.encode()));
    } catch (e) {
      log('登录异常: $e', action: 'LOGIN_ERROR');
      final resp = LoginResponse(success: false, errorMessage: '登录失败: $e');
      socket.add(
          ProtocolHandler.encode(MessageType.loginResponse, resp.encode()));
    }
  }

  /// 处理心跳
  void handleHeartbeat(Socket socket, Uint8List payload) {
    final heartbeat = HeartbeatMessage.decode(payload);
    final response = ProtocolHandler.encode(
      MessageType.heartbeatResponse,
      heartbeat.encode(),
    );
    socket.add(response);
  }

  /// 处理服务器信息请求
  void handleServerInfoRequest(Socket socket) {
    final response = ServerInfoResponse(
      serverName: serverName,
      currentConnections: connectionCount,
      maxConnections: maxConnections,
      currentRooms: roomCount,
      maxRooms: maxRooms,
    );
    final message = ProtocolHandler.encode(
      MessageType.serverInfoResponse,
      response.encode(),
    );
    socket.add(message);
  }
}
