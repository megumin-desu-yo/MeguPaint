/// 加密服务接口
abstract class CryptoService {
  /// 派生私钥 (PBKDF2-SHA256)
  /// [username] 用户名
  /// [password] 密码
  /// 返回: 十六进制私钥字符串
  String derivePrivateKey(String username, String password);

  /// 哈希密码 (PBKDF2-SHA256)
  /// [password] 密码
  /// [salt] 盐值
  /// 返回: 十六进制哈希字符串
  String hashPassword(String password, String salt);

  /// 生成图层签名 (HMAC-SHA256)
  /// [privateKey] 私钥 (十六进制)
  /// [layerId] 图层ID
  /// [seed] 画作种子
  /// 返回: 十六进制签名字符串
  String signLayer(String privateKey, String layerId, int seed);

  /// 验证图层签名
  /// [privateKey] 私钥 (十六进制)
  /// [layerId] 图层ID
  /// [seed] 画作种子
  /// [signature] 待验证的签名
  /// 返回: 是否验证通过
  bool verifyLayerSignature(
    String privateKey,
    String layerId,
    int seed,
    String signature,
  );

  /// 生成随机种子
  int generateSeed();

  /// 生成UUID
  String generateUuid();
}
