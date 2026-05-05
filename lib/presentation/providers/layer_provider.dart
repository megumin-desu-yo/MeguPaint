import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/delta/region_delta.dart';
import '../../services/network/tcp_client_service.dart'
    show CollabLayerOpType, CollabMultiLayerSnapshot;

/// 撤销步骤：保存单个图层的上一次像素快照（旧版，保留兼容）
class UndoStep {
  final int layerIndex;
  final ui.Image? previousImage;

  UndoStep(this.layerIndex, this.previousImage);

  void dispose() {
    previousImage?.dispose();
  }
}

/// 绘制图层（像素模式，区别于 domain/entities/layer.dart 的权限图层）
class DrawLayer {
  final String id;
  final String name;
  final ui.Image? pixels; // 光栅像素数据（null 表示空/透明图层）
  final double opacity; // 0.0 - 1.0
  final bool isVisible;
  final bool isLocked;
  final BlendMode blendMode;

  /// 图层所有者（协同模式）：空字符串表示公共图层，非空时仅该用户可编辑
  final String ownerId;

  DrawLayer({
    required this.id,
    required this.name,
    this.pixels,
    this.opacity = 1.0,
    this.isVisible = true,
    this.isLocked = false,
    this.blendMode = BlendMode.srcOver,
    this.ownerId = '',
  });

  DrawLayer copyWith({
    String? id,
    String? name,
    ui.Image? pixels,
    bool clearPixels = false,
    double? opacity,
    bool? isVisible,
    bool? isLocked,
    BlendMode blendMode = BlendMode.srcOver,
    bool useDefaultBlendMode = false,
    String? ownerId,
  }) {
    return DrawLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      pixels: clearPixels ? null : (pixels ?? this.pixels),
      opacity: opacity ?? this.opacity,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      blendMode: useDefaultBlendMode ? blendMode : (this.blendMode),
      ownerId: ownerId ?? this.ownerId,
    );
  }

  /// 序列化元数据（像素数据由 ProjectService 单独处理）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'opacity': opacity,
      'isVisible': isVisible,
      'isLocked': isLocked,
      'blendMode': blendMode.index,
    };
  }

  factory DrawLayer.fromMap(Map<String, dynamic> map) {
    return DrawLayer(
      id: map['id'] as String,
      name: map['name'] as String,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
      isVisible: map['isVisible'] as bool? ?? true,
      isLocked: map['isLocked'] as bool? ?? false,
      blendMode: BlendMode.values[(map['blendMode'] as num?)?.toInt() ?? 0],
    );
  }
}

/// 图层状态
class LayerState {
  final List<DrawLayer> layers;
  final int activeLayerIndex; // 当前活动图层索引
  final bool canUndo;
  final bool canRedo;

  const LayerState({
    this.layers = const [],
    this.activeLayerIndex = 0,
    this.canUndo = false,
    this.canRedo = false,
  });

  /// 获取活动图层
  DrawLayer? get activeLayer {
    if (layers.isEmpty || activeLayerIndex >= layers.length) return null;
    return layers[activeLayerIndex];
  }

  /// 获取所有可见图层（直接返回 layers，由 painter 跳过不可见图层，避免每帧分配新列表）
  List<DrawLayer> get visibleLayers => layers;

  LayerState copyWith({
    List<DrawLayer>? layers,
    int? activeLayerIndex,
    bool? canUndo,
    bool? canRedo,
  }) {
    return LayerState(
      layers: layers ?? this.layers,
      activeLayerIndex: activeLayerIndex ?? this.activeLayerIndex,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
    );
  }
}

/// 图层管理器（像素模式）
class LayerNotifier extends StateNotifier<LayerState> {
  LayerNotifier() : super(const LayerState());

  // ========== 旧版撤销/重做栈（保留兼容） ==========
  final List<UndoStep> _undoStack = [];
  final List<UndoStep> _redoStack = [];
  static const int _maxUndoSteps = 30;

  // ========== 增量撤销/重做栈（新版） ==========
  final List<UndoRegionDeltaStep> _undoDeltaStack = [];
  final List<UndoRegionDeltaStep> _redoDeltaStack = [];
  static const int _maxDeltaSteps = 50; // 增量模式下可支持更多步数

  // ========== RGBA 缓存（避免重复 toByteData） ==========
  /// 图层 RGBA 缓存：layerId -> RGBA 数据
  final Map<String, Uint8List> _layerRgbaCache = {};

  /// 图层版本号：layerId -> revision
  final Map<String, int> _layerRevision = {};

  /// 画布尺寸（用于增量计算）
  int _canvasWidth = 0;
  int _canvasHeight = 0;

