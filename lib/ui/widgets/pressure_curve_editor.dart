import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import '../../services/input/native_pressure_service.dart';

/// 压感曲线控制点
class PressureControlPoint {
  /// 输入压力 (0.0 - 1.0)
  double x;

  /// 输出压力 (0.0 - 1.0)
  double y;

  PressureControlPoint({required this.x, required this.y});

  Map<String, dynamic> toMap() => {'x': x, 'y': y};

  factory PressureControlPoint.fromMap(Map<String, dynamic> map) =>
      PressureControlPoint(x: map['x'] as double, y: map['y'] as double);
}

/// 压感曲线编辑器
/// 允许用户通过拖动控制点来调整压感响应曲线
class PressureCurveEditor extends StatefulWidget {
  /// 控制点列表（至少2个点：起点和终点）
  final List<PressureControlPoint> controlPoints;

  /// 曲线变化回调
  final ValueChanged<List<PressureControlPoint>> onCurveChanged;

  /// 还原默认回调
  final VoidCallback? onReset;

  /// 编辑器尺寸
  final Size size;

  const PressureCurveEditor({
    super.key,
    required this.controlPoints,
    required this.onCurveChanged,
    this.onReset,
    this.size = const Size(200, 200),
  });

  /// 默认线性曲线控制点
  static List<PressureControlPoint> defaultCurve() => [
    PressureControlPoint(x: 0.0, y: 0.0),
    PressureControlPoint(x: 1.0, y: 1.0),
  ];

  /// "软"曲线（轻压也有较强输出）
  static List<PressureControlPoint> softCurve() => [
    PressureControlPoint(x: 0.0, y: 0.0),
    PressureControlPoint(x: 0.3, y: 0.6),
    PressureControlPoint(x: 1.0, y: 1.0),
  ];

  /// "硬"曲线（需要较大压力才有输出）
  static List<PressureControlPoint> hardCurve() => [
    PressureControlPoint(x: 0.0, y: 0.0),
    PressureControlPoint(x: 0.6, y: 0.3),
    PressureControlPoint(x: 1.0, y: 1.0),
  ];

  /// 根据输入压力计算输出压力（使用分段线性插值）
  static double calculateOutput(
    List<PressureControlPoint> points,
    double input,
  ) {
    if (points.isEmpty) return input;
    if (points.length == 1) return points.first.y;

    // 确保输入在有效范围内
    input = input.clamp(0.0, 1.0);

    // 找到输入值所在的区间
    for (int i = 0; i < points.length - 1; i++) {
      if (input >= points[i].x && input <= points[i + 1].x) {
        // 线性插值
        final t = (input - points[i].x) / (points[i + 1].x - points[i].x);
        return points[i].y + t * (points[i + 1].y - points[i].y);
      }
    }

    // 如果超出范围，返回最后一个点的值
    return points.last.y;
  }

  @override
  State<PressureCurveEditor> createState() => _PressureCurveEditorState();
}

class _PressureCurveEditorState extends State<PressureCurveEditor> {
  /// 当前拖动的控制点索引
  int? _draggingIndex;

