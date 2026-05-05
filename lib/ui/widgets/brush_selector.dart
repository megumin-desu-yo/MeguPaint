import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;

import '../../domain/brush/brush_preset.dart';
import '../../presentation/providers/drawing_provider.dart';

/// 笔刷引擎类型的显示名称和图标
const Map<BrushEngineType, ({String name, IconData icon})> _engineMeta = {
  BrushEngineType.round: (name: '圆形', icon: Icons.circle),
  BrushEngineType.pencil: (name: '铅笔', icon: Icons.edit),
  BrushEngineType.airbrush: (name: '喷枪', icon: Icons.blur_on),
  BrushEngineType.marker: (name: '马克笔', icon: Icons.format_color_fill),
  BrushEngineType.ink: (name: '墨水', icon: Icons.brush),
};

/// 笔刷选择器面板
/// 显示当前笔刷信息，允许调整参数
class BrushSelectorPanel extends ConsumerStatefulWidget {
  const BrushSelectorPanel({super.key});

  @override
  ConsumerState<BrushSelectorPanel> createState() => _BrushSelectorPanelState();
}

class _BrushSelectorPanelState extends ConsumerState<BrushSelectorPanel> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final presetState = ref.watch(brushPresetProvider);
    final currentPreset = presetState.currentPreset;
    final meta = _engineMeta[currentPreset.engineType];
    final curveExp = ref.watch(brushSizeCurveExponentProvider);

    double toUi(double actual, double min, double max) {
      final t = ((actual - min) / (max - min)).clamp(0.0, 1.0);
      return math.pow(t, 1.0 / curveExp).toDouble();
    }

    double toActual(double ui, double min, double max) {
      final t = ui.clamp(0.0, 1.0);
      return min + (max - min) * math.pow(t, curveExp).toDouble();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前笔刷显示
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // 笔刷图标
              Icon(
                meta?.icon ?? Icons.brush,
                size: 24,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              // 笔刷名称
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('当前笔刷', style: Theme.of(context).textTheme.labelSmall),
                    Text(
                      currentPreset.name,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // 快速参数调节
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              // 尺寸
              _ParamSlider(
                label: '大小',
                value: toUi(currentPreset.baseSize, 1, 100),
                min: 0,
                max: 1,
                displayText: toActual(
                  toUi(currentPreset.baseSize, 1, 100),
                  1,
                  100,
                ).toStringAsFixed(1),
                onChanged: (v) {
                  final actual = toActual(v, 1, 100);
                  ref.read(brushPresetProvider.notifier).setBaseSize(actual);
                  ref.read(drawingProvider.notifier).setWidth(actual);
                  ref.read(brushProvider.notifier).setWidth(actual);
                },
              ),
              // 不透明度
              _ParamSlider(
                label: '不透明度',
                value: currentPreset.baseOpacity,
                min: 0.01,
                max: 1.0,
                displayText: '${(currentPreset.baseOpacity * 100).toInt()}%',
                onChanged: (v) {
                  ref.read(brushPresetProvider.notifier).setBaseOpacity(v);
                  ref.read(drawingProvider.notifier).setOpacity(v);
                  ref.read(brushProvider.notifier).setOpacity(v);
                },
              ),
              // 硬度
              _ParamSlider(
                label: '硬度',
                value: currentPreset.hardness,
                min: 0.0,
                max: 1.0,
                displayText: '${(currentPreset.hardness * 100).toInt()}%',
                onChanged: (v) {
                  ref.read(brushPresetProvider.notifier).setHardness(v);
                },
              ),
              // 流量
              _ParamSlider(
                label: '流量',
                value: currentPreset.flow,
                min: 0.01,
                max: 1.0,
                displayText: '${(currentPreset.flow * 100).toInt()}%',
                onChanged: (v) {
                  ref.read(brushPresetProvider.notifier).setFlow(v);
                },
              ),
            ],
          ),
        ),

        // 高级设置展开
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  _showAdvanced ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text('高级参数', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),

        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _showAdvanced
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        // 间距
                        _ParamSlider(
                          label: '间距',
                          value: currentPreset.spacing,
                          min: 0.01,
                          max: 2.0,
                          displayText:
                              '${(currentPreset.spacing * 100).toInt()}%',
                          onChanged: (v) {
                            ref
                                .read(brushPresetProvider.notifier)
                                .setSpacing(v);
                          },
                        ),
                        // 圆度
                        _ParamSlider(
                          label: '圆度',
                          value: currentPreset.roundness,
                          min: 0.1,
                          max: 1.0,
                          displayText:
                              '${(currentPreset.roundness * 100).toInt()}%',
                          onChanged: (v) {
                            ref
                                .read(brushPresetProvider.notifier)
                                .setRoundness(v);
                          },
                        ),
                        // 角度
                        _ParamSlider(
                          label: '角度',
                          value: currentPreset.angle * 180 / 3.14159,
                          min: 0,
                          max: 360,
                          displayText:
                              '${(currentPreset.angle * 180 / 3.14159).toInt()}°',
                          onChanged: (v) {
                            ref
                                .read(brushPresetProvider.notifier)
                                .setAngle(v * 3.14159 / 180);
                          },
                        ),
                        // 稳定度
                        _ParamSlider(
                          label: '稳定度',
                          value: currentPreset.stabilization,
                          min: 0.0,
                          max: 1.0,
                          displayText:
                              '${(currentPreset.stabilization * 100).toInt()}%',
                          onChanged: (v) {
                            ref
                                .read(brushPresetProvider.notifier)
                                .setStabilization(v);
                            ref
                                .read(drawingProvider.notifier)
                                .setStabilization(v);
                            ref
                                .read(brushProvider.notifier)
                                .setStabilization(v);
                          },
                        ),
                        // 压感开关
                        Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(
                                '压感',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const Spacer(),
                            Transform.scale(
                              scale: 0.6,
                              child: Switch(
                                value: currentPreset.pressureEnabled,
                                onChanged: (v) {
                                  ref
                                      .read(brushPresetProvider.notifier)
                                      .setPressureEnabled(v);
                                  ref
                                      .read(drawingProvider.notifier)
                                      .setPressureEnabled(v);
                                  ref
                                      .read(brushProvider.notifier)
                                      .setPressureEnabled(v);
                                },
                              ),
                            ),
                          ],
                        ),
                        // 平滑开关
                        Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(
                                '平滑',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const Spacer(),
                            Transform.scale(
                              scale: 0.6,
                              child: Switch(
                                value: currentPreset.smoothEnabled,
                                onChanged: (v) {
                                  ref
                                      .read(brushPresetProvider.notifier)
                                      .setSmoothEnabled(v);
                                  ref
                                      .read(drawingProvider.notifier)
                                      .setSmoothEnabled(v);
                                  ref
                                      .read(brushProvider.notifier)
                                      .setSmoothEnabled(v);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// 参数滑块
class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String displayText;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            displayText,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
