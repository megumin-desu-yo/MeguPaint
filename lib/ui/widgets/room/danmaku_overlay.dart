import 'package:flutter/material.dart';

/// 弹幕数据项
class DanmakuItem {
  final int id;
  final String sender;
  final String content;
  final double topRatio; // 0.0~0.5 垂直位置比例

  DanmakuItem({
    required this.id,
    required this.sender,
    required this.content,
    required this.topRatio,
  });
}

/// 弹幕覆盖层
class DanmakuOverlay extends StatefulWidget {
  final List<DanmakuItem> items;
  final ValueChanged<int> onItemComplete;

  const DanmakuOverlay({
    super.key,
    required this.items,
    required this.onItemComplete,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: widget.items.map((item) {
              final top = constraints.maxHeight * item.topRatio;
              return DanmakuBubble(
                key: ValueKey(item.id),
                item: item,
                containerWidth: constraints.maxWidth,
                top: top,
                onComplete: () => widget.onItemComplete(item.id),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

/// 单条弹幕气泡（自带动画）
class DanmakuBubble extends StatefulWidget {
  final DanmakuItem item;
  final double containerWidth;
  final double top;
  final VoidCallback onComplete;

  const DanmakuBubble({
    super.key,
    required this.item,
    required this.containerWidth,
    required this.top,
    required this.onComplete,
  });

  @override
  State<DanmakuBubble> createState() => _DanmakuBubbleState();
}

class _DanmakuBubbleState extends State<DanmakuBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // 8~12秒飘过，根据内容长度微调
    final duration = Duration(
      milliseconds: 8000 + (widget.item.content.length * 80).clamp(0, 4000),
    );
    _controller = AnimationController(vsync: this, duration: duration);
    // 从右侧屏幕外 → 左侧屏幕外
    _animation = Tween<double>(
      begin: widget.containerWidth,
      end: -400.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Positioned(
          left: _animation.value,
          top: widget.top,
          child: child!,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.item.sender,
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.item.content,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
