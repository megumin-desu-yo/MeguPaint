import 'dart:convert';
import 'dart:io';

class ServerConfig {
  final String serverName;
  final int port;
  final int maxConnections; // 最大连接数
  final int maxRooms; // 最大房间数

  final int idleSweepIntervalSeconds;
  final int handshakeTimeoutSeconds;
  final int authenticatedIdleTimeoutSeconds;
  final int authenticatedIdleTimeoutMinutes;

  const ServerConfig({
    required this.serverName,
    required this.port,
    this.maxConnections = 100,
    this.maxRooms = 20,
    this.idleSweepIntervalSeconds = 10,
    this.handshakeTimeoutSeconds = 30,
    this.authenticatedIdleTimeoutSeconds = 0,
    this.authenticatedIdleTimeoutMinutes = 90,
  });

  static Future<ServerConfig> load({String? path}) async {
    try {
      final candidates = <String>[
        if (path != null && path.trim().isNotEmpty) path.trim(),
        'config/server_config.json',
        '../config/server_config.json',
        '../../config/server_config.json',
      ];

      File? file;
      for (final p in candidates) {
        final f = File(p);
        if (await f.exists()) {
          file = f;
          break;
        }
      }

      if (file == null) {
        return const ServerConfig(
          serverName: 'MeguPaint Server',
          port: 9527,
          maxConnections: 100,
          maxRooms: 20,
          idleSweepIntervalSeconds: 10,
          handshakeTimeoutSeconds: 30,
          authenticatedIdleTimeoutSeconds: 0,
          authenticatedIdleTimeoutMinutes: 90,
        );
      }

      final content = await file.readAsString();
      final jsonMap = json.decode(content) as Map<String, dynamic>;
      final name = (jsonMap['serverName'] as String?)?.trim();
      final port = jsonMap['port'] as int? ?? 9527;
      final maxConnections = jsonMap['maxConnections'] as int? ?? 100;
      final maxRooms = jsonMap['maxRooms'] as int? ?? 20;

      final idleSweepIntervalSeconds =
          jsonMap['idleSweepIntervalSeconds'] as int? ?? 10;
      final handshakeTimeoutSeconds =
          jsonMap['handshakeTimeoutSeconds'] as int? ?? 30;
      final authenticatedIdleTimeoutSeconds =
          jsonMap['authenticatedIdleTimeoutSeconds'] as int? ?? 0;
      final authenticatedIdleTimeoutMinutes =
          jsonMap['authenticatedIdleTimeoutMinutes'] as int? ?? 90;
      return ServerConfig(
        serverName: (name == null || name.isEmpty) ? 'MeguPaint Server' : name,
        port: port,
        maxConnections: maxConnections,
        maxRooms: maxRooms,
        idleSweepIntervalSeconds: idleSweepIntervalSeconds,
        handshakeTimeoutSeconds: handshakeTimeoutSeconds,
        authenticatedIdleTimeoutSeconds: authenticatedIdleTimeoutSeconds,
        authenticatedIdleTimeoutMinutes: authenticatedIdleTimeoutMinutes,
      );
    } catch (_) {
      return const ServerConfig(
        serverName: 'MeguPaint Server',
        port: 9527,
        maxConnections: 100,
        maxRooms: 20,
        idleSweepIntervalSeconds: 10,
        handshakeTimeoutSeconds: 30,
        authenticatedIdleTimeoutSeconds: 0,
        authenticatedIdleTimeoutMinutes: 90,
      );
    }
  }
}
