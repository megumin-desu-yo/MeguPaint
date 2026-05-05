import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Color;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 原生压感数据
class NativePressureData {
  /// 事件类型: "down", "move", "up"
  final String event;

  /// 指针 ID
  final int pointerId;

  /// 客户端坐标 X
  final double x;

  /// 客户端坐标 Y
  final double y;

  /// 归一化压感值 (0.0 - 1.0)
  final double pressure;

  /// X 轴倾斜角度
  final double tiltX;

  /// Y 轴倾斜角度
  final double tiltY;

  /// 是否为数位笔
  final bool isPen;

  /// 是否有压感数据
  final bool hasPressure;

  /// 原始指针类型 (Win32 POINTER_INPUT_TYPE)
  final int pointerType;

  const NativePressureData({
    required this.event,
    required this.pointerId,
    required this.x,
    required this.y,
    required this.pressure,
    required this.tiltX,
    required this.tiltY,
    required this.isPen,
    required this.hasPressure,
    required this.pointerType,
  });

  factory NativePressureData.fromMap(Map<Object?, Object?> map) {
    return NativePressureData(
      event: map['event'] as String? ?? '',
      pointerId: map['pointerId'] as int? ?? 0,
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      pressure: (map['pressure'] as num?)?.toDouble() ?? 0.0,
      tiltX: (map['tiltX'] as num?)?.toDouble() ?? 0.0,
      tiltY: (map['tiltY'] as num?)?.toDouble() ?? 0.0,
      isPen: map['isPen'] as bool? ?? false,
      hasPressure: map['hasPressure'] as bool? ?? false,
      pointerType: map['pointerType'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'NativePressure(event=$event, pressure=${pressure.toStringAsFixed(3)}, '
      'isPen=$isPen, hasPressure=$hasPressure, pos=($x, $y))';
}

/// 原生压感服务
/// 通过 EventChannel 接收 C++ 层的 WM_POINTER 压感数据
class NativePressureService {
  static const _eventChannel = EventChannel('com.megupaint/pressure');
  static const _methodChannel = MethodChannel('com.megupaint/pressure_method');

  /// 单例
  static final NativePressureService instance = NativePressureService._();
  NativePressureService._();

  /// 压感数据流
  Stream<NativePressureData>? _pressureStream;

  /// 最近的压感数据（按 pointerId 缓存）
  final Map<int, NativePressureData> _latestData = {};

  /// 全局最新压感值
  double _latestPressure = 0.0;

  /// 是否检测到数位笔
  bool _penDetected = false;

  /// 是否有压感数据
  bool _hasPressure = false;

  /// 缓存的 isSupported 结果（同步读取）
  bool _isSupportedCached = false;

  /// 同步获取是否支持原生压感（需先调用 isSupported()）
  bool get isSupportedSync => _isSupportedCached;

  /// 获取压感数据流
  Stream<NativePressureData> get pressureStream {
    _pressureStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map) {
            final data = NativePressureData.fromMap(event);
            _latestData[data.pointerId] = data;
            _latestPressure = data.pressure;
            if (data.isPen) _penDetected = true;
            if (data.hasPressure) _hasPressure = true;
            return data;
          }
          throw const FormatException('无效的压感数据格式');
        })
        .handleError((error) {
          debugPrint('[NativePressureService] 错误: $error');
        })
        .asBroadcastStream();
    return _pressureStream!;
  }

  /// 获取最新压感值
  double get latestPressure => _latestPressure;

  /// 是否检测到数位笔
  bool get penDetected => _penDetected;

  /// 是否有压感数据
  bool get hasPressure => _hasPressure;

  /// 内部订阅，保证流始终活跃以更新缓存值
  StreamSubscription<NativePressureData>? _internalSub;

  /// 确保内部订阅活跃
  void _ensureListening() {
    if (_internalSub == null) {
      _internalSub = pressureStream.listen((data) {
        // 内部订阅：仅用于保证 .map() 中的缓存值持续更新
      });
    }
  }

  /// 检查原生压感是否支持
  Future<bool> isSupported() async {
    try {
      if (!kIsWeb && !Platform.isWindows) {
        _isSupportedCached = false;
        return false;
      }
      final result = await _methodChannel.invokeMethod<bool>('isSupported');
      _isSupportedCached = result == true;
      if (_isSupportedCached) {
        _ensureListening();
      }
      return _isSupportedCached;
    } on PlatformException catch (e) {
      debugPrint('[NativePressureService] 检查支持失败: $e');
      return false;
    } on MissingPluginException {
      debugPrint('[NativePressureService] 原生插件未注册');
      return false;
    }
  }

  /// 重置状态
  void reset() {
    _latestData.clear();
    _latestPressure = 0.0;
    _penDetected = false;
    _hasPressure = false;
  }

  /// 获取屏幕指定位置的颜色
  Future<Color?> getScreenColor(double x, double y) async {
    try {
      if (!kIsWeb && !Platform.isWindows) {
        return null;
      }
      final result = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
        'getScreenColor',
        {'x': x, 'y': y},
      );
      if (result != null) {
        final r = result['r'] as int? ?? 0;
        final g = result['g'] as int? ?? 0;
        final b = result['b'] as int? ?? 0;
        final a = result['a'] as int? ?? 255;
        return Color.fromARGB(a, r, g, b);
      }
    } on PlatformException catch (e) {
      debugPrint('[NativePressureService] 获取屏幕颜色失败: $e');
    } on MissingPluginException {
      debugPrint('[NativePressureService] 原生插件未注册');
    }
    return null;
  }
}
