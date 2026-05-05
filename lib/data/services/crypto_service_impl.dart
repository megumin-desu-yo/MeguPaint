import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../domain/services/crypto_service.dart';

/// 加密服务实现
class CryptoServiceImpl implements CryptoService {
  /// PBKDF2 迭代次数
  static const int _pbkdf2Iterations = 100000;

  /// 密钥长度 (字节)
  static const int _keyLength = 32;

  /// PBKDF2 盐值前缀
  static const String _saltPrefix = 'MeguPaint-v1';

  @override
  String derivePrivateKey(String username, String password) {
    // 组合用户名和密码
    final combined = '$username:$password';

    // 生成盐值
    final salt = _generateSalt(username);

    // 使用 PBKDF2 派生密钥
    final key = _pbkdf2(combined, salt);

    return _bytesToHex(key);
  }

  @override
  String hashPassword(String password, String salt) {
    final bytes = _pbkdf2(password, salt);
    return _bytesToHex(bytes);
  }

  @override
  String signLayer(String privateKey, String layerId, int seed) {
    // 组合消息: layerId:seed
    final message = '$layerId:$seed';

    // 使用 HMAC-SHA256 签名
    final keyBytes = _hexToBytes(privateKey);
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(utf8.encode(message));

    return digest.toString();
  }

  @override
  bool verifyLayerSignature(
    String privateKey,
    String layerId,
    int seed,
    String signature,
  ) {
    final expectedSignature = signLayer(privateKey, layerId, seed);
    // 常量时间比较，防止时序攻击
    return _constantTimeEquals(expectedSignature, signature);
  }

  @override
  int generateSeed() {
    final random = Random.secure();
    return random.nextInt(0x7FFFFFFF); // 正整数范围
  }

  @override
  String generateUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // 设置 UUID v4 版本位
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    // 格式化为 UUID 字符串
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// 生成盐值
  String _generateSalt(String username) {
    return '$_saltPrefix:$username';
  }

  /// PBKDF2 密钥派生
  List<int> _pbkdf2(String password, String salt) {
    final passwordBytes = utf8.encode(password);
    final saltBytes = utf8.encode(salt);

    // 使用 crypto 包的 PBKDF2
    // 注意: crypto 包没有直接提供 PBKDF2，我们使用 HMAC 实现
    return _pbkdf2Impl(passwordBytes, saltBytes, _pbkdf2Iterations, _keyLength);
  }

  /// PBKDF2 实现
  List<int> _pbkdf2Impl(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    final blockCount = (keyLength / sha256.convert([]).bytes.length).ceil();

    final result = <int>[];

    for (var i = 1; i <= blockCount; i++) {
      // U1 = HMAC(password, salt || INT(i))
      var u = hmac.convert([...salt, ..._intToBytes(i)]).bytes;
      final block = List<int>.from(u);

      // U2 .. Uc = HMAC(password, U(j-1))
      for (var j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < block.length; k++) {
          block[k] ^= u[k];
        }
      }

      result.addAll(block);
    }

    return result.sublist(0, keyLength);
  }

  /// 整数转字节数组 (大端序, 4字节)
  List<int> _intToBytes(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  /// 字节数组转十六进制字符串
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 十六进制字符串转字节数组
  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// 常量时间比较 (防止时序攻击)
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;

    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
