import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show ByteData, Uint8List;
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/input/native_pressure_service.dart';
import '../../../domain/entities/layer.dart' as domain_layer;
import '../../../domain/brush/brush_preset.dart';
import '../../../domain/brush/brush_system.dart';
import '../../../domain/canvas_tool.dart';
import '../../../data/services/crypto_service_impl.dart';
import '../../../domain/utils/pressure_smoother.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/providers/artwork_provider.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/providers/drawing_provider.dart';
import '../../../presentation/providers/layer_provider.dart';
import '../../../presentation/providers/connection_provider.dart';
import '../../../presentation/providers/shortcut_provider.dart';
import '../../../presentation/providers/settings_provider.dart';
import '../../../services/project/project_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/brush_selector.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/drawing_settings_dialog.dart';
import '../../widgets/layer_panel.dart';
import '../../widgets/pressure_curve_editor.dart';
import '../../widgets/canvas/canvas_widgets.dart';

/// 笔刷引擎类型的显示名称和图标
const Map<BrushEngineType, ({String name, IconData icon})> _engineMeta = {
  BrushEngineType.round: (name: '圆形', icon: Icons.circle),
  BrushEngineType.pencil: (name: '铅笔', icon: Icons.edit),
  BrushEngineType.airbrush: (name: '喷枪', icon: Icons.blur_on),
  BrushEngineType.marker: (name: '马克笔', icon: Icons.format_color_fill),
  BrushEngineType.ink: (name: '墨水', icon: Icons.brush),
};

/// 画布屏幕 - 绘画操作界面
class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key});

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

/// 待烧录笔画（避免烧录期间的闪烁）
class _PendingStroke {
  final String id;
  final String layerId;
  final List<DrawPoint> points;
  final BrushPreset preset;
  final bool isEraser;

  _PendingStroke({
    required this.id,
    required this.layerId,
    required this.points,
    required this.preset,
    this.isEraser = false,
  });
}

enum LayerPreviewMode { overlayBox, soloCanvas }

/// 像素模式画布绘制器：合成各图层 ui.Image + 实时笔画预览（引擎版）
class _RasterPainter extends CustomPainter {
  final List<DrawLayer> layers;
  final List<DrawPoint> currentPoints;
  final int currentPointCount;
  final int activeLayerIndex;
  final BrushPreset currentPreset;
  final List<_PendingStroke> pendingStrokes;
  final bool isEraser;
  final Offset? eraserCursorPos;
  final double eraserSize;
  final bool showMagnifier;
  final Offset magnifierPosition;
  final Color previewColor;

  /// 笔刷系统实例（共享单例）
  static final BrushSystem _brushSystem = BrushSystem();

  _RasterPainter({
    required this.layers,
    required this.currentPoints,
    required this.currentPointCount,
    required this.activeLayerIndex,
    required this.currentPreset,
    this.pendingStrokes = const [],
    this.isEraser = false,
    this.eraserCursorPos,
    this.eraserSize = 10.0,
    this.showMagnifier = false,
    this.magnifierPosition = Offset.zero,
    this.previewColor = Colors.transparent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int cw = size.width.toInt();
    final int ch = size.height.toInt();
    if (cw <= 0 || ch <= 0) return;

    final pixelPaint = Paint()..filterQuality = FilterQuality.none;

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (!layer.isVisible) continue;

      final bool isActiveLayer = i == activeLayerIndex;
      final bool eraserPreview =
          isActiveLayer && isEraser && currentPoints.isNotEmpty;
      final layerPending = pendingStrokes.isEmpty
          ? const <_PendingStroke>[]
          : pendingStrokes.where((p) => p.layerId == layer.id).toList();
      final pendingEraser = layerPending
          .where((p) => p.isEraser)
          .toList(growable: false);
      final pendingBrush = layerPending
          .where((p) => !p.isEraser)
          .toList(growable: false);
      final bool needsComposite = eraserPreview || pendingEraser.isNotEmpty;

      if (needsComposite) {
        final recorder = ui.PictureRecorder();
        final offCanvas = Canvas(recorder);
        if (layer.pixels != null) {
          offCanvas.drawImage(
            layer.pixels!,
            Offset.zero,
            Paint()..filterQuality = FilterQuality.none,
          );
        }

        // 实时橡皮擦轨迹
        if (eraserPreview) {
          _brushSystem.renderStroke(
            offCanvas,
            currentPoints,
            currentPreset,
            isEraser: true,
          );
        }
        // 待烧录的橡皮擦笔画
        for (final pending in pendingEraser) {
          _brushSystem.renderStroke(
            offCanvas,
            pending.points,
            pending.preset,
            isEraser: true,
          );
        }
        final picture = recorder.endRecording();
        final compositeImage = picture.toImageSync(cw, ch);
        picture.dispose();
        final drawPaint = Paint()..filterQuality = FilterQuality.none;
        if (layer.opacity < 1.0) {
          drawPaint.color = Color.fromRGBO(255, 255, 255, layer.opacity);
        }
        canvas.drawImage(compositeImage, Offset.zero, drawPaint);
        compositeImage.dispose();
      } else {
        if (layer.pixels != null) {
          final paint = Paint()..filterQuality = FilterQuality.none;
          if (layer.opacity < 1.0) {
            paint.color = Color.fromRGBO(255, 255, 255, layer.opacity);
          }
          canvas.drawImage(layer.pixels!, Offset.zero, paint);
        }
      }

      // 活动图层：画笔实时预览（离屏像素化）
      if (isActiveLayer && currentPoints.isNotEmpty && !isEraser) {
        final recorder = ui.PictureRecorder();
        final offCanvas = Canvas(recorder);
        _brushSystem.renderStroke(offCanvas, currentPoints, currentPreset);
        final picture = recorder.endRecording();
        final strokeImage = picture.toImageSync(cw, ch);
        picture.dispose();
        canvas.drawImage(strokeImage, Offset.zero, pixelPaint);
        strokeImage.dispose();
      }

      // 待烧录的非橡皮擦笔画（离屏像素化）
      for (final pending in pendingBrush) {
        final recorder = ui.PictureRecorder();
        final offCanvas = Canvas(recorder);
        _brushSystem.renderStroke(offCanvas, pending.points, pending.preset);
        final picture = recorder.endRecording();
        final strokeImage = picture.toImageSync(cw, ch);
        picture.dispose();
        canvas.drawImage(strokeImage, Offset.zero, pixelPaint);
        strokeImage.dispose();
      }
    }

    // 橡皮擦光标预览
    if (isEraser && eraserCursorPos != null) {
      final r = eraserSize / 2;
      final cursorPaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..blendMode = BlendMode.difference;
      canvas.drawCircle(eraserCursorPos!, r, cursorPaint);
      final crossSize = r * 0.4;
      canvas.drawLine(
        eraserCursorPos! + Offset(-crossSize, 0),
        eraserCursorPos! + Offset(crossSize, 0),
        cursorPaint,
      );
      canvas.drawLine(
        eraserCursorPos! + Offset(0, -crossSize),
        eraserCursorPos! + Offset(0, crossSize),
        cursorPaint,
      );
    }

    // 颜色吸管放大镜预览
    if (showMagnifier) {
      _drawMagnifier(canvas, magnifierPosition, previewColor);
    }
  }

  /// 绘制放大镜预览
  void _drawMagnifier(Canvas canvas, Offset position, Color color) {
    const magnifierSize = 120.0;
    const zoomLevel = 8.0;
    const pixelSize = magnifierSize / zoomLevel;

    // 放大镜背景
    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, magnifierSize / 2, bgPaint);

    // 放大镜边框
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(position, magnifierSize / 2, borderPaint);

    // 绘制像素网格
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 0; i <= zoomLevel; i++) {
      final offset = i * pixelSize - magnifierSize / 2;
      // 垂直线
      canvas.drawLine(
        position + Offset(offset, -magnifierSize / 2),
        position + Offset(offset, magnifierSize / 2),
        gridPaint,
      );
      // 水平线
      canvas.drawLine(
        position + Offset(-magnifierSize / 2, offset),
        position + Offset(magnifierSize / 2, offset),
        gridPaint,
      );
    }

    // 中心像素（预览颜色）
    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromCenter(center: position, width: pixelSize, height: pixelSize),
      centerPaint,
    );

    // 中心十字线
    final crossPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      position + Offset(-pixelSize / 2, 0),
      position + Offset(pixelSize / 2, 0),
      crossPaint,
    );
    canvas.drawLine(
      position + Offset(0, -pixelSize / 2),
      position + Offset(0, pixelSize / 2),
      crossPaint,
    );

    // 颜色信息文本
    final textPainter = TextPainter(
      text: TextSpan(
        text:
            '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      position + Offset(-textPainter.width / 2, magnifierSize / 2 + 10),
    );
  }

  @override
  bool shouldRepaint(covariant _RasterPainter oldDelegate) {
    // 实时笔画点数变化
    if (currentPointCount != oldDelegate.currentPointCount) return true;

    // 最后一个点位置变化
    if (currentPoints.isNotEmpty && oldDelegate.currentPoints.isNotEmpty) {
      final last = currentPoints.last;
      final oldLast = oldDelegate.currentPoints.last;
      if (last.x != oldLast.x || last.y != oldLast.y) return true;
    }

    // 图层变化（像素引用、可见性、透明度）
    if (layers.length != oldDelegate.layers.length) return true;
    for (var i = 0; i < layers.length; i++) {
      if (i >= oldDelegate.layers.length) return true;
      if (layers[i].isVisible != oldDelegate.layers[i].isVisible) return true;
      if (layers[i].opacity != oldDelegate.layers[i].opacity) return true;
      if (!identical(layers[i].pixels, oldDelegate.layers[i].pixels))
        return true;
    }

    // 活动图层变化
    if (activeLayerIndex != oldDelegate.activeLayerIndex) return true;

    // 待烧录笔画变化
    if (pendingStrokes.length != oldDelegate.pendingStrokes.length) {
      return true;
    }
    for (var i = 0; i < pendingStrokes.length; i++) {
      if (pendingStrokes[i].id != oldDelegate.pendingStrokes[i].id) {
        return true;
      }
    }

    // 笔刷预设变化
    if (!identical(currentPreset, oldDelegate.currentPreset)) return true;

    // 橡皮擦状态/光标变化
    if (isEraser != oldDelegate.isEraser) return true;
    if (eraserCursorPos != oldDelegate.eraserCursorPos) return true;
    if (eraserSize != oldDelegate.eraserSize) return true;

    return false;
  }
}

