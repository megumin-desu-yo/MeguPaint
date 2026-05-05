import 'package:flutter/material.dart';

/// 飞球动画类型
enum FlySourceType { vote, favorite }

/// 飞球动画源
class FlySource {
  final Offset from;
  final Color color;
  final FlySourceType type;

  FlySource({
    required this.from,
    required this.color,
    this.type = FlySourceType.vote,
  });
}

/// 飞球动画实例
class FlyBall {
  final AnimationController controller;
  final Animation<double> anim;
  final Offset start;
  final Offset control;
  final Offset end;
  final Color color;
  final String targetFp;

  FlyBall({
    required this.controller,
    required this.anim,
    required this.start,
    required this.control,
    required this.end,
    required this.color,
    required this.targetFp,
  });
}

/// 飞球绘制器
class FlyBallPainter extends CustomPainter {
  final List<FlyBall> balls;

  FlyBallPainter({required this.balls});

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in balls) {
      final t = b.anim.value;
      final p = _quadraticBezier(b.start, b.control, b.end, t);

      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(p + const Offset(1.5, 2.0), 8.5, shadowPaint);

      final paint = Paint()..color = b.color;
      canvas.drawCircle(p, 8.0, paint);
    }
  }

  Offset _quadraticBezier(Offset a, Offset c, Offset b, double t) {
    final mt = 1 - t;
    return a * (mt * mt) + c * (2 * mt * t) + b * (t * t);
  }

  @override
  bool shouldRepaint(covariant FlyBallPainter oldDelegate) {
    return true;
  }
}
