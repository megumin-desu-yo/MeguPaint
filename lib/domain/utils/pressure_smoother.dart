/// 压感平滑器
/// 使用指数平滑 + 自适应因子算法
class PressureSmoother {
  double _smoothed = 0.0;
  double _lastValue = 0.0;
  bool _initialized = false;

  /// 平滑压感值
  /// [value] 原始压感值 (0.0 - 1.0)
  /// [baseAlpha] 基础平滑因子 (0.1 - 0.9)
  /// [enabled] 是否启用平滑
  double smooth(double value, double baseAlpha, bool enabled) {
    if (!enabled) {
      return value;
    }

    // 首次调用时初始化
    if (!_initialized) {
      _smoothed = value;
      _lastValue = value;
      _initialized = true;
      return value;
    }

    // 根据变化幅度动态调整平滑强度
    // 变化大时减少平滑（更跟手），变化小时增加平滑（更平滑）
    final delta = (value - _lastValue).abs();
    final adaptiveAlpha = baseAlpha * (1.0 - delta.clamp(0.0, 1.0));

    // 确保自适应因子在合理范围内
    final clampedAlpha = adaptiveAlpha.clamp(0.05, baseAlpha);

    // 指数平滑公式
    _smoothed = clampedAlpha * value + (1 - clampedAlpha) * _smoothed;
    _lastValue = value;

    return _smoothed.clamp(0.0, 1.0);
  }

  /// 重置平滑器状态（笔画结束时调用）
  void reset() {
    _smoothed = 0.0;
    _lastValue = 0.0;
    _initialized = false;
  }
}