/// 笔刷系统单例（用于顶层工具函数）
final BrushSystem _brushSystemGlobal = BrushSystem();

/// 烧录结果：包含图像和 RGBA 数据
class BurnResult {
  final ui.Image image;
  final Uint8List rgba;
  BurnResult(this.image, this.rgba);
}

/// 将笔画烧录到图层像素：在现有图层像素上叠加笔画，返回新的 ui.Image 和 RGBA 数据
Future<BurnResult> burnStrokeToLayer({
  required ui.Image? existingPixels,
  required List<DrawPoint> points,
  required BrushPreset preset,
  required int canvasWidth,
  required int canvasHeight,
  bool isEraser = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // 先绘制现有图层像素
  if (existingPixels != null) {
    canvas.drawImage(
      existingPixels,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  // 在上面叠加新笔画（引擎渲染）
  _brushSystemGlobal.renderStroke(canvas, points, preset, isEraser: isEraser);

  final picture = recorder.endRecording();
  final image = await picture.toImage(canvasWidth, canvasHeight);
  picture.dispose();

  // 提取 RGBA 数据
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba =
      byteData?.buffer.asUint8List() ??
      Uint8List(canvasWidth * canvasHeight * 4);

  return BurnResult(image, rgba);
}

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  /// 当前选中的图层索引
  int _selectedLayerIndex = 0;

  String? _hoverTopAction;

  int? _hoverLayerIndex;

  int? _previewLayerIndex;
  LayerPreviewMode _layerPreviewMode = LayerPreviewMode.soloCanvas;

  /// 当前工具
  CanvasTool _currentTool = CanvasTool.brush;

  /// 画布变换控制器（缩放 + 平移）
  final TransformationController _transformController =
      TransformationController();
  static const double _minScale = 0.1;
  static const double _maxScale = 20.0;

  /// 中键拖拽平移状态
  bool _isMiddleButtonPanning = false;
  Offset _middlePanStart = Offset.zero;
  Matrix4 _middlePanStartMatrix = Matrix4.identity();

  /// 移动工具左键拖拽状态
  bool _isMoveToolPanning = false;
  Offset _moveToolPanStart = Offset.zero;
  Matrix4 _moveToolStartMatrix = Matrix4.identity();

  /// 原生压感服务
  final _nativePressure = NativePressureService.instance;
  StreamSubscription<NativePressureData>? _pressureSub;
  bool _nativeSupported = false;

  /// 是否正在烧录笔画到像素（防止并发）
  bool _isBurning = false;
  List<_PendingStroke> _pendingStrokes = const [];

  /// 橡皮擦光标在画布坐标系中的位置（用于实时预览）
  Offset? _eraserCursorCanvasPos;

  /// 颜色吸管：放大镜显示状态
  bool _showMagnifier = false;
  Offset _magnifierPosition = Offset.zero;
  Color _previewColor = Colors.transparent;
  List<List<Color>> _magnifierPixels = []; // 放大镜像素网格 (7x7)
  static const int _magnifierGridSize = 7; // 放大镜网格大小

  /// 放大镜节流：避免数位笔快速移动时卡顿
  bool _magnifierUpdatePending = false;
  Offset? _pendingMagnifierPosition;
  DateTime _lastMagnifierUpdate = DateTime.now();
  static const Duration _magnifierThrottleDuration = Duration(
    milliseconds: 16,
  ); // ~60fps

  /// 缓存图层像素数据，避免重复 toByteData
  ByteData? _cachedPixelData;
  String? _cachedPixelLayerId;
  int? _cachedPixelWidth;
  int? _cachedPixelHeight;

  /// 缓存 _canEditActiveLayer 结果，避免每次指针事件做签名验证
  String? _canEditCachedLayerId;

  /// 工具栏折叠状态
  bool _isToolbarCollapsed = false;
  bool _canEditCachedResult = false;

  /// 缓存压感曲线点列表，避免每次 _extractPressure 重新分配
  List<PressureControlPoint>? _cachedCurvePoints;
  List<PressureCurvePoint>? _lastPressureCurve;

  /// 压感平滑器
  final _pressureSmoother = PressureSmoother();

  /// 起笔压感抬升（ramp）状态
  int? _strokeStartTimestampMs;
  Offset? _strokeStartCanvasPos;

  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _initNativePressure();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    // 添加快捷键监听
    HardwareKeyboard.instance.addHandler(_handleShortcutKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleShortcutKey);
    _lifecycleListener?.dispose();
    _pressureSub?.cancel();
    _transformController.dispose();
    super.dispose();
  }

  /// 处理快捷键
  bool _handleShortcutKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
    final shortcuts = ref.read(shortcutProvider);
    final action = shortcuts.findAction(pressedKeys);

    if (action == null) return false;

    _executeShortcutAction(action);
    return true;
  }

  /// 执行快捷键动作
  Future<void> _executeShortcutAction(ShortcutAction action) async {
    // 切换工具前关闭放大镜
    if (_showMagnifier) {
      setState(() => _showMagnifier = false);
    }

    switch (action) {
      case ShortcutAction.brush:
        setState(() => _currentTool = CanvasTool.brush);
        break;
      case ShortcutAction.eraser:
        setState(() => _currentTool = CanvasTool.eraser);
        break;
      case ShortcutAction.eyedropper:
        setState(() => _currentTool = CanvasTool.eyedropper);
        break;
      case ShortcutAction.move:
        setState(() => _currentTool = CanvasTool.move);
        break;
      case ShortcutAction.undo:
        final drawingState = ref.read(drawingProvider);
        if (drawingState.isDrawing) {
          // 正在绘画时，取消当前渲染预览笔画
          ref.read(drawingProvider.notifier).cancelStroke();
          // 重置压感平滑器/起笔抬升状态
          _pressureSmoother.reset();
          _strokeStartTimestampMs = null;
          _strokeStartCanvasPos = null;
        } else {
          // 执行增量撤回（如果启用）
          final notifier = ref.read(layerProvider.notifier);
          if (notifier.isDeltaMode && notifier.canvasWidth > 0) {
            if (ref.read(connectionProvider).isCollabRoom) {
              await ref.read(connectionProvider.notifier).collabUndoDelta();
            } else {
              await notifier.undoDelta();
            }
          } else {
            notifier.undo();
          }
        }
        break;
      case ShortcutAction.redo:
        final notifier = ref.read(layerProvider.notifier);
        if (notifier.isDeltaMode && notifier.canvasWidth > 0) {
          if (ref.read(connectionProvider).isCollabRoom) {
            await ref.read(connectionProvider.notifier).collabRedoDelta();
          } else {
            await notifier.redoDelta();
          }
        } else {
          notifier.redo();
        }
        break;
      case ShortcutAction.rectangle:
        setState(() => _currentTool = CanvasTool.rectangle);
        break;
      case ShortcutAction.circle:
        setState(() => _currentTool = CanvasTool.circle);
        break;
      case ShortcutAction.line:
        setState(() => _currentTool = CanvasTool.line);
        break;
      case ShortcutAction.fill:
        setState(() {
          if (_currentTool == CanvasTool.fill) {
            _currentTool = CanvasTool.edgeFill;
          } else if (_currentTool == CanvasTool.edgeFill) {
            _currentTool = CanvasTool.fill;
          } else {
            _currentTool = CanvasTool.fill;
          }
        });
        break;
      case ShortcutAction.text:
        setState(() => _currentTool = CanvasTool.text);
        break;
    }
  }

  Future<void> _initNativePressure() async {
    _nativeSupported = await _nativePressure.isSupported();
    if (_nativeSupported) {
      _pressureSub = _nativePressure.pressureStream.listen((_) {});
      debugPrint('✅ 原生压感插件已连接');
    } else {
      debugPrint('⚠️ 原生压感插件不可用');
    }
  }

  /// 窗口关闭拦截：询问是否保存
  Future<ui.AppExitResponse> _onExitRequested() async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出'),
        content: const Text('是否在退出前保存项目？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('不保存'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == 2 || result == null) {
      return ui.AppExitResponse.cancel;
    }

    if (result == 1) {
      final artwork = ref.read(artworkProvider).artwork;
      if (artwork != null) {
        final layerState = ref.read(layerProvider);
        final ok = await ProjectService().saveProjectFile(
          artwork: artwork,
          drawLayers: layerState.layers,
          activeLayerIndex: layerState.activeLayerIndex,
        );
        if (!ok) {
          if (mounted) toast.error(context, '保存失败，请重试');
          return ui.AppExitResponse.cancel;
        }
      }
    }
    return ui.AppExitResponse.exit;
  }

  bool _canEditActiveLayer() {
    final layerState = ref.read(layerProvider);
    final activeDrawLayerId = layerState.activeLayer?.id;
    if (activeDrawLayerId == null) return false;

    final artworkState = ref.read(artworkProvider);
    final authState = ref.read(authProvider);
    if (artworkState.artwork == null) return false;

    domain_layer.Layer? domainLayer;
    try {
      domainLayer = artworkState.layers.firstWhere(
        (l) => l.id == activeDrawLayerId,
      );
    } catch (_) {
      domainLayer = null;
    }

    if (domainLayer == null) {
      // 域图层尚未同步，不缓存此结果（下次重新检查）
      return false;
    }

    // 构建复合缓存键：图层ID + 域图层数量 + 用户名 + 锁定状态 + 权限签名/owner
    // 确保在图层同步、锁定切换、权限变更、用户切换时自动失效
    final cacheKey =
        '$activeDrawLayerId:${artworkState.layers.length}:${authState.username}:'
        '${domainLayer.isLocked}:'
        '${domainLayer.ownerId ?? ''}:'
        '${domainLayer.ownerSignature ?? ''}';
    if (cacheKey == _canEditCachedLayerId) {
      return _canEditCachedResult;
    }

    if (domainLayer.isLocked) {
      _canEditCachedLayerId = cacheKey;
      _canEditCachedResult = false;
      return false;
    }

    final cryptoService = CryptoServiceImpl();
    _canEditCachedResult = domainLayer.canEditWithVerification(
      authState.username,
      authState.privateKey,
      artworkState.artwork!.seed,
      cryptoService.verifyLayerSignature,
    );
    _canEditCachedLayerId = cacheKey;
    return _canEditCachedResult;
  }

  double _extractPressure(PointerEvent event) {
    // 检查压感开关，关闭时返回固定值
    final brush = ref.read(drawingProvider.notifier).brush;
    if (!brush.pressureEnabled) {
      return 1.0;
    }

    final kind = event.kind;
    final min = event.pressureMin;
    final max = event.pressureMax;
    final raw = event.pressure;

    double inputPressure;

    // 原生压感（Wintab）：使用服务缓存值，避免 EventChannel 异步时序问题
    // Wintab 模式下 Flutter 会把数位笔识别为鼠标（pressure 恒为 1.0），
    // 所以必须使用原生压感数据
    final nativeSvc = NativePressureService.instance;
    if ((_nativeSupported || nativeSvc.isSupportedSync) &&
        nativeSvc.hasPressure) {
      inputPressure = nativeSvc.latestPressure.clamp(0.0, 1.0);
    }
    // Flutter 数位笔设备（Windows Ink 模式）
    else if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus) {
      if (max <= min) {
        inputPressure = raw.clamp(0.0, 1.0);
      } else {
        inputPressure = ((raw - min) / (max - min)).clamp(0.0, 1.0);
      }
    }
    // 无压感设备，使用默认值
    else {
      inputPressure = 0.5;
    }

    // 应用压感曲线转换（缓存曲线点列表，避免每次分配）
    if (!identical(_lastPressureCurve, brush.pressureCurve)) {
      _lastPressureCurve = brush.pressureCurve;
      _cachedCurvePoints = brush.pressureCurve
          .map((p) => PressureControlPoint(x: p.x, y: p.y))
          .toList();
    }
    final outputPressure = PressureCurveEditor.calculateOutput(
      _cachedCurvePoints!,
      inputPressure,
    );

    // 应用压感平滑（使用设置中的平滑因子）
    final settings = ref.read(settingsProvider);
    final smoothedPressure = _pressureSmoother.smooth(
      outputPressure,
      settings.pressureSmoothingFactor,
      settings.pressureSmoothing,
    );

    // 起笔压感抬升：在笔画开始的短时间内，从 0.0 逐步过渡到真实压感
    // 用于更容易留下笔锋/起笔尾巴
    if (!settings.pressureStartRamp) {
      return smoothedPressure;
    }

    final strength = settings.pressureStartRampStrength.clamp(0.0, 1.0);
    if (strength <= 0.0) {
      return smoothedPressure;
    }

    final startTs = _strokeStartTimestampMs;
    final startPos = _strokeStartCanvasPos;
    if (startTs == null || startPos == null) {
      return smoothedPressure;
    }

    final rampDurationMs = (30 + 120 * strength).round();
    final rampDistancePx = 8.0 + 40.0 * strength;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final tTime = ((nowMs - startTs) / rampDurationMs).clamp(0.0, 1.0);

    final canvasPos = _viewportToCanvas(event.localPosition);
    final tDist = ((canvasPos - startPos).distance / rampDistancePx).clamp(
      0.0,
      1.0,
    );
    final tLinear = math.max(tTime, tDist);
    final t = tLinear * tLinear;

    return (smoothedPressure * t).clamp(0.0, 1.0);
  }

  /// 视口尺寸（由 LayoutBuilder 更新）
  Size _viewportSize = Size.zero;

  /// 将视口坐标转换为画布坐标（通过逆变换矩阵）
  Offset _viewportToCanvas(Offset viewportPos) {
    final artwork = ref.read(artworkProvider).artwork;
    if (artwork == null) return viewportPos;

    final inverse = Matrix4.tryInvert(_transformController.value);
    if (inverse == null) return viewportPos;

    // 逆变换得到未变换空间坐标
    final untransformed = MatrixUtils.transformPoint(inverse, viewportPos);

    // 画布居中于视口（Center + OverflowBox alignment: center）
    final offsetX = (_viewportSize.width - artwork.width) / 2;
    final offsetY = (_viewportSize.height - artwork.height) / 2;

    return Offset(untransformed.dx - offsetX, untransformed.dy - offsetY);
  }

  /// 处理滚轮缩放（以鼠标位置为焦点，无极缩放）
  void _handleScrollZoom(PointerScrollEvent event) {
    // 无极缩放因子（滚轮单次 ±10%）
    final double scaleFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * scaleFactor).clamp(_minScale, _maxScale);
    if (newScale == currentScale) return;
    final double s = newScale / currentScale;

    // 鼠标在视口中的位置为缩放焦点
    // 公式：M' = T(focal) * S(s) * T(-focal) * M
    final f = event.localPosition;
    final m = _transformController.value.clone();
    // 将焦点平移到原点、缩放、再平移回去
    final result = Matrix4.identity()
      ..translate(f.dx, f.dy)
      ..scale(s, s)
      ..translate(-f.dx, -f.dy)
      ..multiply(m);
    _transformController.value = result;
  }

  /// 颜色吸管：在指定位置拾取颜色
  Future<void> _pickColorAtPosition(Offset localPosition) async {
    try {
      final artworkState = ref.read(artworkProvider);
      final artwork = artworkState.artwork;
      if (artwork == null) return;

      final canvasPos = _viewportToCanvas(localPosition);

      // 检查是否在画布边界内
      if (canvasPos.dx < 0 ||
          canvasPos.dy < 0 ||
          canvasPos.dx >= artwork.width ||
          canvasPos.dy >= artwork.height) {
        // 不在画布内，尝试获取屏幕颜色
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final screenPos = box.localToGlobal(localPosition);
          final screenColor = await _getScreenColor(screenPos);
          if (screenColor != null && mounted) {
            ref.read(drawingProvider.notifier).setColor(screenColor);
            ref.read(brushPresetProvider.notifier).setColor(screenColor);
          }
        }
        return;
      }

      // 使用与放大镜相同的合成图层取色
      final layerState = ref.read(layerProvider);
      final visibleLayers = layerState.visibleLayers;
      if (visibleLayers.isEmpty) return;

      final cacheKey = visibleLayers
          .map((l) => '${l.id}:${l.pixels?.hashCode ?? 0}')
          .join(',');

      ByteData? byteData;
      if (_cachedPixelLayerId == cacheKey &&
          _cachedPixelWidth == artwork.width &&
          _cachedPixelHeight == artwork.height &&
          _cachedPixelData != null) {
        byteData = _cachedPixelData!;
      } else {
        final compositeImage = await _compositeVisibleLayers(
          visibleLayers,
          artwork.width,
          artwork.height,
        );
        if (compositeImage == null) return;
        byteData = await compositeImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        compositeImage.dispose();
        if (byteData != null) {
          _cachedPixelData = byteData;
          _cachedPixelLayerId = cacheKey;
          _cachedPixelWidth = artwork.width;
          _cachedPixelHeight = artwork.height;
        }
      }

      if (byteData == null) return;

      final x = canvasPos.dx.toInt();
      final y = canvasPos.dy.toInt();
      final idx = (y * artwork.width + x) * 4;
      if (idx >= 0 && idx < byteData.lengthInBytes - 3) {
        final color = Color.fromARGB(
          byteData.getUint8(idx + 3),
          byteData.getUint8(idx),
          byteData.getUint8(idx + 1),
          byteData.getUint8(idx + 2),
        );
        if (mounted) {
          ref.read(drawingProvider.notifier).setColor(color);
          ref.read(brushPresetProvider.notifier).setColor(color);
        }
      }
    } catch (e) {
      debugPrint('颜色拾取失败: $e');
    }
  }

  Future<void> _fillAtPosition(Offset localPosition) async {
    if (_isBurning) return;

    final artwork = ref.read(artworkProvider).artwork;
    if (artwork == null) return;

    final canvasPos = _viewportToCanvas(localPosition);
    if (canvasPos.dx < 0 ||
        canvasPos.dy < 0 ||
        canvasPos.dx >= artwork.width ||
        canvasPos.dy >= artwork.height) {
      return;
    }

    if (!_canEditActiveLayer()) {
      return;
    }

    final layerState = ref.read(layerProvider);
    final activeLayer = layerState.activeLayer;
    if (activeLayer == null) return;
    if (activeLayer.isLocked) return;

    setState(() => _isBurning = true);
    try {
      final int width = artwork.width;
      final int height = artwork.height;

      final ui.Image baseImage =
          activeLayer.pixels ?? await _createTransparentImage(width, height);
      final ByteData? byteData = await baseImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (activeLayer.pixels == null) {
        baseImage.dispose();
      }
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final int x0 = canvasPos.dx.toInt();
      final int y0 = canvasPos.dy.toInt();
      final int startIndex = (y0 * width + x0) * 4;
      if (startIndex < 0 || startIndex >= bytes.length - 3) return;

      final int targetR = bytes[startIndex];
      final int targetG = bytes[startIndex + 1];
      final int targetB = bytes[startIndex + 2];
      final int targetA = bytes[startIndex + 3];

      final Color fillColor = ref.read(drawingProvider.notifier).brush.color;
      final int fillR = fillColor.red;
      final int fillG = fillColor.green;
      final int fillB = fillColor.blue;
      final int fillA = fillColor.alpha;

      if (targetR == fillR &&
          targetG == fillG &&
          targetB == fillB &&
          targetA == fillA) {
        return;
      }

      final visited = Uint8List(width * height);
      final queueX = <int>[x0];
      final queueY = <int>[y0];

      bool matchesTarget(int idx) {
        return bytes[idx] == targetR &&
            bytes[idx + 1] == targetG &&
            bytes[idx + 2] == targetB &&
            bytes[idx + 3] == targetA;
      }

      void paintAt(int idx) {
        bytes[idx] = fillR;
        bytes[idx + 1] = fillG;
        bytes[idx + 2] = fillB;
        bytes[idx + 3] = fillA;
      }

      while (queueX.isNotEmpty) {
        final int x = queueX.removeLast();
        final int y = queueY.removeLast();
        if (x < 0 || y < 0 || x >= width || y >= height) continue;

        final int p = y * width + x;
        if (visited[p] != 0) continue;
        visited[p] = 1;

        final int idx = p * 4;
        if (!matchesTarget(idx)) continue;

        paintAt(idx);

        queueX.add(x + 1);
        queueY.add(y);
        queueX.add(x - 1);
        queueY.add(y);
        queueX.add(x);
        queueY.add(y + 1);
        queueX.add(x);
        queueY.add(y - 1);
      }

      final ui.Image newImage = await _imageFromRgbaBytes(bytes, width, height);
      ref.read(layerProvider.notifier).commitImageToActiveLayer(newImage);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() => _isBurning = false);
      } else {
        _isBurning = false;
      }
    }
  }

  Future<void> _edgeFillAtPosition(Offset localPosition) async {
    if (_isBurning) return;

    final artwork = ref.read(artworkProvider).artwork;
    if (artwork == null) return;

    final canvasPos = _viewportToCanvas(localPosition);
    if (canvasPos.dx < 0 ||
        canvasPos.dy < 0 ||
        canvasPos.dx >= artwork.width ||
        canvasPos.dy >= artwork.height) {
      return;
    }

    if (!_canEditActiveLayer()) {
      return;
    }

    final layerState = ref.read(layerProvider);
    final activeLayer = layerState.activeLayer;
    if (activeLayer == null) return;
    if (activeLayer.isLocked) return;
    if (activeLayer.pixels == null) return;

    setState(() => _isBurning = true);
    try {
      final int width = artwork.width;
      final int height = artwork.height;

      final ByteData? byteData = await activeLayer.pixels!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      final int x0 = canvasPos.dx.toInt();
      final int y0 = canvasPos.dy.toInt();
      final int startIndex = (y0 * width + x0) * 4;
      if (startIndex < 0 || startIndex >= bytes.length - 3) return;

      final int targetR = bytes[startIndex];
      final int targetG = bytes[startIndex + 1];
      final int targetB = bytes[startIndex + 2];
      final int targetA = bytes[startIndex + 3];

      final Color strokeColor = ref.read(drawingProvider.notifier).brush.color;
      final int strokeR = strokeColor.red;
      final int strokeG = strokeColor.green;
      final int strokeB = strokeColor.blue;
      final int strokeA = strokeColor.alpha;

      final region = Uint8List(width * height);
      final queueX = <int>[x0];
      final queueY = <int>[y0];

      bool matchesTargetAt(int p) {
        final idx = p * 4;
        return bytes[idx] == targetR &&
            bytes[idx + 1] == targetG &&
            bytes[idx + 2] == targetB &&
            bytes[idx + 3] == targetA;
      }

      while (queueX.isNotEmpty) {
        final int x = queueX.removeLast();
        final int y = queueY.removeLast();
        if (x < 0 || y < 0 || x >= width || y >= height) continue;

        final int p = y * width + x;
        if (region[p] != 0) continue;
        if (!matchesTargetAt(p)) continue;

        region[p] = 1;

        queueX.add(x + 1);
        queueY.add(y);
        queueX.add(x - 1);
        queueY.add(y);
        queueX.add(x);
        queueY.add(y + 1);
        queueX.add(x);
        queueY.add(y - 1);
      }

      // 对连通域外侧 4 邻域打 1px 描边
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int p = y * width + x;
          if (region[p] == 0) continue;

          void paintBorderIfNeeded(int nx, int ny) {
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) return;
            final int np = ny * width + nx;
            if (region[np] != 0) return;
            final int idx = np * 4;
            bytes[idx] = strokeR;
            bytes[idx + 1] = strokeG;
            bytes[idx + 2] = strokeB;
            bytes[idx + 3] = strokeA;
          }

          paintBorderIfNeeded(x + 1, y);
          paintBorderIfNeeded(x - 1, y);
          paintBorderIfNeeded(x, y + 1);
          paintBorderIfNeeded(x, y - 1);
        }
      }

      final ui.Image newImage = await _imageFromRgbaBytes(bytes, width, height);
      ref.read(layerProvider.notifier).commitImageToActiveLayer(newImage);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() => _isBurning = false);
      } else {
        _isBurning = false;
      }
    }
  }

  Future<ui.Image> _createTransparentImage(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0x00000000),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  Future<ui.Image> _imageFromRgbaBytes(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    return completer.future;
  }

  /// 返回键拦截：询问是否保存
  Future<void> _onWillPop(BuildContext context, AppLocalizations l10n) async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出画布'),
        content: const Text('是否在退出前保存项目？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('不保存'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result == 1) {
      // 保存后退出
      final artwork = ref.read(artworkProvider).artwork;
      if (artwork != null) {
        final layerState = ref.read(layerProvider);
        final ok = await ProjectService().saveProjectFile(
          artwork: artwork,
          drawLayers: layerState.layers,
          activeLayerIndex: layerState.activeLayerIndex,
        );
        if (!mounted) return;
        if (ok) {
          Navigator.of(context).pop();
        } else {
          toast.error(context, '保存失败，请重试');
        }
      }
    } else if (result == 0) {
      // 直接退出不保存
      if (mounted) Navigator.of(context).pop();
    }
    // result == 2 or null: cancel, do nothing
  }

  /// 获取屏幕指定位置的颜色（使用原生 Win32 API）
  Future<Color?> _getScreenColor(Offset screenPosition) async {
    return await NativePressureService.instance.getScreenColor(
      screenPosition.dx,
      screenPosition.dy,
    );
  }

  /// 更新预览颜色和放大镜像素网格（带节流和缓存）
  Future<void> _updatePreviewColor(Offset localPosition) async {
    // 节流：限制更新频率
    final now = DateTime.now();
    if (now.difference(_lastMagnifierUpdate) < _magnifierThrottleDuration) {
      // 记录待处理位置，跳过本次更新
      _pendingMagnifierPosition = localPosition;
      if (!_magnifierUpdatePending) {
        _magnifierUpdatePending = true;
        // 延迟处理最后一个位置
        Future.delayed(_magnifierThrottleDuration, () {
          if (_pendingMagnifierPosition != null && mounted) {
            _magnifierUpdatePending = false;
            _doUpdatePreviewColor(_pendingMagnifierPosition!);
          }
        });
      }
      return;
    }
    _lastMagnifierUpdate = now;
    await _doUpdatePreviewColor(localPosition);
  }

  /// 实际执行预览颜色更新
  Future<void> _doUpdatePreviewColor(Offset localPosition) async {
    try {
      final artworkState = ref.read(artworkProvider);
      final artwork = artworkState.artwork;
      if (artwork == null) return;

      final canvasPos = _viewportToCanvas(localPosition);
      final centerX = canvasPos.dx.toInt();
      final centerY = canvasPos.dy.toInt();

      // 检查是否在画布边界内
      if (canvasPos.dx < 0 ||
          canvasPos.dy < 0 ||
          canvasPos.dx >= artwork.width ||
          canvasPos.dy >= artwork.height) {
        setState(() {
          _previewColor = Colors.transparent;
          _magnifierPixels = [];
        });
        return;
      }

      // 合成所有可见图层获取颜色
      final layerState = ref.read(layerProvider);
      final visibleLayers = layerState.visibleLayers;
      if (visibleLayers.isEmpty) return;

      // 生成缓存键（所有可见图层ID+版本）
      final cacheKey = visibleLayers
          .map((l) => '${l.id}:${l.pixels?.hashCode ?? 0}')
          .join(',');

      ByteData byteData;
      int width = artwork.width;
      int height = artwork.height;

      // 检查缓存是否有效
      if (_cachedPixelLayerId == cacheKey &&
          _cachedPixelWidth == width &&
          _cachedPixelHeight == height &&
          _cachedPixelData != null) {
        byteData = _cachedPixelData!;
      } else {
        // 合成所有可见图层到一个图像
        final compositeImage = await _compositeVisibleLayers(
          visibleLayers,
          width,
          height,
        );
        if (compositeImage == null) return;

        final newData = await compositeImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        compositeImage.dispose();
        if (newData == null) return;
        byteData = newData;

        // 更新缓存
        _cachedPixelData = byteData;
        _cachedPixelLayerId = cacheKey;
        _cachedPixelWidth = width;
        _cachedPixelHeight = height;
      }

      final half = _magnifierGridSize ~/ 2;

      // 获取中心像素颜色
      final centerIndex = (centerY * width + centerX) * 4;
      Color centerColor = Colors.transparent;
      if (centerIndex >= 0 && centerIndex < byteData.lengthInBytes - 3) {
        centerColor = Color.fromARGB(
          byteData.getUint8(centerIndex + 3),
          byteData.getUint8(centerIndex),
          byteData.getUint8(centerIndex + 1),
          byteData.getUint8(centerIndex + 2),
        );
      }

      // 获取周围像素网格
      final List<List<Color>> pixels = [];
      for (int dy = -half; dy <= half; dy++) {
        final List<Color> row = [];
        for (int dx = -half; dx <= half; dx++) {
          final px = centerX + dx;
          final py = centerY + dy;
          if (px >= 0 && px < width && py >= 0 && py < height) {
            final index = (py * width + px) * 4;
            if (index >= 0 && index < byteData.lengthInBytes - 3) {
              row.add(
                Color.fromARGB(
                  byteData.getUint8(index + 3),
                  byteData.getUint8(index),
                  byteData.getUint8(index + 1),
                  byteData.getUint8(index + 2),
                ),
              );
            } else {
              row.add(Colors.transparent);
            }
          } else {
            row.add(Colors.grey.shade300); // 画布外显示灰色
          }
        }
        pixels.add(row);
      }

      if (mounted) {
        setState(() {
          _previewColor = centerColor;
          _magnifierPixels = pixels;
        });
      }
    } catch (e) {
      debugPrint('预览颜色更新失败: $e');
    }
  }

  /// 合成所有可见图层到一个图像
  Future<ui.Image?> _compositeVisibleLayers(
    List<DrawLayer> layers,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 白色背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );

    // 按顺序绘制所有可见图层
    for (final layer in layers) {
      if (layer.pixels != null && layer.isVisible) {
        final paint = Paint()..filterQuality = FilterQuality.none;
        if (layer.opacity < 1.0) {
          paint.color = Color.fromRGBO(255, 255, 255, layer.opacity);
        }
        canvas.drawImage(layer.pixels!, Offset.zero, paint);
      }
    }

    final picture = recorder.endRecording();
    return await picture.toImage(width, height);
  }

  /// 将笔画烧录到活动图层的像素缓冲
  Future<void> _burnStroke(List<DrawPoint> points) async {
    if (_isBurning) return;
    final artworkState = ref.read(artworkProvider);
    final artwork = artworkState.artwork;
    if (artwork == null) return;

    final presetState = ref.read(brushPresetProvider);
    final layerState = ref.read(layerProvider);
    final activeLayer = layerState.activeLayer;
    if (activeLayer == null) return;

    // 协同模式下，非本人图层拒绝绘制
    final pool = ref.read(connectionProvider);
    if (pool.isCollabRoom && activeLayer.ownerId.isNotEmpty) {
      final currentUsername = ref.read(authProvider).username;
      if (activeLayer.ownerId != currentUsername) return;
    }

    // 确保画布尺寸已设置（用于增量计算）
    final layerNotifier = ref.read(layerProvider.notifier);
    if (layerNotifier.canvasWidth != artwork.width ||
        layerNotifier.canvasHeight != artwork.height) {
      layerNotifier.setCanvasSize(artwork.width, artwork.height);
    }

    final isEraserMode = _currentTool == CanvasTool.eraser;
    final pending = _PendingStroke(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      layerId: activeLayer.id,
      points: List<DrawPoint>.from(points),
      preset: presetState.currentPreset,
      isEraser: isEraserMode,
    );

    _isBurning = true;
    if (mounted) {
      setState(() {
        _pendingStrokes = [..._pendingStrokes, pending];
      });
    }

    try {
      final result = await burnStrokeToLayer(
        existingPixels: activeLayer.pixels,
        points: pending.points,
        preset: pending.preset,
        canvasWidth: artwork.width,
        canvasHeight: artwork.height,
        isEraser: pending.isEraser,
      );

      if (mounted) {
        // 使用增量提交（如果启用）
        if (layerNotifier.isDeltaMode) {
          final layerIndex = layerState.layers.indexWhere(
            (l) => l.id == pending.layerId,
          );
          final deltaStep = await layerNotifier.commitImageWithDelta(
            layerIndex: layerIndex,
            newImage: result.image,
            newRgba: result.rgba,
          );
          final pool = ref.read(connectionProvider);
          final roomId = pool.currentRoomId;
          int? roomTypeCode;
          if (roomId != null) {
            for (final r in pool.rooms) {
              final rid = (r as dynamic).roomId as String?;
              if (rid != null && rid.toLowerCase() == roomId.toLowerCase()) {
                roomTypeCode = (r as dynamic).roomTypeCode as int?;
                break;
              }
            }
          }
          if (roomId != null && roomTypeCode == 0x02 && deltaStep != null) {
            final activeLayerId = ref.read(layerProvider).activeLayer?.id;
            if (activeLayerId != null) {
              ref
                  .read(connectionProvider.notifier)
                  .sendCollabLayerDeltaStep(activeLayerId, deltaStep);
            }
          }
        } else {
          // 降级到旧版提交
          layerNotifier.commitImageToLayer(pending.layerId, result.image);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingStrokes = _pendingStrokes
              .where((p) => p.id != pending.id)
              .toList();
        });
      }
      _isBurning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final artworkState = ref.watch(artworkProvider);
    final l10n = AppLocalizations.of(context);

    // 监听错误消息
    ref.listen<ArtworkState>(artworkProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage!.isNotEmpty) {
        toast.error(context, next.errorMessage!);
        ref.read(artworkProvider.notifier).clearError();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop(context, l10n);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leadingWidth: 80,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: kToolbarHeight,
                child: Center(
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hoverTopAction = 'back'),
                    onExit: (_) {
                      if (_hoverTopAction == 'back') {
                        setState(() => _hoverTopAction = null);
                      }
                    },
                    child: Material(
                      type: MaterialType.circle,
                      elevation: _hoverTopAction == 'back' ? 4 : 0,
                      color: _hoverTopAction == 'back'
                          ? Theme.of(context).colorScheme.surface
                          : Colors.transparent,
                      shadowColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => _onWillPop(context, l10n),
                        tooltip: l10n.translate('back'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                height: kToolbarHeight,
                child: Center(
                  child: Builder(
                    builder: (context) {
                      final isOverlayMode =
                          _layerPreviewMode == LayerPreviewMode.overlayBox;
                      return MouseRegion(
                        onEnter: (_) =>
                            setState(() => _hoverTopAction = 'preview'),
                        onExit: (_) {
                          if (_hoverTopAction == 'preview') {
                            setState(() => _hoverTopAction = null);
                          }
                        },
                        child: Material(
                          type: MaterialType.circle,
                          elevation: _hoverTopAction == 'preview' ? 4 : 0,
                          color: _hoverTopAction == 'preview'
                              ? Theme.of(context).colorScheme.surface
                              : Colors.transparent,
                          shadowColor: Colors.black54,
                          child: IconButton(
                            icon: Icon(
                              isOverlayMode
                                  ? Icons.crop_square
                                  : Icons.layers_clear,
                            ),
                            onPressed: () {
                              setState(() {
                                _layerPreviewMode = isOverlayMode
                                    ? LayerPreviewMode.soloCanvas
                                    : LayerPreviewMode.overlayBox;
                              });
                            },
                            tooltip: isOverlayMode ? '预览框' : '只显示图层',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 40,
                              height: 40,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          titleSpacing: 0,
          title: Builder(
            builder: (context) {
              final layers = artworkState.layers;
              if (layers.isEmpty) return const SizedBox.shrink();

              final activeIndex = ref.watch(layerProvider).activeLayerIndex;

              final inactiveColor = Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
              final activeColor = Theme.of(context).colorScheme.primary;

              return SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 2),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < layers.length; i++)
                                MouseRegion(
                                  onEnter: (_) {
                                    ref
                                        .read(layerProvider.notifier)
                                        .setActiveLayerIndex(i);
                                    setState(() {
                                      _hoverLayerIndex = i;
                                      _selectedLayerIndex = i;
                                      _previewLayerIndex = i;
                                    });
                                  },
                                  onExit: (_) {
                                    if (_hoverLayerIndex == i ||
                                        _previewLayerIndex == i) {
                                      setState(() {
                                        if (_hoverLayerIndex == i) {
                                          _hoverLayerIndex = null;
                                        }
                                        if (_previewLayerIndex == i) {
                                          _previewLayerIndex = null;
                                        }
                                      });
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Center(
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 100,
                                        ),
                                        curve: Curves.easeOut,
                                        width:
                                            (i == activeIndex ||
                                                i == _hoverLayerIndex)
                                            ? 4
                                            : 2,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color:
                                              (i == activeIndex ||
                                                  i == _hoverLayerIndex)
                                              ? activeColor
                                              : inactiveColor,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            SizedBox(
              width: 40,
              height: kToolbarHeight,
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoverTopAction = 'undo'),
                  onExit: (_) {
                    if (_hoverTopAction == 'undo') {
                      setState(() => _hoverTopAction = null);
                    }
                  },
                  child: Material(
                    type: MaterialType.circle,
                    elevation: _hoverTopAction == 'undo' ? 4 : 0,
                    color: _hoverTopAction == 'undo'
                        ? Theme.of(context).colorScheme.surface
                        : Colors.transparent,
                    shadowColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.undo),
                      onPressed: ref.watch(layerProvider).canUndo
                          ? () async {
                              final drawingState = ref.read(drawingProvider);
                              if (drawingState.isDrawing) {
                                // 正在绘画时，取消当前渲染预览笔画
                                ref
                                    .read(drawingProvider.notifier)
                                    .cancelStroke();
                              } else {
                                // 执行增量撤回（如果启用）
                                final notifier = ref.read(
                                  layerProvider.notifier,
                                );
                                if (notifier.isDeltaMode &&
                                    notifier.canvasWidth > 0) {
                                  if (ref
                                      .read(connectionProvider)
                                      .isCollabRoom) {
                                    await ref
                                        .read(connectionProvider.notifier)
                                        .collabUndoDelta();
                                  } else {
                                    await notifier.undoDelta();
                                  }
                                } else {
                                  notifier.undo();
                                }
                              }
                            }
                          : null,
                      tooltip: l10n.translate('undo'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              height: kToolbarHeight,
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoverTopAction = 'redo'),
                  onExit: (_) {
                    if (_hoverTopAction == 'redo') {
                      setState(() => _hoverTopAction = null);
                    }
                  },
                  child: Material(
                    type: MaterialType.circle,
                    elevation: _hoverTopAction == 'redo' ? 4 : 0,
                    color: _hoverTopAction == 'redo'
                        ? Theme.of(context).colorScheme.surface
                        : Colors.transparent,
                    shadowColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.redo),
                      onPressed: ref.watch(layerProvider).canRedo
                          ? () async {
                              final notifier = ref.read(layerProvider.notifier);
                              if (notifier.isDeltaMode &&
                                  notifier.canvasWidth > 0) {
                                if (ref.read(connectionProvider).isCollabRoom) {
                                  await ref
                                      .read(connectionProvider.notifier)
                                      .collabRedoDelta();
                                } else {
                                  await notifier.redoDelta();
                                }
                              } else {
                                notifier.redo();
                              }
                            }
                          : null,
                      tooltip: l10n.translate('redo'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              height: kToolbarHeight,
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoverTopAction = 'save'),
                  onExit: (_) {
                    if (_hoverTopAction == 'save') {
                      setState(() => _hoverTopAction = null);
                    }
                  },
                  child: Material(
                    type: MaterialType.circle,
                    elevation: _hoverTopAction == 'save' ? 4 : 0,
                    color: _hoverTopAction == 'save'
                        ? Theme.of(context).colorScheme.surface
                        : Colors.transparent,
                    shadowColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.save),
                      onPressed: () {
                        final artwork = ref.read(artworkProvider).artwork;
                        if (artwork == null ||
                            !ref.read(artworkProvider).isInitialized) {
                          toast.error(
                            context,
                            l10n.translate('canvas_not_loaded'),
                          );
                          return;
                        }

                        final layerState = ref.read(layerProvider);
                        final projectService = ProjectService();

                        projectService
                            .saveProjectFile(
                              artwork: artwork,
                              drawLayers: layerState.layers,
                              activeLayerIndex: layerState.activeLayerIndex,
                            )
                            .then((ok) {
                              if (!context.mounted) return;
                              if (ok) {
                                toast.success(context, l10n.translate('save'));
                              } else {
                                toast.error(
                                  context,
                                  '${l10n.translate('save')}: failed',
                                );
                              }
                            })
                            .catchError((e) {
                              if (!context.mounted) return;
                              toast.error(
                                context,
                                '${l10n.translate('save')}: $e',
                              );
                            });
                      },
                      tooltip: l10n.translate('save'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              height: kToolbarHeight,
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoverTopAction = 'export'),
                  onExit: (_) {
                    if (_hoverTopAction == 'export') {
                      setState(() => _hoverTopAction = null);
                    }
                  },
                  child: Material(
                    type: MaterialType.circle,
                    elevation: _hoverTopAction == 'export' ? 4 : 0,
                    color: _hoverTopAction == 'export'
                        ? Theme.of(context).colorScheme.surface
                        : Colors.transparent,
                    shadowColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: () => _showExportDialog(context, l10n),
                      tooltip: l10n.translate('export'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              height: kToolbarHeight,
              child: Center(
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoverTopAction = 'settings'),
                  onExit: (_) {
                    if (_hoverTopAction == 'settings') {
                      setState(() => _hoverTopAction = null);
                    }
                  },
                  child: Material(
                    type: MaterialType.circle,
                    elevation: _hoverTopAction == 'settings' ? 4 : 0,
                    color: _hoverTopAction == 'settings'
                        ? Theme.of(context).colorScheme.surface
                        : Colors.transparent,
                    shadowColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () =>
                          _showDrawingSettingsDialog(context, l10n),
                      tooltip: l10n.translate('drawing_settings'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
        body: Stack(
          children: [
            // 中间画布区域（支持缩放 + 平移 + 绘画）
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewportSize = constraints.biggest;
                  return Stack(
                    children: [
                      MouseRegion(
                        cursor: _currentTool == CanvasTool.eraser
                            ? SystemMouseCursors.none
                            : (_currentTool == CanvasTool.eyedropper
                                  ? SystemMouseCursors.precise
                                  : SystemMouseCursors.basic),
                        onHover: (event) {
                          if (_currentTool == CanvasTool.eraser &&
                              artworkState.isInitialized) {
                            setState(() {
                              _eraserCursorCanvasPos = _viewportToCanvas(
                                event.localPosition,
                              );
                            });
                          }
                          // 颜色吸管：跟踪位置并显示放大镜
                          if (_currentTool == CanvasTool.eyedropper &&
                              artworkState.isInitialized) {
                            setState(() {
                              _magnifierPosition = event.localPosition;
                              _showMagnifier = true;
                            });
                            _updatePreviewColor(event.localPosition);
                          }
                        },
                        onExit: (_) {
                          if (_eraserCursorCanvasPos != null) {
                            setState(() => _eraserCursorCanvasPos = null);
                          }
                          if (_showMagnifier) {
                            setState(() => _showMagnifier = false);
                          }
                        },
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerSignal: (event) {
                            if (event is PointerScrollEvent &&
                                artworkState.isInitialized) {
                              _handleScrollZoom(event);
                            }
                          },
                          onPointerDown: (event) {
                            if (event.buttons == kMiddleMouseButton) {
                              _isMiddleButtonPanning = true;
                              _middlePanStart = event.position;
                              _middlePanStartMatrix = _transformController.value
                                  .clone();
                              return;
                            }
                            if (_currentTool == CanvasTool.move &&
                                event.buttons == kPrimaryButton) {
                              _isMoveToolPanning = true;
                              _moveToolPanStart = event.position;
                              _moveToolStartMatrix = _transformController.value
                                  .clone();
                              return;
                            }
                            if (_currentTool == CanvasTool.fill &&
                                event.buttons == kPrimaryButton &&
                                artworkState.isInitialized) {
                              _fillAtPosition(event.localPosition);
                              return;
                            }
                            if (_currentTool == CanvasTool.edgeFill &&
                                event.buttons == kPrimaryButton &&
                                artworkState.isInitialized) {
                              _edgeFillAtPosition(event.localPosition);
                              return;
                            }
                            if (_currentTool == CanvasTool.eyedropper &&
                                event.buttons == kPrimaryButton &&
                                artworkState.isInitialized) {
                              // 显示放大镜并更新预览
                              setState(() {
                                _magnifierPosition = event.localPosition;
                                _showMagnifier = true;
                              });
                              _updatePreviewColor(event.localPosition);
                              _pickColorAtPosition(event.localPosition);
                              return;
                            }
                            if (event.buttons == kPrimaryButton &&
                                artworkState.isInitialized) {
                              if (!_canEditActiveLayer()) {
                                final msg =
                                    l10n.translate('no_permission').isNotEmpty
                                    ? l10n.translate('no_permission')
                                    : '无权限编辑此图层';
                                toast.error(context, msg);
                                return;
                              }
                              final canvasPos = _viewportToCanvas(
                                event.localPosition,
                              );
                              _strokeStartTimestampMs =
                                  DateTime.now().millisecondsSinceEpoch;
                              _strokeStartCanvasPos = canvasPos;
                              final pressure = _extractPressure(event);
                              ref
                                  .read(drawingProvider.notifier)
                                  .startStroke(canvasPos, pressure: pressure);
                            }
                          },
                          onPointerMove: (event) {
                            if (_isMiddleButtonPanning) {
                              final delta = event.position - _middlePanStart;
                              final result = Matrix4.identity()
                                ..translate(delta.dx, delta.dy)
                                ..multiply(_middlePanStartMatrix);
                              _transformController.value = result;
                            } else if (_isMoveToolPanning) {
                              final delta = event.position - _moveToolPanStart;
                              final result = Matrix4.identity()
                                ..translate(delta.dx, delta.dy)
                                ..multiply(_moveToolStartMatrix);
                              _transformController.value = result;
                            } else if (ref.read(drawingProvider).isDrawing) {
                              final canvasPos = _viewportToCanvas(
                                event.localPosition,
                              );
                              final pressure = _extractPressure(event);
                              ref
                                  .read(drawingProvider.notifier)
                                  .addPoint(canvasPos, pressure: pressure);
                            }
                            if (_currentTool == CanvasTool.eraser &&
                                artworkState.isInitialized) {
                              setState(() {
                                _eraserCursorCanvasPos = _viewportToCanvas(
                                  event.localPosition,
                                );
                              });
                            }
                            // 颜色吸管：数位笔/触摸跟随
                            if (_currentTool == CanvasTool.eyedropper &&
                                artworkState.isInitialized) {
                              setState(() {
                                _magnifierPosition = event.localPosition;
                                _showMagnifier = true;
                              });
                              _updatePreviewColor(event.localPosition);
                            }
                          },
                          onPointerUp: (event) {
                            if (_isMiddleButtonPanning || _isMoveToolPanning) {
                              _isMiddleButtonPanning = false;
                              _isMoveToolPanning = false;
                              return;
                            }
                            if (ref.read(drawingProvider).isDrawing) {
                              final points = ref
                                  .read(drawingProvider.notifier)
                                  .endStroke();
                              // 重置压感平滑器
                              _pressureSmoother.reset();
                              // 重置起笔抬升状态
                              _strokeStartTimestampMs = null;
                              _strokeStartCanvasPos = null;
                              if (points.isNotEmpty) {
                                _burnStroke(points);
                              }
                            }
                            if (_currentTool == CanvasTool.eyedropper) {
                              setState(() => _showMagnifier = false);
                            }
                          },
                          child: Container(
                            color: const Color(0xFF2D2D2D),
                            child: ClipRect(
                              child: AnimatedBuilder(
                                animation: _transformController,
                                builder: (context, child) {
                                  return Transform(
                                    transform: _transformController.value,
                                    alignment: Alignment.topLeft,
                                    child: child,
                                  );
                                },
                                child: Center(
                                  child: artworkState.isInitialized
                                      ? OverflowBox(
                                          alignment: Alignment.center,
                                          minWidth: 0,
                                          minHeight: 0,
                                          maxWidth: double.infinity,
                                          maxHeight: double.infinity,
                                          child: Container(
                                            width: artworkState.artwork!.width
                                                .toDouble(),
                                            height: artworkState.artwork!.height
                                                .toDouble(),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(
                                                color: Colors.grey,
                                              ),
                                            ),
                                            child: Consumer(
                                              builder: (context, ref, child) {
                                                final drawingState = ref.watch(
                                                  drawingProvider,
                                                );
                                                final layerState = ref.watch(
                                                  layerProvider,
                                                );
                                                final presetState = ref.watch(
                                                  brushPresetProvider,
                                                );
                                                return RepaintBoundary(
                                                  child: Builder(
                                                    builder: (context) {
                                                      final preset = presetState
                                                          .currentPreset;

                                                      final previewIndex =
                                                          _previewLayerIndex;
                                                      final isSoloPreview =
                                                          previewIndex !=
                                                              null &&
                                                          _layerPreviewMode ==
                                                              LayerPreviewMode
                                                                  .soloCanvas;

                                                      final painterLayers =
                                                          isSoloPreview &&
                                                              previewIndex >=
                                                                  0 &&
                                                              previewIndex <
                                                                  layerState
                                                                      .layers
                                                                      .length
                                                          ? <DrawLayer>[
                                                              layerState
                                                                  .layers[previewIndex],
                                                            ]
                                                          : layerState
                                                                .visibleLayers;
                                                      final painterActiveIndex =
                                                          isSoloPreview
                                                          ? 0
                                                          : layerState
                                                                .activeLayerIndex;
                                                      return CustomPaint(
                                                        painter: _RasterPainter(
                                                          layers: painterLayers,
                                                          currentPoints:
                                                              drawingState
                                                                  .currentPoints,
                                                          currentPointCount:
                                                              drawingState
                                                                  .pointCount,
                                                          activeLayerIndex:
                                                              painterActiveIndex,
                                                          currentPreset: preset,
                                                          pendingStrokes:
                                                              _pendingStrokes,
                                                          isEraser:
                                                              _currentTool ==
                                                              CanvasTool.eraser,
                                                          eraserCursorPos:
                                                              _eraserCursorCanvasPos,
                                                          eraserSize:
                                                              preset
                                                                  .pressureEnabled
                                                              ? preset.baseSize *
                                                                    2.0
                                                              : preset.baseSize,
                                                          showMagnifier: false,
                                                          magnifierPosition:
                                                              _magnifierPosition,
                                                          previewColor:
                                                              _previewColor,
                                                        ),
                                                        size: Size.infinite,
                                                      );
                                                    },
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        )
                                      : Text(
                                          l10n.translate('canvas_not_loaded'),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 放大镜覆盖层
                      if (_showMagnifier)
                        Positioned(
                          left: _magnifierPosition.dx + 20,
                          top: _magnifierPosition.dy - 60,
                          child: IgnorePointer(child: _buildMagnifierWidget()),
                        ),

                      if (_previewLayerIndex != null &&
                          _layerPreviewMode == LayerPreviewMode.overlayBox &&
                          artworkState.isInitialized)
                        Positioned(
                          top: 8,
                          left: 0,
                          right: 120,
                          child: IgnorePointer(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Builder(
                                builder: (context) {
                                  final art = artworkState.artwork;
                                  if (art == null) {
                                    return const SizedBox.shrink();
                                  }

                                  final layerState = ref.watch(layerProvider);
                                  final drawingState = ref.watch(
                                    drawingProvider,
                                  );
                                  final presetState = ref.watch(
                                    brushPresetProvider,
                                  );

                                  final previewIndex = _previewLayerIndex!;
                                  if (previewIndex < 0 ||
                                      previewIndex >=
                                          layerState.layers.length) {
                                    return const SizedBox.shrink();
                                  }

                                  const previewWidth = 400.0;
                                  final ratio =
                                      art.width.toDouble() /
                                      art.height.toDouble();
                                  final previewHeight = (previewWidth / ratio)
                                      .clamp(180.0, 440.0);

                                  return Container(
                                    width: previewWidth,
                                    height: previewHeight,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.18,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: SizedBox(
                                        width: art.width.toDouble(),
                                        height: art.height.toDouble(),
                                        child: CustomPaint(
                                          painter: _RasterPainter(
                                            layers: [
                                              layerState.layers[previewIndex],
                                            ],
                                            currentPoints:
                                                drawingState.currentPoints,
                                            currentPointCount:
                                                drawingState.pointCount,
                                            activeLayerIndex: 0,
                                            currentPreset:
                                                presetState.currentPreset,
                                            pendingStrokes: _pendingStrokes,
                                            isEraser:
                                                _currentTool ==
                                                CanvasTool.eraser,
                                            eraserCursorPos:
                                                _eraserCursorCanvasPos,
                                            eraserSize:
                                                presetState
                                                    .currentPreset
                                                    .pressureEnabled
                                                ? presetState
                                                          .currentPreset
                                                          .baseSize *
                                                      2.0
                                                : presetState
                                                      .currentPreset
                                                      .baseSize,
                                            showMagnifier: false,
                                            magnifierPosition:
                                                _magnifierPosition,
                                            previewColor: _previewColor,
                                          ),
                                          size: Size.infinite,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // 右侧面板
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 240,
              child: Column(
                children: [
                  // 颜色选择器
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.translate('panel_color'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        // HSV 颜色选择器
                        Center(
                          child: HsvColorPicker(
                            color: ref
                                .watch(brushPresetProvider)
                                .currentPreset
                                .color,
                            onColorChanged: (color) {
                              ref
                                  .read(drawingProvider.notifier)
                                  .setColor(color);
                              ref
                                  .read(brushPresetProvider.notifier)
                                  .setColor(color);
                            },
                            width: 180, // 放大色轮尺寸
                            height: 180,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 笔刷选择器面板
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    child: const BrushSelectorPanel(),
                  ),

                  const Divider(height: 1),

                  // 图层面板
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final pool = ref.watch(connectionProvider);
                        final roomId = pool.currentRoomId;
                        bool isCollab = false;
                        if (roomId != null) {
                          for (final r in pool.rooms) {
                            final rid = (r as dynamic).roomId as String?;
                            if (rid != null &&
                                rid.toLowerCase() == roomId.toLowerCase()) {
                              isCollab =
                                  ((r as dynamic).roomTypeCode as int?) == 0x02;
                              break;
                            }
                          }
                        }
                        return LayerPanel(
                          selectedLayerIndex: _selectedLayerIndex,
                          onLayerSelected: (index) {
                            setState(() {
                              _selectedLayerIndex = index;
                            });
                          },
                          l10n: l10n,
                          toast: toast,
                          isCollabRoom: isCollab,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // 左侧工具栏（浮动定位，带动画）
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: _isToolbarCollapsed ? -48 : 0,
              top: 0,
              bottom: 0,
              width: 48,
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildToolButton(
                        context,
                        Icons.brush,
                        l10n.translate('tool_brush'),
                        CanvasTool.brush,
                      ),
                      _buildToolButton(
                        context,
                        Icons.delete_outline,
                        l10n.translate('tool_eraser'),
                        CanvasTool.eraser,
                      ),
                      _buildToolButton(
                        context,
                        Icons.colorize,
                        l10n.translate('tool_eyedropper'),
                        CanvasTool.eyedropper,
                      ),
                      _buildToolButton(
                        context,
                        Icons.pan_tool,
                        l10n.translate('tool_move'),
                        CanvasTool.move,
                      ),
                      _buildToolButton(
                        context,
                        Icons.near_me,
                        l10n.translate('tool_select'),
                        CanvasTool.select,
                      ),
                      const Divider(),
                      _buildToolButton(
                        context,
                        Icons.rectangle_outlined,
                        l10n.translate('tool_rectangle'),
                        CanvasTool.rectangle,
                      ),
                      _buildToolButton(
                        context,
                        Icons.circle_outlined,
                        l10n.translate('tool_circle'),
                        CanvasTool.circle,
                      ),
                      _buildToolButton(
                        context,
                        Icons.horizontal_rule,
                        l10n.translate('tool_line'),
                        CanvasTool.line,
                      ),
                      const Divider(),
                      _buildToolButton(
                        context,
                        Icons.format_paint,
                        l10n.translate('tool_fill'),
                        CanvasTool.fill,
                      ),
                      _buildToolButton(
                        context,
                        Icons.border_outer,
                        l10n.translate('tool_edge_fill'),
                        CanvasTool.edgeFill,
                      ),
                      _buildToolButton(
                        context,
                        Icons.text_fields,
                        l10n.translate('tool_text'),
                        CanvasTool.text,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 快速调节滑条（浮动定位，带动画）
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: _isToolbarCollapsed ? 0 : 48,
              top: 0,
              bottom: 0,
              child: _buildQuickSliders(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建放大镜预览 Widget
  Widget _buildMagnifierWidget() {
    return MagnifierWidget(
      gridSize: _magnifierGridSize,
      pixels: _magnifierPixels,
      previewColor: _previewColor,
    );
  }

  /// 构建快速调节滑条（笔刷粗细和透明度）
  Widget _buildQuickSliders(BuildContext context) {
    final presetState = ref.watch(brushPresetProvider);
    final currentPreset = presetState.currentPreset;
    final theme = Theme.of(context);

    final curveExp = ref.watch(brushSizeCurveExponentProvider);

    double toUi(double actual, double min, double max) {
      final t = ((actual - min) / (max - min)).clamp(0.0, 1.0);
      return math.pow(t, 1.0 / curveExp).toDouble();
    }

    double toActual(double ui, double min, double max) {
      final t = ui.clamp(0.0, 1.0);
      return min + (max - min) * math.pow(t, curveExp).toDouble();
    }

    // 根据当前工具获取对应图标
    final toolIcon = _currentTool.icon;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 当前工具图标
          _currentTool == CanvasTool.brush
              ? MenuAnchor(
                  builder: (context, controller, child) {
                    return GestureDetector(
                      onTap: () {
                        if (controller.isOpen) {
                          controller.close();
                        } else {
                          controller.open();
                        }
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primaryContainer,
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          toolIcon,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    );
                  },
                  menuChildren: [_buildBrushMenuItems(context)],
                  alignmentOffset: const Offset(4, 0),
                )
              : Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primaryContainer,
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    toolIcon,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
          const SizedBox(height: 8),
          // 折叠/展开按钮
          GestureDetector(
            onTap: () =>
                setState(() => _isToolbarCollapsed = !_isToolbarCollapsed),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                _isToolbarCollapsed ? Icons.chevron_right : Icons.chevron_left,
                size: 18,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 笔刷粗细滑条
          VerticalSlider(
            value: toUi(currentPreset.baseSize, 1, 100),
            min: 0,
            max: 1,
            icon: Icons.brush,
            label: '粗细',
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
          const SizedBox(height: 16),
          // 透明度滑条
          VerticalSlider(
            value: currentPreset.baseOpacity,
            min: 0.01,
            max: 1.0,
            icon: Icons.opacity,
            label: '透明度',
            displayText: '${(currentPreset.baseOpacity * 100).toInt()}%',
            onChanged: (v) {
              ref.read(brushPresetProvider.notifier).setBaseOpacity(v);
              ref.read(drawingProvider.notifier).setOpacity(v);
              ref.read(brushProvider.notifier).setOpacity(v);
            },
          ),
        ],
      ),
    );
  }

  /// 构建工具按钮
  Widget _buildToolButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    CanvasTool tool, {
    GlobalKey? buttonKey,
  }) {
    final isActive = _currentTool == tool;

    // 笔刷按钮使用 MenuAnchor
    if (tool == CanvasTool.brush) {
      return Tooltip(
        message: tooltip,
        child: MenuAnchor(
          builder: (context, controller, child) {
            return Container(
              key: buttonKey,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              child: IconButton(
                icon: Icon(icon),
                onPressed: () {
                  setState(() => _currentTool = tool);
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
              ),
            );
          },
          menuChildren: [_buildBrushMenuItems(context)],
          alignmentOffset: const Offset(4, 0),
        ),
      );
    }

    // 其他工具按钮
    return Tooltip(
      message: tooltip,
      child: Container(
        key: buttonKey,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
        ),
        child: IconButton(
          icon: Icon(icon),
          onPressed: () {
            setState(() => _currentTool = tool);
          },
        ),
      ),
    );
  }

  /// 构建笔刷菜单项
  Widget _buildBrushMenuItems(BuildContext context) {
    return BrushMenuItems(engineMeta: _engineMeta);
  }

  /// 显示导出对话框
  void _showExportDialog(BuildContext context, AppLocalizations l10n) {
    final artworkState = ref.read(artworkProvider);
    if (!artworkState.isInitialized || artworkState.artwork == null) {
      toast.error(context, l10n.translate('canvas_not_loaded'));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出图像'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('选择导出格式：'),
            const SizedBox(height: 16),
            _ExportFormatButton(
              label: 'PNG（无损）',
              icon: Icons.image,
              onTap: () {
                Navigator.pop(ctx);
                _exportImage('png', l10n);
              },
            ),
            const SizedBox(height: 8),
            _ExportFormatButton(
              label: 'JPEG（有损压缩）',
              icon: Icons.photo,
              onTap: () {
                Navigator.pop(ctx);
                _exportImage('jpg', l10n);
              },
            ),
            const SizedBox(height: 8),
            _ExportFormatButton(
              label: 'BMP（位图）',
              icon: Icons.grid_on,
              onTap: () {
                Navigator.pop(ctx);
                _exportImage('bmp', l10n);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 导出图像到文件
  Future<void> _exportImage(String format, AppLocalizations l10n) async {
    try {
      final artworkState = ref.read(artworkProvider);
      final artwork = artworkState.artwork;
      if (artwork == null) return;

      final layerState = ref.read(layerProvider);
      final visibleLayers = layerState.visibleLayers;

      // 合成所有可见图层
      final compositeImage = await _compositeVisibleLayers(
        visibleLayers,
        artwork.width,
        artwork.height,
      );
      if (compositeImage == null) return;

      // 获取 RGBA 原始数据
      final rawBytes = await compositeImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      compositeImage.dispose();
      if (rawBytes == null) return;

      final width = artwork.width;
      final height = artwork.height;

      // 使用 image 包编码
      final imgLib = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rawBytes.buffer,
        numChannels: 4,
      );

      Uint8List encoded;
      String ext;
      switch (format) {
        case 'jpg':
          encoded = Uint8List.fromList(img.encodeJpg(imgLib, quality: 95));
          ext = 'jpg';
          break;
        case 'bmp':
          encoded = Uint8List.fromList(img.encodeBmp(imgLib));
          ext = 'bmp';
          break;
        default:
          encoded = Uint8List.fromList(img.encodePng(imgLib));
          ext = 'png';
      }

      // 选择保存路径
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出图像',
        fileName: '${artwork.name}.$ext',
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (savePath == null) return;

      final outPath = savePath.endsWith('.$ext') ? savePath : '$savePath.$ext';
      await File(outPath).writeAsBytes(encoded);

      if (mounted) {
        toast.success(context, '已导出：$outPath');
      }
    } catch (e) {
      debugPrint('导出失败: $e');
      if (mounted) {
        toast.error(context, '导出失败: $e');
      }
    }
  }

  /// 显示绘画设置对话框
  void _showDrawingSettingsDialog(BuildContext context, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => DrawingSettingsDialog(l10n: l10n),
    );
  }
}

/// 导出格式按钮
class _ExportFormatButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ExportFormatButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