  /// 是否启用增量模式（默认启用）
  bool _useDeltaMode = true;

  // ========== 协同状态（A2：服务端托管） ==========
  int _collabEpoch = 0;
  int _collabRev = 0;

  int get collabEpoch => _collabEpoch;
  int get collabRev => _collabRev;

  void advanceCollabRevOnLocalDelta() {
    _collabRev += 1;
  }

  /// 协同多图层：本地发送 layerDelta 后推进该层 per-layer revision
  void advanceLayerRevOnLocalDelta(String layerId) {
    _layerRevision[layerId] = (_layerRevision[layerId] ?? 0) + 1;
  }

  // ========== 画布尺寸管理 ==========

  /// 设置画布尺寸（必须在提交图像前调用）
  void setCanvasSize(int width, int height) {
    _canvasWidth = width;
    _canvasHeight = height;
  }

  /// 获取画布尺寸
  int get canvasWidth => _canvasWidth;
  int get canvasHeight => _canvasHeight;

  Uint8List _decodeMaybeZlib(Uint8List data, bool isCompressed) {
    if (!isCompressed) return data;
    return Uint8List.fromList(zlib.decode(data));
  }

  void _xorApplyDeltaInPlace({
    required Uint8List canvasRgba,
    required int x,
    required int y,
    required int width,
    required int height,
    required Uint8List deltaRgba,
  }) {
    final canvasStride = _canvasWidth * 4;
    final rowBytes = width * 4;
    int deltaOffset = 0;
    int canvasOffset = (y * canvasStride) + (x * 4);
    for (int row = 0; row < height; row++) {
      for (int i = 0; i < rowBytes; i++) {
        canvasRgba[canvasOffset + i] ^= deltaRgba[deltaOffset + i];
      }
      deltaOffset += rowBytes;
      canvasOffset += canvasStride;
    }
  }

  /// 协同：收到远端 delta 广播并应用到 layer0
  ///
  /// 返回 true 表示成功应用；false 表示版本/尺寸不匹配，需要 sync。
  Future<bool> applyCollabDeltaBroadcast({
    required int epoch,
    required int rev,
    required int x,
    required int y,
    required int width,
    required int height,
    required int flags,
    required Uint8List payload,
  }) async {
    if (_canvasWidth <= 0 || _canvasHeight <= 0) return false;

    if (epoch != _collabEpoch) return false;
    if (rev != _collabRev + 1) return false;

    if (x < 0 || y < 0) return false;
    if (x + width > _canvasWidth) return false;
    if (y + height > _canvasHeight) return false;

    final layer = state.layers.isNotEmpty ? state.layers[0] : null;
    if (layer == null) return false;
    final layerId = layer.id;

    Uint8List rgba =
        _layerRgbaCache[layerId] ?? Uint8List(_canvasWidth * _canvasHeight * 4);

    final isCompressed = (flags & 0x01) != 0;
    final deltaRgba = _decodeMaybeZlib(payload, isCompressed);
    final expected = width * height * 4;
    if (deltaRgba.length != expected) return false;

    _xorApplyDeltaInPlace(
      canvasRgba: rgba,
      x: x,
      y: y,
      width: width,
      height: height,
      deltaRgba: deltaRgba,
    );

    final img = await _rgbaToImage(rgba, _canvasWidth, _canvasHeight);
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[0] = layer.copyWith(pixels: img);
    state = state.copyWith(layers: newLayers);

    _layerRgbaCache[layerId] = rgba;
    _collabRev = rev;
    return true;
  }

  /// 协同：应用服务端快照（整图替换）
  Future<void> applyCollabSnapshotFromServer({
    required int epoch,
    required int rev,
    required int width,
    required int height,
    required int flags,
    required Uint8List rgbaZlib,
  }) async {
    setCanvasSize(width, height);

    final isCompressed = (flags & 0x01) != 0;
    final rgba = _decodeMaybeZlib(rgbaZlib, isCompressed);
    if (rgba.length != width * height * 4) {
      return;
    }

    if (state.layers.isEmpty) {
      initializeWithDefaultLayer();
    }
    final layer = state.layers[0];
    final layerId = layer.id;

    final img = await _rgbaToImage(rgba, width, height);
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[0] = layer.copyWith(pixels: img);
    state = state.copyWith(layers: newLayers);

    _layerRgbaCache[layerId] = Uint8List.fromList(rgba);
    _collabEpoch = epoch;
    _collabRev = rev;
  }

  /// 协同：强制进入需要同步状态（用于画布尺寸变化等场景）
  void forceCollabNeedSync() {
    _collabRev = -1;
  }

  // ========== 多图层协同方法 ==========

