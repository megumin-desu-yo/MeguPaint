import 'dart:math' as math;

import 'package:flutter/material.dart';

/// HSV 颜色选择器组件
/// 包含：色相环 + 内部SV方形色轮 + 当前颜色预览
class HsvColorPicker extends StatefulWidget {
  /// 当前选中的颜色
  final Color color;

  /// 颜色变化回调
  final ValueChanged<Color> onColorChanged;

  /// 选择器宽度
  final double width;

  /// 选择器高度
  final double height;

  const HsvColorPicker({
    super.key,
    required this.color,
    required this.onColorChanged,
    this.width = 200,
    this.height = 200, //这个值会被覆盖
  });

  @override
  State<HsvColorPicker> createState() => _HsvColorPickerState();
}

class _ColorWheelPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  static const double _squareGapFactor = 0.98;

  _ColorWheelPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.7;
    final squareSize = innerRadius * math.sqrt2 * _squareGapFactor;

    _drawHueWheel(canvas, center, outerRadius, innerRadius);
    _drawSaturationValueSquare(canvas, center, squareSize);
    _drawWheelSelector(canvas, center, outerRadius, innerRadius);
    _drawSquareSelector(canvas, center, squareSize);
  }

  void _drawHueWheel(
    Canvas canvas,
    Offset center,
    double outerRadius,
    double innerRadius,
  ) {
    final rect = Rect.fromCircle(center: center, radius: outerRadius);

    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: const [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
      stops: const [0.0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1.0],
    );

    final ringWidth = (outerRadius - innerRadius) * 0.6;
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.butt;

    final midRadius = (outerRadius + innerRadius) / 2;
    canvas.drawCircle(center, midRadius, paint);

    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..color = Colors.grey.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 外圈白色描边 - 紧贴色环
    final outerEdgeRadius = midRadius + ringWidth / 2;
    canvas.drawCircle(
      center,
      outerEdgeRadius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 外圈灰色边框
    canvas.drawCircle(
      center,
      outerEdgeRadius + 1,
      Paint()
        ..color = Colors.grey
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawSaturationValueSquare(
    Canvas canvas,
    Offset center,
    double squareSize,
  ) {
    final squareRect = Rect.fromCenter(
      center: center,
      width: squareSize,
      height: squareSize,
    );

    final baseColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    final white = HSVColor.fromAHSV(1.0, hue, 0.0, 1.0).toColor();

    final saturationGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [white, baseColor],
    );

    canvas.drawRect(
      squareRect,
      Paint()..shader = saturationGradient.createShader(squareRect),
    );

    final valueGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    );

    canvas.drawRect(
      squareRect,
      Paint()
        ..shader = valueGradient.createShader(squareRect)
        ..blendMode = BlendMode.srcOver,
    );

    canvas.drawRect(
      squareRect,
      Paint()
        ..color = Colors.grey.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawWheelSelector(
    Canvas canvas,
    Offset center,
    double outerRadius,
    double innerRadius,
  ) {
    final angle = hue * math.pi / 180;
    final midRadius = (outerRadius + innerRadius) / 2;
    final selectorX = center.dx + midRadius * math.cos(angle);
    final selectorY = center.dy + midRadius * math.sin(angle);

    canvas.drawCircle(
      Offset(selectorX, selectorY),
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.drawCircle(
      Offset(selectorX, selectorY),
      6,
      Paint()..color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor(),
    );
  }

  void _drawSquareSelector(Canvas canvas, Offset center, double squareSize) {
    final squareRect = Rect.fromCenter(
      center: center,
      width: squareSize,
      height: squareSize,
    );

    final selectorX = squareRect.left + saturation * squareSize;
    final selectorY = squareRect.top + (1.0 - value) * squareSize;

    final backgroundColor = HSVColor.fromAHSV(
      1.0,
      hue,
      saturation,
      value,
    ).toColor();
    final luminance = backgroundColor.computeLuminance();
    final selectorColor = luminance > 0.5 ? Colors.black : Colors.white;

    canvas.drawCircle(
      Offset(selectorX, selectorY),
      8,
      Paint()
        ..color = selectorColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.drawCircle(
      Offset(selectorX, selectorY),
      5,
      Paint()..color = backgroundColor,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return hue != oldDelegate.hue ||
        saturation != oldDelegate.saturation ||
        value != oldDelegate.value;
  }
}

class _HsvColorPickerState extends State<HsvColorPicker> {
  /// 当前 HSV 值
  late HSVColor _hsvColor;

  /// 拖动中标记
  bool _isDraggingWheel = false;
  bool _isDraggingSquare = false;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.color);
  }

  @override
  void didUpdateWidget(HsvColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部颜色变化时更新 HSV
    if (oldWidget.color != widget.color) {
      // 拖动期间外部通常会回传同一个颜色（上层 state 更新），
      // 如果此时把 RGB 再转换回 HSV，可能造成 hue 漂移，从而让外圈指示器“抖动/跳变”。
      // 因此拖动期间忽略外部同步，拖动结束后自然会保持内部状态一致。
      if (_isDraggingWheel || _isDraggingSquare) {
        return;
      }

      _hsvColor = HSVColor.fromColor(widget.color);
    }
  }

  /// 更新颜色并通知
  void _updateColor() {
    widget.onColorChanged(_hsvColor.toColor());
  }

  void _handleWheelTouch(Offset localPosition, double diameter) {
    final center = Offset(diameter / 2, diameter / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    double angle = math.atan2(dy, dx) * 180 / math.pi;
    if (angle < 0) angle += 360;

    setState(() {
      _hsvColor = _hsvColor.withHue(angle);
    });
    _updateColor();
  }

  void _handleSquareTouch(Offset localPosition, double squareSize) {
    final saturation = (localPosition.dx / squareSize).clamp(0.0, 1.0);
    final value = (1.0 - localPosition.dy / squareSize).clamp(0.0, 1.0);

    setState(() {
      _hsvColor = _hsvColor.withSaturation(saturation).withValue(value);
    });
    _updateColor();
  }

  bool _isOnWheel(Offset localPosition, double diameter) {
    final center = Offset(diameter / 2, diameter / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    final outerRadius = diameter / 2;
    final innerRadius = outerRadius * 0.7;
    return distance >= innerRadius && distance <= outerRadius;
  }

  bool _isOnSquare(Offset localPosition, double diameter) {
    final center = Offset(diameter / 2, diameter / 2);
    final outerRadius = diameter / 2;
    final innerRadius = outerRadius * 0.7;
    final squareSize =
        innerRadius * math.sqrt2 * _ColorWheelPainter._squareGapFactor;

    final squareRect = Rect.fromCenter(
      center: center,
      width: squareSize,
      height: squareSize,
    );
    return squareRect.contains(localPosition);
  }

  @override
  Widget build(BuildContext context) {
    final diameter = math.min(widget.width, widget.height);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onPanStart: (details) {
            if (_isOnSquare(details.localPosition, diameter)) {
              _isDraggingSquare = true;
              final outerRadius = diameter / 2;
              final innerRadius = outerRadius * 0.7;
              final squareSize =
                  innerRadius *
                  math.sqrt2 *
                  _ColorWheelPainter._squareGapFactor;
              final center = Offset(diameter / 2, diameter / 2);
              final squareRect = Rect.fromCenter(
                center: center,
                width: squareSize,
                height: squareSize,
              );
              final localPos = Offset(
                details.localPosition.dx - squareRect.left,
                details.localPosition.dy - squareRect.top,
              );
              _handleSquareTouch(localPos, squareSize);
            } else if (_isOnWheel(details.localPosition, diameter)) {
              _isDraggingWheel = true;
              _handleWheelTouch(details.localPosition, diameter);
            }
          },
          onPanUpdate: (details) {
            if (_isDraggingSquare) {
              final outerRadius = diameter / 2;
              final innerRadius = outerRadius * 0.7;
              final squareSize =
                  innerRadius *
                  math.sqrt2 *
                  _ColorWheelPainter._squareGapFactor;
              final center = Offset(diameter / 2, diameter / 2);
              final squareRect = Rect.fromCenter(
                center: center,
                width: squareSize,
                height: squareSize,
              );
              final localPos = Offset(
                details.localPosition.dx - squareRect.left,
                details.localPosition.dy - squareRect.top,
              );
              _handleSquareTouch(localPos, squareSize);
            } else if (_isDraggingWheel) {
              _handleWheelTouch(details.localPosition, diameter);
            }
          },
          onPanEnd: (_) {
            _isDraggingWheel = false;
            _isDraggingSquare = false;
          },
          child: CustomPaint(
            size: Size(diameter, diameter),
            painter: _ColorWheelPainter(
              hue: _hsvColor.hue,
              saturation: _hsvColor.saturation,
              value: _hsvColor.value,
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 当前颜色预览 + 颜色值显示
        Row(
          children: [
            // 当前颜色预览
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _hsvColor.toColor(),
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            // 颜色值
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HEX: #${_hsvColor.toColor().value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    'HSV: ${_hsvColor.hue.toInt()}° ${(_hsvColor.saturation * 100).toInt()}% ${(_hsvColor.value * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
