import 'package:flutter/material.dart';

/// 投票弹幕项
class VoteBarrageItem extends StatelessWidget {
  final String username;
  final bool isUp;

  const VoteBarrageItem({super.key, required this.username, required this.isUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isUp ? Colors.green : Colors.red).withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            username,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isUp ? Icons.check_circle : Icons.cancel,
            color: Colors.white,
            size: 16,
          ),
        ],
      ),
    );
  }
}
