import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 身份验证服务
/// 负责验证客户端发送的用户名和数字指纹
class AuthService {
  /// 已注册的用户数据 (模拟数据库)
  /// key: "username#fingerprintHex", value: fingerprint (8字节)
  final Map<String, Uint8List> _registeredUsers = {};

  /// 注册用户
  /// [username] 用户名
  /// [privateKeyHex] 私钥 (十六进制字符串)
  void registerUser(String username, String privateKeyHex) {
    final fingerprint = _deriveFingerprint(privateKeyHex);
    final fingerprintHex = _bytesToHex(fingerprint);
    final userKey = '$username#$fingerprintHex';
    _registeredUsers[userKey] = fingerprint;
  }

  /// 验证登录请求
  /// [username] 用户名
  /// [fingerprint] 客户端发送的指纹 (8字节)
  /// 返回: (是否成功, 错误消息)
  (bool, String?) verifyLogin(String username, Uint8List fingerprint) {
    final fingerprintHex = _bytesToHex(fingerprint);
    final userKey = '$username#$fingerprintHex';

    // 检查这个特定组合是否存在
    if (!_registeredUsers.containsKey(userKey)) {
      // 检查指纹是否已被其他用户名占用 (可选，根据需求决定是否允许一个指纹多个名字)
      // 目前逻辑：允许同一个指纹使用不同的用户名注册，也允许同一个用户名被不同指纹使用

      // 自动注册新用户 (开发阶段)
      _registeredUsers[userKey] = fingerprint;
      return (true, null);
    }

    // 验证指纹 (由于 key 已经包含了指纹，这里实际上只要 key 存在即验证通过)
    return (true, null);
  }

  /// 从私钥派生指纹
  /// 与客户端 IdentityUtils.getUserFingerprintFromPrivateKey 逻辑一致
  Uint8List _deriveFingerprint(String privateKeyHex) {
    // 解码私钥
    final keyBytes = _hexToBytes(privateKeyHex);

    // 派生 publicId: SHA256("MeguPaint-public:v1" + privateKeyBytes)
    final prefix = 'MeguPaint-public:v1'.codeUnits;
    final input = Uint8List.fromList([...prefix, ...keyBytes]);
    final publicId = sha256.convert(input);

    // 取前8字节作为指纹
    return Uint8List.fromList(publicId.bytes.sublist(0, 8));
  }

  /// 十六进制字符串转字节
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// 字节转十六进制字符串
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 比较两个指纹 (已废弃，现在通过 key 匹配)
  // bool _compareFingerprints(Uint8List a, Uint8List b) {
  //   if (a.length != b.length) return false;
  //   for (var i = 0; i < a.length; i++) {
  //     if (a[i] != b[i]) return false;
  //   }
  //   return true;
  // }
}