  /// 协同：处理图层操作广播（DrawLayer 侧）
  void applyCollabLayerOp(
    CollabLayerOpType opType,
    Map<String, dynamic> payload,
  ) {
    switch (opType) {
      case CollabLayerOpType.add:
        final layerId = payload['layerId'] as String?;
        final name = payload['name'] as String? ?? '';
        if (layerId == null) return;
        if (state.layers.any((l) => l.id == layerId)) return;
        final opacity = (payload['opacity'] as num?)?.toDouble() ?? 1.0;
        final isVisible = payload['isVisible'] as bool? ?? true;
        final isLocked = payload['isLocked'] as bool? ?? false;
        final blendModeIdx = (payload['blendMode'] as num?)?.toInt() ?? 0;
        final ownerIdAdd = payload['ownerId'] as String? ?? '';
        final newLayer = DrawLayer(
          id: layerId,
          name: name,
          opacity: opacity,
          isVisible: isVisible,
          isLocked: isLocked,
          blendMode: BlendMode
              .values[blendModeIdx.clamp(0, BlendMode.values.length - 1)],
          ownerId: ownerIdAdd,
        );
        state = state.copyWith(
          layers: [...state.layers, newLayer],
          activeLayerIndex: state.layers.length,
        );
        // 初始化该层 RGBA 缓存（全透明）
        if (_canvasWidth > 0 && _canvasHeight > 0) {
          _layerRgbaCache[layerId] = Uint8List(
            _canvasWidth * _canvasHeight * 4,
          );
          _layerRevision[layerId] = 0;
        }
        break;

      case CollabLayerOpType.remove:
        final layerId = payload['layerId'] as String?;
        if (layerId == null) return;
        removeLayerById(layerId);
        _layerRgbaCache.remove(layerId);
        _layerRevision.remove(layerId);
        break;

      case CollabLayerOpType.rename:
        final layerId = payload['layerId'] as String?;
        final name = payload['name'] as String?;
        if (layerId == null || name == null) return;
        updateLayerById(layerId, name: name);
        break;

      case CollabLayerOpType.reorder:
        final order = (payload['order'] as List?)?.cast<String>();
        if (order == null) return;
        final map = {for (final l in state.layers) l.id: l};
        final reordered = <DrawLayer>[];
        for (final id in order) {
          final l = map[id];
          if (l != null) reordered.add(l);
        }
        for (final l in state.layers) {
          if (!reordered.contains(l)) reordered.add(l);
        }
        // 保持当前活动图层
        final activeId = state.activeLayer?.id;
        int newActiveIndex = 0;
        if (activeId != null) {
          newActiveIndex = reordered.indexWhere((l) => l.id == activeId);
          if (newActiveIndex < 0) newActiveIndex = 0;
        }
        state = state.copyWith(
          layers: reordered,
          activeLayerIndex: newActiveIndex,
        );
        break;

      case CollabLayerOpType.setVisibility:
        final layerId = payload['layerId'] as String?;
        final isVisible = payload['isVisible'] as bool?;
        if (layerId == null || isVisible == null) return;
        updateLayerById(layerId, isVisible: isVisible);
        break;

      case CollabLayerOpType.setOpacity:
        final layerId = payload['layerId'] as String?;
        final opacity = (payload['opacity'] as num?)?.toDouble();
        if (layerId == null || opacity == null) return;
        updateLayerById(layerId, opacity: opacity);
        break;

      case CollabLayerOpType.setLock:
        final layerId = payload['layerId'] as String?;
        final isLocked = payload['isLocked'] as bool?;
        if (layerId == null || isLocked == null) return;
        updateLayerById(layerId, isLocked: isLocked);
        break;
    }
  }

  /// 协同：收到带 layerId 的远端 delta 广播并应用
  Future<bool> applyCollabLayerDeltaBroadcast({
    required String layerId,
    required int epoch,
    required int rev,
    required int x,
    required int y,
    required int width,
    required int height,
    required int flags,
    required Uint8List payload,
  }) async {
    if (_canvasWidth <= 0 || _canvasHeight <= 0) return false;
    if (epoch != _collabEpoch) return false;

    // 找到目标图层
    final layerIdx = state.layers.indexWhere((l) => l.id == layerId);
    if (layerIdx < 0) return false;
    final layer = state.layers[layerIdx];

    // per-layer rev 校验
    final currentLayerRev = _layerRevision[layerId] ?? 0;
    if (rev != currentLayerRev + 1) return false;

    if (x < 0 || y < 0) return false;
    if (x + width > _canvasWidth) return false;
    if (y + height > _canvasHeight) return false;

    Uint8List rgba =
        _layerRgbaCache[layerId] ?? Uint8List(_canvasWidth * _canvasHeight * 4);

    final isCompressed = (flags & 0x01) != 0;
    final deltaRgba = _decodeMaybeZlib(payload, isCompressed);
    final expected = width * height * 4;
    if (deltaRgba.length != expected) return false;

    _xorApplyDeltaInPlace(
      canvasRgba: rgba,
      x: x,
      y: y,
      width: width,
      height: height,
      deltaRgba: deltaRgba,
    );

    final img = await _rgbaToImage(rgba, _canvasWidth, _canvasHeight);
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[layerIdx] = layer.copyWith(pixels: img);
    state = state.copyWith(layers: newLayers);

    _layerRgbaCache[layerId] = rgba;
    _layerRevision[layerId] = rev;
    return true;
  }

