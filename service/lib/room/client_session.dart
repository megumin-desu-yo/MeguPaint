/// 客户端会话
class ClientSession {
  final List<int> buffer = [];
  bool isAuthenticated = false;
  String? username;
  String? fingerprintHex;
  String? ip;
  String? currentRoomId;

  DateTime connectedAt = DateTime.now();
  DateTime lastActiveAt = DateTime.now();
}
