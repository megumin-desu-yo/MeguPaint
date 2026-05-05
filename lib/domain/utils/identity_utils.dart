import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class IdentityUtils {
  static const int _privateKeyByteLength = 32;

  static bool isValidHexString(String value) {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      final isDigit = c >= 48 && c <= 57;
      final isUpper = c >= 65 && c <= 70;
      final isLower = c >= 97 && c <= 102;
      if (!isDigit && !isUpper && !isLower) return false;
    }
    return true;
  }

  static Uint8List decodeHexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      throw const FormatException('hex 长度必须为偶数');
    }
    if (!isValidHexString(hex)) {
      throw const FormatException('hex 字符串包含非法字符');
    }

    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// 生成公开标识 publicId（可公开，不泄露私钥）
  /// 当前方案：SHA256("MeguPaint-public:v1" + privateKeyBytes)
  static Uint8List derivePublicIdFromPrivateKey(String privateKeyHex) {
    if (privateKeyHex.length != _privateKeyByteLength * 2) {
      throw const FormatException('私钥长度不正确');
    }

    final keyBytes = decodeHexToBytes(privateKeyHex);
    try {
      final prefixBytes = utf8.encode('MeguPaint-public:v1');
      final digest = sha256.convert([...prefixBytes, ...keyBytes]);
      return Uint8List.fromList(digest.bytes);
    } finally {
      // 尽量清理敏感数据（注意：Dart 字符串不可变，无法彻底清理）
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  /// 从 publicId 生成指纹（默认取前 8 字节 = 64bit，16 个 hex 字符）
  static String getUserFingerprintFromPublicId(
    Uint8List publicIdBytes, {
    int bytes = 8,
  }) {
    if (publicIdBytes.isEmpty) return '';
    final len = bytes.clamp(1, publicIdBytes.length);
    final sub = publicIdBytes.sublist(0, len);
    return sub
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  /// 从 publicId 的 hex 字符串生成指纹
  static String getUserFingerprintFromPublicIdHex(
    String publicIdHex, {
    int bytes = 8,
  }) {
    final pid = decodeHexToBytes(publicIdHex);
    try {
      return getUserFingerprintFromPublicId(pid, bytes: bytes);
    } finally {
      pid.fillRange(0, pid.length, 0);
    }
  }

  /// 从私钥直接获取指纹（内部会派生 publicId）
  static String getUserFingerprintFromPrivateKey(
    String privateKeyHex, {
    int bytes = 8,
  }) {
    final publicId = derivePublicIdFromPrivateKey(privateKeyHex);
    try {
      return getUserFingerprintFromPublicId(publicId, bytes: bytes);
    } finally {
      publicId.fillRange(0, publicId.length, 0);
    }
  }
}