  /// 协同：应用多图层快照（完整替换所有图层状态）
  Future<void> applyCollabMultiLayerSnapshot(
    CollabMultiLayerSnapshot snap,
  ) async {
    setCanvasSize(snap.canvasWidth, snap.canvasHeight);
    _collabEpoch = snap.epoch;

    final newLayers = <DrawLayer>[];
    _layerRgbaCache.clear();
    _layerRevision.clear();

    for (final entry in snap.layers) {
      final isCompressed = (entry.rgbaFlags & 0x01) != 0;
      final rgba = _decodeMaybeZlib(entry.rgbaBytes, isCompressed);
      final expectedSize = snap.canvasWidth * snap.canvasHeight * 4;

      ui.Image? img;
      Uint8List layerRgba;
      if (rgba.length == expectedSize) {
        img = await _rgbaToImage(rgba, snap.canvasWidth, snap.canvasHeight);
        layerRgba = Uint8List.fromList(rgba);
      } else {
        layerRgba = Uint8List(expectedSize);
      }

      final blendModeIdx = entry.blendMode.clamp(
        0,
        BlendMode.values.length - 1,
      );
      newLayers.add(
        DrawLayer(
          id: entry.layerId,
          name: entry.name,
          pixels: img,
          opacity: entry.opacity / 255.0,
          isVisible: entry.isVisible,
          isLocked: entry.isLocked,
          blendMode: BlendMode.values[blendModeIdx],
          ownerId: entry.ownerId,
        ),
      );

      _layerRgbaCache[entry.layerId] = layerRgba;
      _layerRevision[entry.layerId] = entry.rev;
    }

    state = state.copyWith(
      layers: newLayers,
      activeLayerIndex: newLayers.isNotEmpty ? newLayers.length - 1 : 0,
    );
  }

  // ========== RGBA 缓存管理 ==========

  /// 获取图层的 RGBA 缓存（如果不存在则返回 null）
  Uint8List? getLayerRgba(String layerId) => _layerRgbaCache[layerId];

  /// 设置图层的 RGBA 缓存
  void setLayerRgba(String layerId, Uint8List rgba) {
    _layerRgbaCache[layerId] = rgba;
    _layerRevision[layerId] = (_layerRevision[layerId] ?? 0) + 1;
  }

  /// 清除图层的 RGBA 缓存
  void clearLayerRgbaCache(String layerId) {
    _layerRgbaCache.remove(layerId);
    _layerRevision.remove(layerId);
  }

  /// 清除所有 RGBA 缓存
  void clearAllRgbaCache() {
    _layerRgbaCache.clear();
    _layerRevision.clear();
  }

  /// 获取图层的版本号
  int getLayerRevision(String layerId) => _layerRevision[layerId] ?? 0;

  // ========== 增量模式切换 ==========

  /// 启用/禁用增量模式
  void setDeltaMode(bool enabled) {
    _useDeltaMode = enabled;
  }

  /// 是否处于增量模式
  bool get isDeltaMode => _useDeltaMode;

  /// 创建新图层
  void addLayer({String? name}) {
    final newId = 'layer_${DateTime.now().millisecondsSinceEpoch}';
    final newLayer = DrawLayer(
      id: newId,
      name: name ?? '图层 ${state.layers.length + 1}',
    );

    state = state.copyWith(
      layers: [...state.layers, newLayer],
      activeLayerIndex: state.layers.length, // 新图层成为活动图层
    );
  }

  void addLayerWithId({required String id, required String name}) {
    if (state.layers.any((l) => l.id == id)) {
      return;
    }

    final newLayer = DrawLayer(id: id, name: name);
    state = state.copyWith(
      layers: [...state.layers, newLayer],
      activeLayerIndex: state.layers.length,
    );
  }

