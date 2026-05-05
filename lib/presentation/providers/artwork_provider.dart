import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/artwork.dart';
import '../../domain/entities/layer.dart';
import '../../domain/services/crypto_service.dart';
import '../../domain/utils/identity_utils.dart';
import '../../data/services/crypto_service_impl.dart';
import '../../services/network/tcp_client_service.dart'
    show CollabLayerOpType, CollabMultiLayerSnapshot;
import 'auth_provider.dart';
import 'layer_provider.dart';

/// 画作状态
class ArtworkState {
  /// 当前画作
  final Artwork? artwork;

  /// 错误消息
  final String? errorMessage;

  const ArtworkState({this.artwork, this.errorMessage});

  /// 是否已初始化
  bool get isInitialized => artwork?.isInitialized ?? false;

  /// 当前画作ID
  String get artworkId => artwork?.id ?? '';

  /// 当前画作种子
  int get seed => artwork?.seed ?? 0;

  /// 图层列表
  List<Layer> get layers => artwork?.layers ?? [];

  /// 复制并修改
  ArtworkState copyWith({
    Artwork? artwork,
    String? errorMessage,
    bool clearError = false,
    bool clearArtwork = false,
  }) {
    return ArtworkState(
      artwork: clearArtwork ? null : (artwork ?? this.artwork),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 画作状态管理器
class ArtworkNotifier extends StateNotifier<ArtworkState> {
  final CryptoService _cryptoService;
  final Ref _ref;

  ArtworkNotifier(this._ref)
    : _cryptoService = CryptoServiceImpl(),
      super(const ArtworkState());

  /// 创建新画作
  Future<void> createNew({
    required String name,
    required int width,
    required int height,
  }) async {
    final authState = _ref.read(authProvider);

    if (!authState.isLoggedIn) {
      state = state.copyWith(errorMessage: '请先登录', clearArtwork: true);
      return;
    }

    // 生成画作ID和种子
    final id = _cryptoService.generateUuid();
    final seed = _cryptoService.generateSeed();
    final now = DateTime.now();

    // 创建背景图层 (无权限)
    final backgroundLayer = Layer(
      id: '$id-0',
      index: 0,
      name: '背景',
      ownerSignature: null,
      ownerId: null,
      isVisible: true,
      isLocked: false,
      opacity: 1.0,
      createdAt: now,
    );

    // 创建画作
    final artwork = Artwork(
      id: id,
      name: name,
      seed: seed,
      width: width,
      height: height,
      creatorId: authState.username,
      createdAt: now,
      updatedAt: now,
      layers: [backgroundLayer],
    );

    state = ArtworkState(artwork: artwork);

    // 同步绘制图层（与 Domain Layer 使用同一 id）
    _ref
        .read(layerProvider.notifier)
        .loadFromProject(
          layers: [
            DrawLayer(id: backgroundLayer.id, name: backgroundLayer.name),
          ],
          activeLayerIndex: 0,
        );
  }

  /// 打开画作 (从文件)
  Future<void> openArtwork(Artwork artwork) async {
    state = ArtworkState(artwork: artwork);
  }

  /// 关闭画作
  void closeArtwork() {
    state = const ArtworkState();
  }

  /// 添加图层
  void addLayer({String? name, bool withPermission = false}) async {
    final artwork = state.artwork;
    if (artwork == null) return;

    final authState = _ref.read(authProvider);
    // 使用 UUID 生成唯一 ID，避免删除/移动后 ID 重复
    final layerId = '${artwork.id}-${_cryptoService.generateUuid()}';
    final newIndex = artwork.layers.length;
    final now = DateTime.now();

    // 生成签名 (如果需要权限)
    String? signature;
    String? ownerId;
    String? ownerPublicId;
    if (withPermission && authState.isLoggedIn) {
      signature = _cryptoService.signLayer(
        authState.privateKey,
        layerId,
        artwork.seed,
      );
      ownerId = authState.username;
      try {
        final publicIdBytes = IdentityUtils.derivePublicIdFromPrivateKey(
          authState.privateKey,
        );
        ownerPublicId = publicIdBytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        publicIdBytes.fillRange(0, publicIdBytes.length, 0);
      } catch (_) {
        ownerPublicId = null;
      }
    }

    final newLayer = Layer(
      id: layerId,
      index: newIndex,
      name: name ?? '图层 $newIndex',
      ownerSignature: signature,
      ownerId: ownerId,
      ownerPublicId: ownerPublicId,
      isVisible: true,
      isLocked: false,
      opacity: 1.0,
      createdAt: now,
    );

    final updatedArtwork = artwork.copyWith(
      layers: [...artwork.layers, newLayer],
      updatedAt: now,
    );

    state = ArtworkState(artwork: updatedArtwork);

    // 同步创建对应绘制图层（与 Domain Layer 同 id）
    _ref
        .read(layerProvider.notifier)
        .addLayerWithId(id: newLayer.id, name: newLayer.name);
  }

  /// 删除图层
  bool deleteLayer(int index) {
    final artwork = state.artwork;
    if (artwork == null || index < 0 || index >= artwork.layers.length) {
      return false;
    }

    final authState = _ref.read(authProvider);
    final layer = artwork.layers[index];

    // 检查权限（带签名验证）
    if (!layer.canDeleteWithVerification(
      authState.username,
      authState.privateKey,
      artwork.seed,
      _cryptoService.verifyLayerSignature,
    )) {
      state = state.copyWith(errorMessage: '无权限删除此图层');
      return false;
    }

    // 至少保留一个图层
    if (artwork.layers.length <= 1) {
      state = state.copyWith(errorMessage: '至少需要保留一个图层');
      return false;
    }

    final newLayers = List<Layer>.from(artwork.layers)..removeAt(index);

    // 同步删除绘制图层（删除前保留 id）
    _ref.read(layerProvider.notifier).removeLayerById(layer.id);

    // 重新编号
    for (var i = 0; i < newLayers.length; i++) {
      newLayers[i] = newLayers[i].copyWith(index: i);
    }

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
    return true;
  }

  /// 更新图层可见性
  void setLayerVisibility(int index, bool visible) {
    final artwork = state.artwork;
    if (artwork == null || index < 0 || index >= artwork.layers.length) return;

    final newLayers = List<Layer>.from(artwork.layers);
    newLayers[index] = newLayers[index].copyWith(isVisible: visible);

    // 同步到绘制图层
    _ref
        .read(layerProvider.notifier)
        .updateLayerById(newLayers[index].id, isVisible: visible);

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
  }

  /// 更新图层锁定状态
  void setLayerLocked(int index, bool locked) {
    final artwork = state.artwork;
    if (artwork == null || index < 0 || index >= artwork.layers.length) return;

    final newLayers = List<Layer>.from(artwork.layers);
    newLayers[index] = newLayers[index].copyWith(isLocked: locked);

    // 同步到绘制图层
    _ref
        .read(layerProvider.notifier)
        .updateLayerById(newLayers[index].id, isLocked: locked);

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
  }

  /// 为图层添加权限签名
  bool addLayerPermission(int index) {
    final artwork = state.artwork;
    if (artwork == null || index < 0 || index >= artwork.layers.length) {
      return false;
    }

    final authState = _ref.read(authProvider);
    if (!authState.isLoggedIn) {
      state = state.copyWith(errorMessage: '请先登录');
      return false;
    }

    final layer = artwork.layers[index];

    // 检查是否已有权限
    if (layer.hasPermission) {
      state = state.copyWith(errorMessage: '此图层已有权限');
      return false;
    }

    // 生成签名
    final signature = _cryptoService.signLayer(
      authState.privateKey,
      layer.id,
      artwork.seed,
    );

    String? ownerPublicId;
    try {
      final publicIdBytes = IdentityUtils.derivePublicIdFromPrivateKey(
        authState.privateKey,
      );
      ownerPublicId = publicIdBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      publicIdBytes.fillRange(0, publicIdBytes.length, 0);
    } catch (_) {
      ownerPublicId = null;
    }

    final newLayers = List<Layer>.from(artwork.layers);
    newLayers[index] = layer.copyWith(
      ownerSignature: signature,
      ownerId: authState.username,
      ownerPublicId: ownerPublicId,
    );

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
    return true;
  }

  /// 移除图层权限签名 (降为无权限)
  bool removeLayerPermission(int index) {
    final artwork = state.artwork;
    if (artwork == null || index < 0 || index >= artwork.layers.length) {
      return false;
    }

    final authState = _ref.read(authProvider);
    final layer = artwork.layers[index];

    // 检查权限 (只有自己的图层可以移除权限，需验证签名)
    if (!layer.canChangePermissionWithVerification(
      authState.username,
      authState.privateKey,
      artwork.seed,
      _cryptoService.verifyLayerSignature,
    )) {
      state = state.copyWith(errorMessage: '只能移除自己图层的权限');
      return false;
    }

    final newLayers = List<Layer>.from(artwork.layers);
    newLayers[index] = layer.copyWith(clearOwner: true);

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
    return true;
  }

  /// 更新图层名称
  void setLayerName(int index, String name) {
    final artwork = state.artwork;
    if (artwork == null || index < 0 || index >= artwork.layers.length) return;
    if (name.trim().isEmpty) return;

    final newLayers = List<Layer>.from(artwork.layers);
    newLayers[index] = newLayers[index].copyWith(name: name.trim());

    // 同步到绘制图层
    _ref
        .read(layerProvider.notifier)
        .updateLayerById(newLayers[index].id, name: name.trim());

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
  }

  /// 更新图层不透明度
  void setLayerOpacity(int index, double opacity) {
    final artwork = state.artwork;
    if (artwork == null || index < 0 || index >= artwork.layers.length) return;

    final clampedOpacity = opacity.clamp(0.0, 1.0);
    final newLayers = List<Layer>.from(artwork.layers);
    newLayers[index] = newLayers[index].copyWith(opacity: clampedOpacity);

    // 同步到绘制图层
    _ref
        .read(layerProvider.notifier)
        .updateLayerById(newLayers[index].id, opacity: clampedOpacity);

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
  }

  /// 移动图层顺序
  void moveLayer(int fromIndex, int toIndex) {
    final artwork = state.artwork;
    if (artwork == null) return;
    if (fromIndex < 0 || fromIndex >= artwork.layers.length) return;
    if (toIndex < 0 || toIndex >= artwork.layers.length) return;
    if (fromIndex == toIndex) return;

    final newLayers = List<Layer>.from(artwork.layers);
    final layer = newLayers.removeAt(fromIndex);
    newLayers.insert(toIndex, layer);

    // 重新编号
    for (var i = 0; i < newLayers.length; i++) {
      newLayers[i] = newLayers[i].copyWith(index: i);
    }

    // 同步移动绘制图层
    _ref.read(layerProvider.notifier).moveLayer(fromIndex, toIndex);

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
  }

  /// 合并图层（向上或向下）
  /// [index] 当前图层索引
  /// [direction] 方向：'up' 向上合并，'down' 向下合并
  /// 返回是否成功
  Future<bool> mergeLayer(int index, String direction) async {
    final artwork = state.artwork;
    if (artwork == null || index < 0 || index >= artwork.layers.length)
      return false;

    int targetIndex;
    if (direction == 'up') {
      // 向上合并：合并到 UI 上方图层（更高索引 = 顶层方向）
      if (index == artwork.layers.length - 1) {
        state = state.copyWith(errorMessage: '已经是最顶层，无法向上合并');
        return false;
      }
      targetIndex = index + 1;
    } else {
      // 向下合并：合并到 UI 下方图层（更低索引 = 底层方向）
      if (index == 0) {
        state = state.copyWith(errorMessage: '已经是最底层，无法向下合并');
        return false;
      }
      targetIndex = index - 1;
    }

    final currentLayer = artwork.layers[index];
    final targetLayer = artwork.layers[targetIndex];

    // 检查权限：只能合并自己有权限的图层
    final authState = _ref.read(authProvider);

    final canEditCurrent = currentLayer.canEditWithVerification(
      authState.username,
      authState.privateKey,
      artwork.seed,
      _cryptoService.verifyLayerSignature,
    );
    final canEditTarget = targetLayer.canEditWithVerification(
      authState.username,
      authState.privateKey,
      artwork.seed,
      _cryptoService.verifyLayerSignature,
    );

    if (!canEditCurrent || !canEditTarget) {
      state = state.copyWith(errorMessage: '只能合并有权限的图层');
      return false;
    }

    // 异步合并绘制图层（像素合成）
    final success = await _ref
        .read(layerProvider.notifier)
        .mergeLayers(
          index,
          targetIndex,
          canvasWidth: artwork.width,
          canvasHeight: artwork.height,
        );
    if (!success) return false;

    // 更新领域层：移除目标图层，保留当前图层
    // 像素合并已由 layer_provider.mergeLayers 处理
    final newLayers = List<Layer>.from(artwork.layers);

    // 移除目标图层
    newLayers.removeAt(targetIndex);

    // 重新编号
    for (var i = 0; i < newLayers.length; i++) {
      newLayers[i] = newLayers[i].copyWith(index: i);
    }

    final updatedArtwork = artwork.copyWith(
      layers: newLayers,
      updatedAt: DateTime.now(),
    );

    state = ArtworkState(artwork: updatedArtwork);
    return true;
  }

  /// 清除错误消息
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  // ========== 多图层协同方法 ==========

  /// 协同：处理图层操作广播（Domain Layer 侧）
  void applyCollabLayerOp(
    CollabLayerOpType opType,
    Map<String, dynamic> payload,
  ) {
    final artwork = state.artwork;
    if (artwork == null) return;
    final now = DateTime.now();

    switch (opType) {
      case CollabLayerOpType.add:
        final layerId = payload['layerId'] as String?;
        final name = payload['name'] as String? ?? '';
        final ownerId = payload['ownerId'] as String? ?? '';
        if (layerId == null) return;
        if (artwork.layers.any((l) => l.id == layerId)) return;
        final opacity = (payload['opacity'] as num?)?.toDouble() ?? 1.0;
        final isVisible = payload['isVisible'] as bool? ?? true;
        final isLocked = payload['isLocked'] as bool? ?? false;
        final newLayer = Layer(
          id: layerId,
          index: artwork.layers.length,
          name: name,
          ownerId: ownerId,
          isVisible: isVisible,
          isLocked: isLocked,
          opacity: opacity,
          createdAt: now,
        );
        state = ArtworkState(
          artwork: artwork.copyWith(
            layers: [...artwork.layers, newLayer],
            updatedAt: now,
          ),
        );
        break;

      case CollabLayerOpType.remove:
        final layerId = payload['layerId'] as String?;
        if (layerId == null) return;
        if (artwork.layers.length <= 1) return;
        final newLayers = artwork.layers.where((l) => l.id != layerId).toList();
        for (var i = 0; i < newLayers.length; i++) {
          newLayers[i] = newLayers[i].copyWith(index: i);
        }
        state = ArtworkState(
          artwork: artwork.copyWith(layers: newLayers, updatedAt: now),
        );
        break;

      case CollabLayerOpType.rename:
        final layerId = payload['layerId'] as String?;
        final name = payload['name'] as String?;
        if (layerId == null || name == null) return;
        final idx = artwork.layers.indexWhere((l) => l.id == layerId);
        if (idx < 0) return;
        final newLayers = List<Layer>.from(artwork.layers);
        newLayers[idx] = newLayers[idx].copyWith(name: name);
        state = ArtworkState(
          artwork: artwork.copyWith(layers: newLayers, updatedAt: now),
        );
        break;

      case CollabLayerOpType.reorder:
        final order = (payload['order'] as List?)?.cast<String>();
        if (order == null) return;
        final map = {for (final l in artwork.layers) l.id: l};
        final reordered = <Layer>[];
        for (final id in order) {
          final l = map[id];
          if (l != null) reordered.add(l);
        }
        for (final l in artwork.layers) {
          if (!reordered.any((r) => r.id == l.id)) reordered.add(l);
        }
        for (var i = 0; i < reordered.length; i++) {
          reordered[i] = reordered[i].copyWith(index: i);
        }
        state = ArtworkState(
          artwork: artwork.copyWith(layers: reordered, updatedAt: now),
        );
        break;

      case CollabLayerOpType.setVisibility:
        final layerId = payload['layerId'] as String?;
        final isVisible = payload['isVisible'] as bool?;
        if (layerId == null || isVisible == null) return;
        final idx = artwork.layers.indexWhere((l) => l.id == layerId);
        if (idx < 0) return;
        final newLayers = List<Layer>.from(artwork.layers);
        newLayers[idx] = newLayers[idx].copyWith(isVisible: isVisible);
        state = ArtworkState(
          artwork: artwork.copyWith(layers: newLayers, updatedAt: now),
        );
        break;

      case CollabLayerOpType.setOpacity:
        final layerId = payload['layerId'] as String?;
        final opacity = (payload['opacity'] as num?)?.toDouble();
        if (layerId == null || opacity == null) return;
        final idx = artwork.layers.indexWhere((l) => l.id == layerId);
        if (idx < 0) return;
        final newLayers = List<Layer>.from(artwork.layers);
        newLayers[idx] = newLayers[idx].copyWith(
          opacity: opacity.clamp(0.0, 1.0),
        );
        state = ArtworkState(
          artwork: artwork.copyWith(layers: newLayers, updatedAt: now),
        );
        break;

      case CollabLayerOpType.setLock:
        final layerId = payload['layerId'] as String?;
        final isLocked = payload['isLocked'] as bool?;
        if (layerId == null || isLocked == null) return;
        final idx = artwork.layers.indexWhere((l) => l.id == layerId);
        if (idx < 0) return;
        final newLayers = List<Layer>.from(artwork.layers);
        newLayers[idx] = newLayers[idx].copyWith(isLocked: isLocked);
        state = ArtworkState(
          artwork: artwork.copyWith(layers: newLayers, updatedAt: now),
        );
        break;
    }
  }

  /// 协同：应用多图层快照（完整重建 Artwork.layers）
  void applyCollabMultiLayerSnapshot(CollabMultiLayerSnapshot snap) {
    final artwork = state.artwork;
    if (artwork == null) return;
    final now = DateTime.now();

    final newLayers = <Layer>[];
    for (var i = 0; i < snap.layers.length; i++) {
      final entry = snap.layers[i];
      newLayers.add(
        Layer(
          id: entry.layerId,
          index: i,
          name: entry.name,
          ownerId: entry.ownerId.isNotEmpty ? entry.ownerId : null,
          isVisible: entry.isVisible,
          isLocked: entry.isLocked,
          opacity: entry.opacity / 255.0,
          createdAt: now,
        ),
      );
    }

    state = ArtworkState(
      artwork: artwork.copyWith(
        width: snap.canvasWidth,
        height: snap.canvasHeight,
        layers: newLayers,
        updatedAt: now,
      ),
    );
  }
}

/// 画作 Provider
final artworkProvider = StateNotifierProvider<ArtworkNotifier, ArtworkState>(
  (ref) => ArtworkNotifier(ref),
);
