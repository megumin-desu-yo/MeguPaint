import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 复盘信息标签
class ReviewInfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const ReviewInfoChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// 复盘步骤卡片
class ReviewStepCard extends StatelessWidget {
  final Map<String, dynamic> step;
  final bool showGuessInfo;
  final Map<String, Uint8List?> pngCache;

  const ReviewStepCard({
    super.key,
    required this.step,
    required this.showGuessInfo,
    required this.pngCache,
  });

  @override
  Widget build(BuildContext context) {
    final pngBase64 = step['pngBase64'] as String;
    Uint8List? imageBytes;
    if (pngBase64.isNotEmpty) {
      final cached = pngCache[pngBase64];
      if (cached != null) {
        imageBytes = cached;
      } else {
        try {
          imageBytes = base64Decode(pngBase64);
        } catch (_) {}
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ReviewInfoChip(
                label: '作画：${step['drawerName']}',
                icon: Icons.brush,
                color: Colors.blue,
              ),
              const SizedBox(width: 12),
              ReviewInfoChip(
                label: '题目：${step['word']}',
                icon: Icons.title,
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: imageBytes != null
                    ? Image.memory(
                        imageBytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      )
                    : const Center(
                        child: Icon(
                          Icons.image_not_supported,
                          size: 64,
                          color: Colors.grey,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          AnimatedOpacity(
            opacity: showGuessInfo ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ReviewInfoChip(
                  label: '猜测人：${step['guesserName']}',
                  icon: Icons.person_search,
                  color: Colors.orange,
                ),
                const SizedBox(width: 12),
                ReviewInfoChip(
                  label: '猜测：${step['guessText']}',
                  icon: Icons.help_outline,
                  color: Colors.deepOrange,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 领奖台排名项
class PodiumRankItem extends StatelessWidget {
  final Color color;
  final String title;
  final String name;
  final int? score;

  const PodiumRankItem({
    super.key,
    required this.color,
    required this.title,
    required this.name,
    this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
          if (score != null) ...[
            const SizedBox(height: 4),
            Text(
              '$score 分',
              style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 领奖台柱子
class PodiumColumn extends StatelessWidget {
  final double height;
  final Color color;
  final String title;
  final String name;

  const PodiumColumn({
    super.key,
    required this.height,
    required this.color,
    required this.title,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          name.isEmpty ? '-' : name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 140,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 18),
            ],
          ),
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
