import 'dart:io';

import 'package:megu_paint_service/tcp_server.dart';
import 'package:megu_paint_service/config/server_config.dart';
import 'package:megu_paint_service/admin_http_server.dart';

/// TCP 服务端入口
void main(List<String> args) async {
  final config = await ServerConfig.load();

  final portArg = args.isNotEmpty ? int.tryParse(args[0]) : null;
  final port = portArg ?? config.port;

  final adminPortArg = args.length >= 2 ? int.tryParse(args[1]) : null;
  final adminPort = adminPortArg ?? 9090;

  final server = TcpServer(
    port: port,
    serverName: config.serverName,
    maxConnections: config.maxConnections,
    maxRooms: config.maxRooms,
    idleSweepInterval: Duration(seconds: config.idleSweepIntervalSeconds),
    handshakeTimeout: Duration(seconds: config.handshakeTimeoutSeconds),
    authenticatedIdleTimeout: config.authenticatedIdleTimeoutSeconds > 0
        ? Duration(seconds: config.authenticatedIdleTimeoutSeconds)
        : Duration(minutes: config.authenticatedIdleTimeoutMinutes),
  );

  final admin = AdminHttpServer(server: server, port: adminPort);

  // 注册测试用户 (可选)
  // server.registerUser('test', '私钥十六进制字符串');

  // 监听事件
  server.onClientConnected.listen((socket) {
    print('[事件] 客户端连接: ${socket.remoteAddress.address}');
  });

  server.onClientDisconnected.listen((socket) {
    print('[事件] 客户端断开');
  });

  // 启动服务
  await server.start();

  await admin.start();
  print('管理后台: http://127.0.0.1:$adminPort/rooms');

  print('按 Enter 键停止服务...');
  await stdin.first;
  await admin.stop();
  await server.stop();
}
