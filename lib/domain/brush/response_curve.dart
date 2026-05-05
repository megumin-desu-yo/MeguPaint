import 'dart:math' as math;

/// 曲线插值类型
enum CurveInterpolation {
  /// 线性插值
  linear,

  /// 缓入（慢起快收）
  easeIn,

  /// 缓出（快起慢收）
  easeOut,

  /// 缓入缓出
  easeInOut,
}

/// 曲线控制点
class CurvePoint {
  /// 输入值 (0.0 - 1.0)
  final double input;

  /// 输出值 (0.0 - 1.0)
  final double output;

  const CurvePoint({required this.input, required this.output});

  Map<String, dynamic> toMap() => {'input': input, 'output': output};

  factory CurvePoint.fromMap(Map<String, dynamic> map) => CurvePoint(
    input: (map['input'] as num).toDouble(),
    output: (map['output'] as num).toDouble(),
  );
}

/// 响应曲线：定义输入信号到输出值的映射
/// 支持多控制点和不同插值方式
class ResponseCurve {
  /// 控制点列表（按 input 升序排列）
  final List<CurvePoint> points;

  /// 插值方式
  final CurveInterpolation interpolation;

  const ResponseCurve({
    required this.points,
    this.interpolation = CurveInterpolation.linear,
  });

  /// 默认线性曲线 (0,0) -> (1,1)
  static const ResponseCurve linear = ResponseCurve(
    points: [
      CurvePoint(input: 0.0, output: 0.0),
      CurvePoint(input: 1.0, output: 1.0),
    ],
  );

  /// 默认恒定曲线（始终输出 1.0）
  static const ResponseCurve constant = ResponseCurve(
    points: [
      CurvePoint(input: 0.0, output: 1.0),
      CurvePoint(input: 1.0, output: 1.0),
    ],
  );

  /// 恒定值曲线
  factory ResponseCurve.constantValue(double value) => ResponseCurve(
    points: [
      CurvePoint(input: 0.0, output: value),
      CurvePoint(input: 1.0, output: value),
    ],
  );

  /// 反向线性曲线 (0,1) -> (1,0)
  static const ResponseCurve inverseLinear = ResponseCurve(
    points: [
      CurvePoint(input: 0.0, output: 1.0),
      CurvePoint(input: 1.0, output: 0.0),
    ],
  );

  /// 软曲线（轻压也有较大输出）
  static const ResponseCurve soft = ResponseCurve(
    points: [
      CurvePoint(input: 0.0, output: 0.0),
      CurvePoint(input: 0.3, output: 0.6),
      CurvePoint(input: 1.0, output: 1.0),
    ],
  );

  /// 硬曲线（需较大压力才有输出）
  static const ResponseCurve hard = ResponseCurve(
    points: [
      CurvePoint(input: 0.0, output: 0.0),
      CurvePoint(input: 0.6, output: 0.3),
      CurvePoint(input: 1.0, output: 1.0),
    ],
  );

  /// 强S型曲线（G笔专用：轻压极细，中段爆发，重压饱和）
  static const ResponseCurve strongS = ResponseCurve(
    points: [
      CurvePoint(input: 0.0, output: 0.0),
      CurvePoint(input: 0.15, output: 0.03),
      CurvePoint(input: 0.35, output: 0.15),
      CurvePoint(input: 0.5, output: 0.6),
      CurvePoint(input: 0.7, output: 0.9),
      CurvePoint(input: 1.0, output: 1.0),
    ],
  );

  /// 软S型曲线（真实G笔专用：起点更灵敏，过渡更柔和）
  static const ResponseCurve softS = ResponseCurve(
    points: [
      CurvePoint(input: 0.0, output: 0.0),
      CurvePoint(input: 0.1, output: 0.05),
      CurvePoint(input: 0.3, output: 0.3),
      CurvePoint(input: 0.5, output: 0.65),
      CurvePoint(input: 0.75, output: 0.92),
      CurvePoint(input: 1.0, output: 1.0),
    ],
  );

  /// 计算输出值
  double evaluate(double input) {
    if (points.isEmpty) return input;
    if (points.length == 1) return points.first.output;

    input = input.clamp(0.0, 1.0);

    // 找到输入值所在的区间
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];

      if (input >= p0.input && input <= p1.input) {
        final range = p1.input - p0.input;
        if (range <= 0) return p0.output;

        double t = (input - p0.input) / range;

        // 应用插值
        t = _applyInterpolation(t);

        return p0.output + t * (p1.output - p0.output);
      }
    }

    return points.last.output;
  }

  /// 应用插值函数
  double _applyInterpolation(double t) {
    switch (interpolation) {
      case CurveInterpolation.linear:
        return t;
      case CurveInterpolation.easeIn:
        return t * t;
      case CurveInterpolation.easeOut:
        return 1.0 - (1.0 - t) * (1.0 - t);
      case CurveInterpolation.easeInOut:
        return t < 0.5 ? 2.0 * t * t : 1.0 - math.pow(-2.0 * t + 2.0, 2) / 2.0;
    }
  }

  Map<String, dynamic> toMap() => {
    'points': points.map((p) => p.toMap()).toList(),
    'interpolation': interpolation.index,
  };

  factory ResponseCurve.fromMap(Map<String, dynamic> map) => ResponseCurve(
    points: (map['points'] as List)
        .map((p) => CurvePoint.fromMap(p as Map<String, dynamic>))
        .toList(),
    interpolation:
        CurveInterpolation.values[(map['interpolation'] as num?)?.toInt() ?? 0],
  );

  ResponseCurve copyWith({
    List<CurvePoint>? points,
    CurveInterpolation? interpolation,
  }) => ResponseCurve(
    points: points ?? this.points,
    interpolation: interpolation ?? this.interpolation,
  );
}