  /// 删除图层
  void removeLayer(int index) {
    if (index < 0 || index >= state.layers.length) return;
    if (state.layers.length <= 1) return; // 至少保留一个图层

    final newLayers = List<DrawLayer>.from(state.layers)..removeAt(index);

    // 调整活动图层索引
    int newActiveIndex = state.activeLayerIndex;
    if (newActiveIndex >= newLayers.length) {
      newActiveIndex = newLayers.length - 1;
    } else if (index < newActiveIndex) {
      newActiveIndex--;
    }

    state = state.copyWith(layers: newLayers, activeLayerIndex: newActiveIndex);
  }

  /// 选择活动图层
  void selectLayer(int index) {
    if (index < 0 || index >= state.layers.length) return;
    state = state.copyWith(activeLayerIndex: index);
  }

  void setActiveLayerIndex(int index) {
    selectLayer(index);
  }

  void updateLayerById(
    String id, {
    String? name,
    double? opacity,
    bool? isVisible,
    bool? isLocked,
    BlendMode? blendMode,
  }) {
    final idx = state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    updateLayer(
      idx,
      name: name,
      opacity: opacity,
      isVisible: isVisible,
      isLocked: isLocked,
      blendMode: blendMode,
    );
  }

  void removeLayerById(String id) {
    final idx = state.layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    removeLayer(idx);
  }

  /// 将渲染好的像素图像提交到活动图层（替代 addStrokeToActiveLayer）
  void commitImageToActiveLayer(ui.Image newImage) {
    _commitImageAt(state.activeLayerIndex, newImage);
  }

  /// 将像素图像提交到指定 ID 的图层（用于异步烧录队列）
  void commitImageToLayer(String layerId, ui.Image newImage) {
    final index = state.layers.indexWhere((l) => l.id == layerId);
    if (index < 0) return;
    _commitImageAt(index, newImage);
  }

