/// 抖动/随机化设置
/// 为笔刷参数添加随机变化，增加自然感
class JitterSettings {
  /// 尺寸抖动 (0.0 - 1.0)，在基础尺寸上添加随机偏移比例
  final double sizeJitter;

  /// 角度抖动 (0.0 - 1.0)，随机旋转幅度（1.0 = 完全随机旋转 360°）
  final double angleJitter;

  /// 不透明度抖动 (0.0 - 1.0)
  final double opacityJitter;

  /// 散布 (0.0 - 5.0)，印中心偏离路径的随机范围（相对于笔刷尺寸）
  final double scatter;

  /// 圆度抖动 (0.0 - 1.0)
  final double roundnessJitter;

  /// 色相抖动 (0.0 - 1.0)，以当前色相为中心的随机偏移
  final double hueJitter;

  /// 饱和度抖动 (0.0 - 1.0)
  final double saturationJitter;

  /// 明度抖动 (0.0 - 1.0)
  final double brightnessJitter;

  const JitterSettings({
    this.sizeJitter = 0.0,
    this.angleJitter = 0.0,
    this.opacityJitter = 0.0,
    this.scatter = 0.0,
    this.roundnessJitter = 0.0,
    this.hueJitter = 0.0,
    this.saturationJitter = 0.0,
    this.brightnessJitter = 0.0,
  });

  /// 无抖动
  static const JitterSettings none = JitterSettings();

  /// 是否有任何抖动
  bool get hasJitter =>
      sizeJitter > 0 ||
      angleJitter > 0 ||
      opacityJitter > 0 ||
      scatter > 0 ||
      roundnessJitter > 0 ||
      hueJitter > 0 ||
      saturationJitter > 0 ||
      brightnessJitter > 0;

  Map<String, dynamic> toMap() => {
    'sizeJitter': sizeJitter,
    'angleJitter': angleJitter,
    'opacityJitter': opacityJitter,
    'scatter': scatter,
    'roundnessJitter': roundnessJitter,
    'hueJitter': hueJitter,
    'saturationJitter': saturationJitter,
    'brightnessJitter': brightnessJitter,
  };

  factory JitterSettings.fromMap(Map<String, dynamic> map) => JitterSettings(
    sizeJitter: (map['sizeJitter'] as num?)?.toDouble() ?? 0.0,
    angleJitter: (map['angleJitter'] as num?)?.toDouble() ?? 0.0,
    opacityJitter: (map['opacityJitter'] as num?)?.toDouble() ?? 0.0,
    scatter: (map['scatter'] as num?)?.toDouble() ?? 0.0,
    roundnessJitter: (map['roundnessJitter'] as num?)?.toDouble() ?? 0.0,
    hueJitter: (map['hueJitter'] as num?)?.toDouble() ?? 0.0,
    saturationJitter: (map['saturationJitter'] as num?)?.toDouble() ?? 0.0,
    brightnessJitter: (map['brightnessJitter'] as num?)?.toDouble() ?? 0.0,
  );

  JitterSettings copyWith({
    double? sizeJitter,
    double? angleJitter,
    double? opacityJitter,
    double? scatter,
    double? roundnessJitter,
    double? hueJitter,
    double? saturationJitter,
    double? brightnessJitter,
  }) => JitterSettings(
    sizeJitter: sizeJitter ?? this.sizeJitter,
    angleJitter: angleJitter ?? this.angleJitter,
    opacityJitter: opacityJitter ?? this.opacityJitter,
    scatter: scatter ?? this.scatter,
    roundnessJitter: roundnessJitter ?? this.roundnessJitter,
    hueJitter: hueJitter ?? this.hueJitter,
    saturationJitter: saturationJitter ?? this.saturationJitter,
    brightnessJitter: brightnessJitter ?? this.brightnessJitter,
  );
}