  /// 处理控制点拖动
  void _handlePanStart(DragStartDetails details, Size canvasSize) {
    final localPosition = details.localPosition;
    const padding = 30.0;
    final graphSize = Size(
      canvasSize.width - padding * 2,
      canvasSize.height - padding * 2,
    );

    // 检查是否点击了某个控制点
    for (int i = 0; i < widget.controlPoints.length; i++) {
      final point = widget.controlPoints[i];
      final pointX = padding + point.x * graphSize.width;
      final pointY = padding + (1 - point.y) * graphSize.height;
      final distance =
          (localPosition.dx - pointX).abs() + (localPosition.dy - pointY).abs();

      if (distance < 20) {
        setState(() {
          _draggingIndex = i;
        });
        return;
      }
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (_draggingIndex == null) return;

    final localPosition = details.localPosition;
    const padding = 30.0;
    final graphSize = Size(
      canvasSize.width - padding * 2,
      canvasSize.height - padding * 2,
    );

    // 计算新的控制点位置
    double newX = ((localPosition.dx - padding) / graphSize.width).clamp(
      0.0,
      1.0,
    );
    double newY = (1 - (localPosition.dy - padding) / graphSize.height).clamp(
      0.0,
      1.0,
    );

    // 起点和终点只能调整Y值
    if (_draggingIndex == 0) {
      newX = 0.0;
    } else if (_draggingIndex == widget.controlPoints.length - 1) {
      newX = 1.0;
    } else {
      // 中间点需要确保X值有序
      if (_draggingIndex! > 0) {
        newX = math.max(
          newX,
          widget.controlPoints[_draggingIndex! - 1].x + 0.05,
        );
      }
      if (_draggingIndex! < widget.controlPoints.length - 1) {
        newX = math.min(
          newX,
          widget.controlPoints[_draggingIndex! + 1].x - 0.05,
        );
      }
    }

    // 更新控制点
    final newPoints = List<PressureControlPoint>.from(widget.controlPoints);
    newPoints[_draggingIndex!] = PressureControlPoint(x: newX, y: newY);
    widget.onCurveChanged(newPoints);
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _draggingIndex = null;
    });
  }

  /// 添加控制点
  void _addControlPoint() {
    if (widget.controlPoints.length >= 8) return; // 最多8个控制点

    final newPoints = List<PressureControlPoint>.from(widget.controlPoints);

    // 在最后一个点之前添加新点
    final lastPoint = newPoints.last;
    newPoints.insert(
      newPoints.length - 1,
      PressureControlPoint(x: lastPoint.x * 0.5, y: lastPoint.y * 0.5),
    );

    widget.onCurveChanged(newPoints);
  }

  /// 删除控制点
  void _removeControlPoint(int index) {
    if (widget.controlPoints.length <= 2) return; // 至少保留2个点
    if (index == 0 || index == widget.controlPoints.length - 1)
      return; // 不能删除起点和终点

    final newPoints = List<PressureControlPoint>.from(widget.controlPoints);
    newPoints.removeAt(index);
    widget.onCurveChanged(newPoints);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 曲线编辑器
        GestureDetector(
          onPanStart: (details) => _handlePanStart(details, widget.size),
          onPanUpdate: (details) => _handlePanUpdate(details, widget.size),
          onPanEnd: _handlePanEnd,
          child: CustomPaint(
            size: widget.size,
            painter: _CurvePainter(
              controlPoints: widget.controlPoints,
              draggingIndex: _draggingIndex,
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 控制按钮
        Row(
          children: [
            // 添加控制点
            IconButton(
              icon: const Icon(Icons.add),
              iconSize: 20,
              tooltip: '添加控制点',
              onPressed: widget.controlPoints.length < 8
                  ? _addControlPoint
                  : null,
            ),
            // 删除控制点（如果有可删除的点）
            if (widget.controlPoints.length > 2)
              IconButton(
                icon: const Icon(Icons.remove),
                iconSize: 20,
                tooltip: '删除选中控制点',
                onPressed:
                    _draggingIndex != null &&
                        _draggingIndex! > 0 &&
                        _draggingIndex! < widget.controlPoints.length - 1
                    ? () => _removeControlPoint(_draggingIndex!)
                    : null,
              ),
            const Spacer(),
            // 预设曲线
            Tooltip(
              message: '线性',
              child: InkWell(
                onTap: () =>
                    widget.onCurveChanged(PressureCurveEditor.defaultCurve()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: const Text('线性', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
            Tooltip(
              message: '软曲线',
              child: InkWell(
                onTap: () =>
                    widget.onCurveChanged(PressureCurveEditor.softCurve()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: const Text('软', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
            Tooltip(
              message: '硬曲线',
              child: InkWell(
                onTap: () =>
                    widget.onCurveChanged(PressureCurveEditor.hardCurve()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: const Text('硬', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 还原默认
            if (widget.onReset != null)
              TextButton.icon(
                onPressed: widget.onReset,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('还原默认', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }
}

/// 曲线绘制器
class _CurvePainter extends CustomPainter {
  final List<PressureControlPoint> controlPoints;
  final int? draggingIndex;

  _CurvePainter({required this.controlPoints, this.draggingIndex});

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 30.0;
    final graphSize = Size(size.width - padding * 2, size.height - padding * 2);

    // 绘制背景
    final bgPaint = Paint()..color = Colors.grey.shade900;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(padding, padding, graphSize.width, graphSize.height),
      const Radius.circular(4),
    );
    canvas.drawRRect(bgRect, bgPaint);

    // 绘制网格
    final gridPaint = Paint()
      ..color = Colors.grey.shade700
      ..strokeWidth = 0.5;

    // 垂直网格线
    for (int i = 0; i <= 10; i++) {
      final x = padding + (i / 10) * graphSize.width;
      canvas.drawLine(
        Offset(x, padding),
        Offset(x, padding + graphSize.height),
        gridPaint,
      );
    }

    // 水平网格线
    for (int i = 0; i <= 10; i++) {
      final y = padding + (i / 10) * graphSize.height;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + graphSize.width, y),
        gridPaint,
      );
    }

    // 绘制对角参考线（线性）
    final refLinePaint = Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(padding, padding + graphSize.height),
      Offset(padding + graphSize.width, padding),
      refLinePaint,
    );

    // 绘制曲线
    if (controlPoints.length >= 2) {
      final curvePath = Path();
      final curvePaint = Paint()
        ..color = Colors.cyan
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      // 使用分段线性插值绘制曲线
      for (int i = 0; i < 100; i++) {
        final t = i / 100;
        final output = PressureCurveEditor.calculateOutput(controlPoints, t);
        final x = padding + t * graphSize.width;
        final y = padding + (1 - output) * graphSize.height;

        if (i == 0) {
          curvePath.moveTo(x, y);
        } else {
          curvePath.lineTo(x, y);
        }
      }
      canvas.drawPath(curvePath, curvePaint);
    }

    // 绘制坐标轴标签
    final labelStyle = TextStyle(color: Colors.grey.shade400, fontSize: 10);

    // X轴标签
    _drawText(
      canvas,
      '输入',
      Offset(size.width / 2 - 15, size.height - 8),
      labelStyle,
    );
    _drawText(canvas, '0', Offset(padding - 5, size.height - 8), labelStyle);
    _drawText(
      canvas,
      '1',
      Offset(padding + graphSize.width - 5, size.height - 8),
      labelStyle,
    );

    // Y轴标签
    _drawText(canvas, '输出', Offset(2, padding - 5), labelStyle);
    _drawText(canvas, '1', Offset(2, padding - 5), labelStyle);
    _drawText(
      canvas,
      '0',
      Offset(2, padding + graphSize.height - 5),
      labelStyle,
    );

    // 绘制控制点
    for (int i = 0; i < controlPoints.length; i++) {
      final point = controlPoints[i];
      final x = padding + point.x * graphSize.width;
      final y = padding + (1 - point.y) * graphSize.height;

      final isDragging = i == draggingIndex;
      final radius = isDragging ? 8.0 : 6.0;

      // 外圈
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = isDragging ? Colors.orange : Colors.cyan,
      );

      // 内圈
      canvas.drawCircle(
        Offset(x, y),
        radius - 2,
        Paint()..color = Colors.grey.shade900,
      );

      // 中心点
      canvas.drawCircle(
        Offset(x, y),
        2,
        Paint()..color = isDragging ? Colors.orange : Colors.cyan,
      );
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) {
    return controlPoints != oldDelegate.controlPoints ||
        draggingIndex != oldDelegate.draggingIndex;
  }
}

/// 压感测试区域
/// 允许用户测试当前压感曲线的效果
class PressureTestArea extends StatefulWidget {
  /// 压感曲线控制点
  final List<PressureControlPoint> controlPoints;

  /// 测试区域尺寸
  final double height;

  const PressureTestArea({
    super.key,
    required this.controlPoints,
    this.height = 80,
  });

  @override
  State<PressureTestArea> createState() => _PressureTestAreaState();
}

class _PressureTestAreaState extends State<PressureTestArea> {
  /// 测试笔画点列表
  final List<_TestPoint> _testPoints = [];

  /// 当前压感值
  double _currentPressure = 0.0;
  double _currentOutput = 0.0;

  /// 诊断信息
  String _diagnosticInfo = '';
  PointerDeviceKind _lastDeviceKind = PointerDeviceKind.unknown;
  double _lastRawPressure = 0.0;
  double _lastPressureMin = 0.0;
  double _lastPressureMax = 1.0;

  /// 原生压感服务
  final _nativePressure = NativePressureService.instance;
  StreamSubscription<NativePressureData>? _pressureSub;
  double _nativePressureValue = 0.0;
  bool _nativeHasPressure = false;
  bool _nativeIsPen = false;
  bool _nativeSupported = false;
  bool _isDrawing = false;

  @override
  void initState() {
    super.initState();
    _initNativePressure();
  }

  Future<void> _initNativePressure() async {
    _nativeSupported = await _nativePressure.isSupported();
    if (_nativeSupported) {
      _pressureSub = _nativePressure.pressureStream.listen((data) {
        // 仅在绘制时更新原生压感值
        if (_isDrawing) {
          _nativePressureValue = data.pressure;
          _nativeHasPressure = data.hasPressure;
          _nativeIsPen = data.isPen;
        }
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pressureSub?.cancel();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    _testPoints.clear();
    _isDrawing = true;
    _updateDiagnostic(event);
    final pressure = _extractPressure(event);
    setState(() {
      _currentPressure = pressure;
      _currentOutput = PressureCurveEditor.calculateOutput(
        widget.controlPoints,
        pressure,
      );
      _testPoints.add(
        _TestPoint(
          position: event.localPosition,
          pressure: pressure,
          outputPressure: _currentOutput,
        ),
      );
    });
  }

  void _handlePointerMove(PointerEvent event) {
    _updateDiagnostic(event);
    final pressure = _extractPressure(event);
    setState(() {
      _currentPressure = pressure;
      _currentOutput = PressureCurveEditor.calculateOutput(
        widget.controlPoints,
        pressure,
      );
      _testPoints.add(
        _TestPoint(
          position: event.localPosition,
          pressure: pressure,
          outputPressure: _currentOutput,
        ),
      );
    });
  }

  void _handlePointerUp(PointerEvent event) {
    _isDrawing = false;
    // 保留笔画供查看
  }

  void _clearTest() {
    setState(() {
      _testPoints.clear();
      _currentPressure = 0.0;
      _currentOutput = 0.0;
      _diagnosticInfo = '';
      _nativePressureValue = 0.0;
      _nativeHasPressure = false;
      _nativeIsPen = false;
    });
  }

  void _updateDiagnostic(PointerEvent event) {
    _lastDeviceKind = event.kind;
    _lastRawPressure = event.pressure;
    _lastPressureMin = event.pressureMin;
    _lastPressureMax = event.pressureMax;

    final nativeInfo = _nativeSupported
        ? '\n[原生] 压感: ${_nativePressureValue.toStringAsFixed(3)}, '
              '数位笔: $_nativeIsPen, 有压感: $_nativeHasPressure'
        : '\n[原生] 不支持 (非 Windows 或 API 不可用)';

    _diagnosticInfo =
        '[Flutter] 设备: ${event.kind}, '
        '压感: ${event.pressure.toStringAsFixed(3)}, '
        '范围: ${event.pressureMin.toStringAsFixed(3)}-${event.pressureMax.toStringAsFixed(3)}'
        '$nativeInfo';
  }

  double _extractPressure(PointerEvent event) {
    // 优先使用原生压感数据
    if (_nativeSupported && _nativeHasPressure && _nativePressureValue > 0) {
      return _nativePressureValue.clamp(0.0, 1.0);
    }

    final kind = event.kind;
    final min = event.pressureMin;
    final max = event.pressureMax;
    final raw = event.pressure;

    // 数位笔设备：使用归一化压感
    if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus) {
      if (max <= min) return raw.clamp(0.0, 1.0);
      return ((raw - min) / (max - min)).clamp(0.0, 1.0);
    }

    // 尝试从原始压感值提取
    if (raw > 0 && max > min) {
      final normalized = ((raw - min) / (max - min)).clamp(0.0, 1.0);
      if (normalized != 0.5) {
        return normalized;
      }
    }

    // 无压感数据
    return raw.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // 判断设备是否支持压感
    final hasStylus =
        _lastDeviceKind == PointerDeviceKind.stylus ||
        _lastDeviceKind == PointerDeviceKind.invertedStylus;
    final hasNativePen = _nativeIsPen && _nativeHasPressure;
    final hasPressureData =
        hasNativePen ||
        (_lastRawPressure > 0 &&
            _lastPressureMax > _lastPressureMin &&
            _lastRawPressure != 0.5);

    // 压感来源判断
    final String pressureSource;
    final Color statusColor;
    if (hasStylus) {
      pressureSource = '数位笔 (Flutter)';
      statusColor = Colors.green;
    } else if (hasNativePen) {
      pressureSource = '数位笔 (原生)';
      statusColor = Colors.green;
    } else if (hasPressureData) {
      pressureSource = '检测到压感';
      statusColor = Colors.orange;
    } else if (_nativeSupported) {
      pressureSource = '原生已就绪';
      statusColor = Colors.blue;
    } else {
      pressureSource = '无压感';
      statusColor = Colors.grey;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题和清除按钮
        Row(
          children: [
            Text('压感测试区域', style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            // 压感状态指示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                pressureSource,
                style: TextStyle(fontSize: 10, color: statusColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '原始: ${_currentPressure.toStringAsFixed(3)} → 输出: ${_currentOutput.toStringAsFixed(3)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: Colors.cyan,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _clearTest,
              tooltip: '清除',
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 诊断信息
        if (_diagnosticInfo.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _diagnosticInfo,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.grey,
              ),
            ),
          ),
        const SizedBox(height: 4),
        // 测试画布
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade600),
          ),
          child: Listener(
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: _TestAreaPainter(
                    points: _testPoints,
                    currentOutput: _currentOutput,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 提示文字
        Text(
          '使用数位笔测试真实压感值。Windows平台可能需要特殊驱动支持。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade500,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

/// 测试点
class _TestPoint {
  final Offset position;
  final double pressure;
  final double outputPressure;

  _TestPoint({
    required this.position,
    required this.pressure,
    required this.outputPressure,
  });
}

/// 测试区域绘制器
class _TestAreaPainter extends CustomPainter {
  final List<_TestPoint> points;
  final double currentOutput;

  _TestAreaPainter({required this.points, required this.currentOutput});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // 绘制笔画
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];

      // 使用输出压感计算线宽
      final width = 2 + p2.outputPressure * 20;

      final paint = Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(p1.position, p2.position, paint);
    }

    // 绘制当前压感指示器
    if (points.isNotEmpty) {
      final lastPoint = points.last;

      // 压感圆圈
      canvas.drawCircle(
        lastPoint.position,
        3 + currentOutput * 10,
        Paint()
          ..color = Colors.cyan.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TestAreaPainter oldDelegate) {
    return points.length != oldDelegate.points.length ||
        currentOutput != oldDelegate.currentOutput;
  }
}