  void _commitImageAt(int index, ui.Image newImage) {
    if (index < 0 || index >= state.layers.length) return;
    final targetLayer = state.layers[index];
    if (targetLayer.isLocked) return;

    _pushUndo(index, targetLayer.pixels?.clone());

    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[index] = targetLayer.copyWith(pixels: newImage);

    state = state.copyWith(
      layers: newLayers,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  // ========== 增量提交方法（新版） ==========

  /// 将渲染好的像素图像提交到指定图层（增量模式）
  ///
  /// 需要提供新图像的 RGBA 数据，用于计算增量。
  /// 如果未提供 newRgba，会自动从 newImage 提取（较慢）。
  Future<UndoRegionDeltaStep?> commitImageWithDelta({
    required int layerIndex,
    required ui.Image newImage,
    Uint8List? newRgba,
  }) async {
    if (layerIndex < 0 || layerIndex >= state.layers.length) return null;
    final targetLayer = state.layers[state.activeLayerIndex];
    if (targetLayer.isLocked) return null;

    // 画布尺寸检查
    if (_canvasWidth <= 0 || _canvasHeight <= 0) {
      // 降级到旧版提交
      _commitImageAt(layerIndex, newImage);
      return null;
    }

    final layerId = targetLayer.id;

    // 获取旧 RGBA（从缓存或从图像提取）
    Uint8List? oldRgba = _layerRgbaCache[layerId];
    if (oldRgba == null && targetLayer.pixels != null) {
      oldRgba = await _imageToRgba(targetLayer.pixels!);
    }

    // 获取新 RGBA
    final actualNewRgba = newRgba ?? await _imageToRgba(newImage);

    // 计算增量
    final rawStep = createDeltaStep(
      layerIndex: layerIndex,
      oldRgba: oldRgba,
      newRgba: actualNewRgba,
      canvasWidth: _canvasWidth,
      canvasHeight: _canvasHeight,
      revision: _layerRevision[layerId] ?? 0,
    );
    // 注入 layerId（协同模式使用）
    final deltaStep = rawStep == null
        ? null
        : UndoRegionDeltaStep(
            layerIndex: rawStep.layerIndex,
            layerId: layerId,
            x: rawStep.x,
            y: rawStep.y,
            width: rawStep.width,
            height: rawStep.height,
            delta: rawStep.delta,
            canvasWidth: rawStep.canvasWidth,
            canvasHeight: rawStep.canvasHeight,
            revision: rawStep.revision,
            originalSize: rawStep.originalSize,
            changedPixels: rawStep.changedPixels,
            isCompressed: rawStep.isCompressed,
          );

    if (deltaStep != null) {
      // 存入增量 undo 栈
      _pushUndoDelta(deltaStep);
    }

    // 更新图层像素
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[layerIndex] = targetLayer.copyWith(pixels: newImage);

    // 更新 RGBA 缓存
    _layerRgbaCache[layerId] = Uint8List.fromList(actualNewRgba);

    state = state.copyWith(
      layers: newLayers,
      canUndo: _undoDeltaStack.isNotEmpty || _undoStack.isNotEmpty,
      canRedo: _redoDeltaStack.isNotEmpty || _redoStack.isNotEmpty,
    );

    return deltaStep;
  }

  /// 将图像转换为 RGBA 数据
  Future<Uint8List> _imageToRgba(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return Uint8List(_canvasWidth * _canvasHeight * 4);
    }
    return byteData.buffer.asUint8List();
  }

  /// 将 RGBA 数据转换为图像
  Future<ui.Image> _rgbaToImage(Uint8List rgba, int width, int height) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// 压入增量撤销栈
  void _pushUndoDelta(UndoRegionDeltaStep step) {
    _undoDeltaStack.add(step);

    // 超出上限时清理最早的
    while (_undoDeltaStack.length > _maxDeltaSteps) {
      _undoDeltaStack.removeAt(0);
    }

    // 清空增量重做栈
    _redoDeltaStack.clear();
  }

  /// 增量撤销，返回被撤销的原始 step（协同模式用于向服务端发送逆操作）
  Future<UndoRegionDeltaStep?> undoDelta() async {
    if (_undoDeltaStack.isEmpty) return null;

    final step = _undoDeltaStack.removeLast();
    if (step.layerIndex < 0 || step.layerIndex >= state.layers.length) {
      _syncUndoRedoFlags();
      return null;
    }

    final currentLayer = state.layers[step.layerIndex];
    final layerId = step.layerId ?? currentLayer.id;

    // 获取当前 RGBA
    Uint8List? currentRgba = _layerRgbaCache[layerId];
    if (currentRgba == null && currentLayer.pixels != null) {
      currentRgba = await _imageToRgba(currentLayer.pixels!);
    }
    if (currentRgba == null) {
      currentRgba = Uint8List(_canvasWidth * _canvasHeight * 4);
    }

    // 应用增量恢复旧像素
    final oldRgba = applyRegionDelta(currentRgba, _canvasWidth, step);

    // 转换为图像
    final oldImage = await _rgbaToImage(oldRgba, _canvasWidth, _canvasHeight);

    // 计算反向增量存入重做栈（携带 layerId）
    final reverseDelta = computeRegionDelta(
      oldRgba,
      currentRgba,
      _canvasWidth,
      step.rect,
    );
    _redoDeltaStack.add(
      UndoRegionDeltaStep(
        layerIndex: step.layerIndex,
        layerId: layerId,
        x: step.x,
        y: step.y,
        width: step.width,
        height: step.height,
        delta: reverseDelta,
        canvasWidth: _canvasWidth,
        canvasHeight: _canvasHeight,
        revision: step.revision + 1,
        originalSize: reverseDelta.length,
        changedPixels: step.changedPixels,
      ),
    );

    // 更新图层
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[step.layerIndex] = currentLayer.copyWith(pixels: oldImage);

    // 更新缓存
    _layerRgbaCache[layerId] = Uint8List.fromList(oldRgba);

    state = state.copyWith(
      layers: newLayers,
      canUndo: _undoDeltaStack.isNotEmpty || _undoStack.isNotEmpty,
      canRedo: _redoDeltaStack.isNotEmpty || _redoStack.isNotEmpty,
    );

    // 返回原始 step（delta 是 XOR 自逆，原样再发即可撤回）
    return UndoRegionDeltaStep(
      layerIndex: step.layerIndex,
      layerId: layerId,
      x: step.x,
      y: step.y,
      width: step.width,
      height: step.height,
      delta: step.delta,
      canvasWidth: _canvasWidth,
      canvasHeight: _canvasHeight,
      revision: step.revision,
      originalSize: step.originalSize,
      changedPixels: step.changedPixels,
      isCompressed: step.isCompressed,
    );
  }

  /// 增量重做，返回被重做的 step（协同模式用于向服务端发送正向操作）
  Future<UndoRegionDeltaStep?> redoDelta() async {
    if (_redoDeltaStack.isEmpty) return null;

    final step = _redoDeltaStack.removeLast();
    if (step.layerIndex < 0 || step.layerIndex >= state.layers.length) {
      _syncUndoRedoFlags();
      return null;
    }

    final currentLayer = state.layers[step.layerIndex];
    final layerId = step.layerId ?? currentLayer.id;

    // 获取当前 RGBA
    Uint8List? currentRgba = _layerRgbaCache[layerId];
    if (currentRgba == null && currentLayer.pixels != null) {
      currentRgba = await _imageToRgba(currentLayer.pixels!);
    }
    if (currentRgba == null) {
      currentRgba = Uint8List(_canvasWidth * _canvasHeight * 4);
    }

    // 应用增量恢复新像素
    final newRgba = applyRegionDelta(currentRgba, _canvasWidth, step);

    // 转换为图像
    final newImage = await _rgbaToImage(newRgba, _canvasWidth, _canvasHeight);

    // 计算反向增量存入撤销栈（携带 layerId）
    final reverseDelta = computeRegionDelta(
      newRgba,
      currentRgba,
      _canvasWidth,
      step.rect,
    );
    _undoDeltaStack.add(
      UndoRegionDeltaStep(
        layerIndex: step.layerIndex,
        layerId: layerId,
        x: step.x,
        y: step.y,
        width: step.width,
        height: step.height,
        delta: reverseDelta,
        canvasWidth: _canvasWidth,
        canvasHeight: _canvasHeight,
        revision: step.revision - 1,
        originalSize: reverseDelta.length,
        changedPixels: step.changedPixels,
      ),
    );

    // 更新图层
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[step.layerIndex] = currentLayer.copyWith(pixels: newImage);

    // 更新缓存
    _layerRgbaCache[layerId] = Uint8List.fromList(newRgba);

    state = state.copyWith(
      layers: newLayers,
      canUndo: _undoDeltaStack.isNotEmpty || _undoStack.isNotEmpty,
      canRedo: _redoDeltaStack.isNotEmpty || _redoStack.isNotEmpty,
    );

    // 返回 step（delta 是 XOR 自逆，原样再发即重做）
    return UndoRegionDeltaStep(
      layerIndex: step.layerIndex,
      layerId: layerId,
      x: step.x,
      y: step.y,
      width: step.width,
      height: step.height,
      delta: step.delta,
      canvasWidth: _canvasWidth,
      canvasHeight: _canvasHeight,
      revision: step.revision,
      originalSize: step.originalSize,
      changedPixels: step.changedPixels,
      isCompressed: step.isCompressed,
    );
  }

  /// 撤销
  void undo() {
    if (_undoStack.isEmpty) return;

    final step = _undoStack.removeLast();
    if (step.layerIndex < 0 || step.layerIndex >= state.layers.length) {
      step.dispose();
      _syncUndoRedoFlags();
      return;
    }

    // 保存当前像素到重做栈
    final currentLayer = state.layers[step.layerIndex];
    _redoStack.add(UndoStep(step.layerIndex, currentLayer.pixels?.clone()));

    // 恢复旧像素
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[step.layerIndex] = currentLayer.copyWith(
      pixels: step.previousImage,
      clearPixels: step.previousImage == null,
    );

    state = state.copyWith(
      layers: newLayers,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  /// 重做
  void redo() {
    if (_redoStack.isEmpty) return;

    final step = _redoStack.removeLast();
    if (step.layerIndex < 0 || step.layerIndex >= state.layers.length) {
      step.dispose();
      _syncUndoRedoFlags();
      return;
    }

    // 保存当前像素到撤销栈（不清空重做栈）
    final currentLayer = state.layers[step.layerIndex];
    _undoStack.add(UndoStep(step.layerIndex, currentLayer.pixels?.clone()));

    // 恢复新像素
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[step.layerIndex] = currentLayer.copyWith(
      pixels: step.previousImage,
      clearPixels: step.previousImage == null,
    );

    state = state.copyWith(
      layers: newLayers,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  /// 压入撤销栈并清空重做栈
  void _pushUndo(int layerIndex, ui.Image? previousImage) {
    _undoStack.add(UndoStep(layerIndex, previousImage));

    // 超出上限时清理最早的
    while (_undoStack.length > _maxUndoSteps) {
      _undoStack.removeAt(0).dispose();
    }

    // 清空重做栈
    for (final step in _redoStack) {
      step.dispose();
    }
    _redoStack.clear();
  }

  /// 同步撤销/重做标志到状态
  void _syncUndoRedoFlags() {
    state = state.copyWith(
      canUndo: _undoStack.isNotEmpty || _undoDeltaStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty || _redoDeltaStack.isNotEmpty,
    );
  }

  /// 更新图层属性
  void updateLayer(
    int index, {
    String? name,
    double? opacity,
    bool? isVisible,
    bool? isLocked,
    BlendMode? blendMode,
  }) {
    if (index < 0 || index >= state.layers.length) return;

    final layer = state.layers[index];
    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[index] = DrawLayer(
      id: layer.id,
      name: name ?? layer.name,
      pixels: layer.pixels,
      opacity: opacity ?? layer.opacity,
      isVisible: isVisible ?? layer.isVisible,
      isLocked: isLocked ?? layer.isLocked,
      blendMode: blendMode ?? layer.blendMode,
    );

    state = state.copyWith(layers: newLayers);
  }

  /// 移动图层顺序
  void moveLayer(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= state.layers.length) return;
    if (toIndex < 0 || toIndex >= state.layers.length) return;

    final newLayers = List<DrawLayer>.from(state.layers);
    final layer = newLayers.removeAt(fromIndex);
    newLayers.insert(toIndex, layer);

    // 调整活动图层索引
    int newActiveIndex = state.activeLayerIndex;
    if (fromIndex == newActiveIndex) {
      newActiveIndex = toIndex;
    } else if (fromIndex < newActiveIndex && toIndex >= newActiveIndex) {
      newActiveIndex--;
    } else if (fromIndex > newActiveIndex && toIndex <= newActiveIndex) {
      newActiveIndex++;
    }

    state = state.copyWith(layers: newLayers, activeLayerIndex: newActiveIndex);
  }

  /// 合并图层（像素合成）
  /// [currentIndex] 当前图层索引
  /// [targetIndex] 目标图层索引（要合并的图层）
  /// 合并后保留当前图层，移除目标图层
  /// 需要提供画布尺寸用于合成
  Future<bool> mergeLayers(
    int currentIndex,
    int targetIndex, {
    required int canvasWidth,
    required int canvasHeight,
  }) async {
    if (currentIndex < 0 || currentIndex >= state.layers.length) return false;
    if (targetIndex < 0 || targetIndex >= state.layers.length) return false;
    if (currentIndex == targetIndex) return false;

    final currentLayer = state.layers[currentIndex];
    final targetLayer = state.layers[targetIndex];

    // 像素合成：先绘制目标图层（下层），再绘制当前图层（上层）
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (targetLayer.pixels != null) {
      canvas.drawImage(
        targetLayer.pixels!,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    if (currentLayer.pixels != null) {
      canvas.drawImage(
        currentLayer.pixels!,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
    final picture = recorder.endRecording();
    final mergedImage = await picture.toImage(canvasWidth, canvasHeight);
    picture.dispose();

    // 创建合并后的图层
    final mergedLayer = currentLayer.copyWith(
      pixels: mergedImage,
      opacity: currentLayer.opacity < targetLayer.opacity
          ? currentLayer.opacity
          : targetLayer.opacity,
    );

    // 移除两个图层，插入合并后的图层
    final newLayers = List<DrawLayer>.from(state.layers);
    final removeIndex = targetIndex > currentIndex ? targetIndex : currentIndex;
    final keepIndex = targetIndex > currentIndex ? currentIndex : targetIndex;

    newLayers.removeAt(removeIndex);
    newLayers.removeAt(keepIndex);
    newLayers.insert(keepIndex, mergedLayer);

    // 调整活动图层索引
    int newActiveIndex = state.activeLayerIndex;
    if (newActiveIndex == removeIndex || newActiveIndex == keepIndex) {
      newActiveIndex = keepIndex;
    } else if (newActiveIndex > removeIndex) {
      newActiveIndex--;
    } else if (newActiveIndex > keepIndex) {
      newActiveIndex--;
    }

    state = state.copyWith(layers: newLayers, activeLayerIndex: newActiveIndex);
    return true;
  }

  /// 清空图层像素
  void clearLayer(int index) {
    if (index < 0 || index >= state.layers.length) return;
    final layer = state.layers[index];
    if (layer.isLocked) return;

    final newLayers = List<DrawLayer>.from(state.layers);
    newLayers[index] = layer.copyWith(clearPixels: true);

    state = state.copyWith(layers: newLayers);
  }

  /// 初始化默认图层
  void initializeWithDefaultLayer() {
    if (state.layers.isNotEmpty) return;
    addLayer(name: '背景');
  }

  void loadFromProject({
    required List<DrawLayer> layers,
    int activeLayerIndex = 0,
  }) {
    _clearStacks();
    final safeActiveIndex = layers.isEmpty
        ? 0
        : activeLayerIndex.clamp(0, layers.length - 1);

    state = LayerState(layers: layers, activeLayerIndex: safeActiveIndex);
  }

  /// 重置图层状态（创建新画布时调用）
  void reset() {
    _clearStacks();
    state = const LayerState();
    addLayer(name: '背景');
  }

  /// 清理撤销/重做栈内存
  void _clearStacks() {
    for (final step in _undoStack) {
      step.dispose();
    }
    _undoStack.clear();
    for (final step in _redoStack) {
      step.dispose();
    }
    _redoStack.clear();
  }

  @override
  void dispose() {
    _clearStacks();
    super.dispose();
  }
}

/// 图层 Provider
final layerProvider = StateNotifierProvider<LayerNotifier, LayerState>(
  (ref) => LayerNotifier()..initializeWithDefaultLayer(),
);
