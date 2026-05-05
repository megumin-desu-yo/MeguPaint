import 'dart:io';
import 'dart:typed_data';

// ============================================================================
//                              压缩工具
// ============================================================================

/// 压缩阈值：小于此值不压缩（压缩开销大于收益）
const int kCompressionThreshold = 256; // 256 字节

/// 使用 zlib 压缩数据
///
/// 返回压缩后的数据，如果压缩后更大则返回原数据
Uint8List compressDelta(Uint8List data) {
  if (data.length < kCompressionThreshold) {
    return data;
  }

  final compressed = zlib.encode(data);
  // 如果压缩后更大，返回原数据
  if (compressed.length >= data.length) {
    return data;
  }
  return Uint8List.fromList(compressed);
}

/// 解压缩数据
///
/// 如果 [isCompressed] 为 false，直接返回原数据
Uint8List decompressDelta(Uint8List data, int originalSize, bool isCompressed) {
  if (!isCompressed) {
    return data;
  }

  final decompressed = zlib.decode(data);
  if (decompressed.length != originalSize) {
    throw FormatException(
      'Decompressed size mismatch: expected $originalSize, got ${decompressed.length}',
    );
  }
  return Uint8List.fromList(decompressed);
}

/// 区域增量撤销步骤
///
/// 存储单个图层在特定区域的像素增量，用于高效的 Undo/Redo 和协同同步。
/// 相比存储完整 ui.Image，增量存储可节省 95%+ 内存。
class UndoRegionDeltaStep {
  /// 图层索引
  final int layerIndex;

  /// 图层 ID（协同模式使用，不序列化）
  final String? layerId;

  // ========== 区域信息 ==========

  /// 包围盒左上角 X 坐标（像素）
  final int x;

  /// 包围盒左上角 Y 坐标（像素）
  final int y;

  /// 包围盒宽度（像素）
  final int width;

  /// 包围盒高度（像素）
  final int height;

  // ========== 增量数据 ==========

  /// XOR 后的 RGBA 数据
  ///
  /// 格式：从 (x,y) 开始，逐行存储 width×height 像素的 RGBA 值
  /// 每像素 4 字节：R, G, B, A
  /// 大小：width × height × 4 字节
  final Uint8List delta;

  // ========== 元数据 ==========

  /// 原画布宽度（用于边界检查和协同同步）
  final int canvasWidth;

  /// 原画布高度
  final int canvasHeight;

  /// 版本号（用于协同时的版本控制）
  final int revision;

  // ========== 统计信息 ==========

  /// 原始 RGBA 数据大小（未压缩）
  final int originalSize;

  /// 改变的像素数量（非零像素数）
  final int changedPixels;

  /// 是否已压缩（LZ4/zlib）
  final bool isCompressed;

  UndoRegionDeltaStep({
    required this.layerIndex,
    this.layerId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.delta,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.revision,
    required this.originalSize,
    required this.changedPixels,
    this.isCompressed = false,
  });

  /// 获取包围盒区域
  Rect get rect => Rect.fromLTWH(
    x.toDouble(),
    y.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );

  /// 获取 delta 数据大小（字节）
  int get deltaSize => delta.length;

  /// 获取压缩率（如果已压缩）
  double get compressionRatio =>
      isCompressed && originalSize > 0 ? deltaSize / originalSize : 1.0;

  /// 获取区域面积（像素数）
  int get area => width * height;

  /// 获取区域占画布的比例
  double get areaRatio {
    final canvasArea = canvasWidth * canvasHeight;
    return canvasArea > 0 ? area / canvasArea : 0.0;
  }

  /// 序列化为二进制格式（用于存储或网络传输）
  Uint8List encode() {
    final builder = BytesBuilder();

    // Header: layerIndex(4) + x(4) + y(4) + width(4) + height(4) +
    //          canvasWidth(4) + canvasHeight(4) + revision(4) +
    //          originalSize(4) + changedPixels(4) + isCompressed(1) + deltaSize(4)
    // Total: 41 bytes header

    final header = ByteData(41);
    header.setInt32(0, layerIndex, Endian.little);
    header.setInt32(4, x, Endian.little);
    header.setInt32(8, y, Endian.little);
    header.setInt32(12, width, Endian.little);
    header.setInt32(16, height, Endian.little);
    header.setInt32(20, canvasWidth, Endian.little);
    header.setInt32(24, canvasHeight, Endian.little);
    header.setInt32(28, revision, Endian.little);
    header.setInt32(32, originalSize, Endian.little);
    header.setInt32(36, changedPixels, Endian.little);
    header.setUint8(40, isCompressed ? 1 : 0);

    builder.add(header.buffer.asUint8List());
    builder.add(delta);

    return builder.toBytes();
  }

  /// 从二进制格式解码
  static UndoRegionDeltaStep decode(Uint8List data) {
    if (data.length < 41) {
      throw FormatException('Data too short for UndoRegionDeltaStep header');
    }

    final header = ByteData.sublistView(data, 0, 41);
    final layerIndex = header.getInt32(0, Endian.little);
    final x = header.getInt32(4, Endian.little);
    final y = header.getInt32(8, Endian.little);
    final width = header.getInt32(12, Endian.little);
    final height = header.getInt32(16, Endian.little);
    final canvasWidth = header.getInt32(20, Endian.little);
    final canvasHeight = header.getInt32(24, Endian.little);
    final revision = header.getInt32(28, Endian.little);
    final originalSize = header.getInt32(32, Endian.little);
    final changedPixels = header.getInt32(36, Endian.little);
    final isCompressed = header.getUint8(40) == 1;

    final delta = Uint8List.sublistView(data, 41);

    return UndoRegionDeltaStep(
      layerIndex: layerIndex,
      x: x,
      y: y,
      width: width,
      height: height,
      delta: delta,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      revision: revision,
      originalSize: originalSize,
      changedPixels: changedPixels,
      isCompressed: isCompressed,
    );
  }

  @override
  String toString() {
    return 'UndoRegionDeltaStep(layer=$layerIndex, rect=($x,$y $width×$height), '
        'delta=${deltaSize}B, rev=$revision, changed=$changedPixels, '
        'ratio=${(compressionRatio * 100).toStringAsFixed(1)}%)';
  }
}

/// 包围盒区域（简化版，避免依赖 dart:ui）
class Rect {
  final double left;
  final double top;
  final double width;
  final double height;

  const Rect.fromLTWH(this.left, this.top, this.width, this.height);

  double get right => left + width;
  double get bottom => top + height;

  bool get isEmpty => width <= 0 || height <= 0;

  static const Rect zero = Rect.fromLTWH(0, 0, 0, 0);

  @override
  String toString() => 'Rect.fromLTWH($left, $top, $width, $height)';
}

// ============================================================================
//                              核心算法
// ============================================================================

/// Tile 分块大小（像素）
///
/// 用于将包围盒对齐到 Tile 边界，优化压缩效率
const int kTileSize = 64;

/// 计算两图像差异的包围盒
///
/// 遍历比较 oldRgba 和 newRgba 的每个像素，找出所有改变像素的包围盒。
/// 返回的包围盒会对齐到 Tile 边界（64像素）。
///
/// 参数：
/// - [oldRgba]: 旧图像的 RGBA 数据（可为 null 表示全透明）
/// - [newRgba]: 新图像的 RGBA 数据
/// - [width]: 画布宽度
/// - [height]: 画布高度
///
/// 返回：包围盒，如果无变化返回 Rect.zero
Rect computeDirtyRect(
  Uint8List? oldRgba,
  Uint8List newRgba,
  int width,
  int height,
) {
  int minX = width;
  int minY = height;
  int maxX = -1;
  int maxY = -1;
  bool hasChange = false;

  // 遍历所有像素
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = (y * width + x) * 4;

      // 比较 RGBA 四通道
      final oldR = oldRgba != null ? oldRgba[idx] : 0;
      final oldG = oldRgba != null ? oldRgba[idx + 1] : 0;
      final oldB = oldRgba != null ? oldRgba[idx + 2] : 0;
      final oldA = oldRgba != null ? oldRgba[idx + 3] : 0;

      final newR = newRgba[idx];
      final newG = newRgba[idx + 1];
      final newB = newRgba[idx + 2];
      final newA = newRgba[idx + 3];

      if (oldR != newR || oldG != newG || oldB != newB || oldA != newA) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        hasChange = true;
      }
    }
  }

  if (!hasChange) return Rect.zero;

  // 扩展到 Tile 边界（对齐到 64 像素）
  minX = (minX ~/ kTileSize) * kTileSize;
  minY = (minY ~/ kTileSize) * kTileSize;
  maxX = ((maxX ~/ kTileSize) + 1) * kTileSize;
  maxY = ((maxY ~/ kTileSize) + 1) * kTileSize;

  // 边界裁剪
  if (maxX > width) maxX = width;
  if (maxY > height) maxY = height;

  return Rect.fromLTWH(
    minX.toDouble(),
    minY.toDouble(),
    (maxX - minX).toDouble(),
    (maxY - minY).toDouble(),
  );
}

/// 计算区域增量（XOR Delta）
///
/// 对指定包围盒区域内的像素进行 XOR 运算，生成增量数据。
///
/// 参数：
/// - [oldRgba]: 旧图像的 RGBA 数据（可为 null 表示全透明）
/// - [newRgba]: 新图像的 RGBA 数据
/// - [canvasWidth]: 画布宽度
/// - [dirtyRect]: 包围盒区域
///
/// 返回：XOR 后的 RGBA 数据
Uint8List computeRegionDelta(
  Uint8List? oldRgba,
  Uint8List newRgba,
  int canvasWidth,
  Rect dirtyRect,
) {
  final x = dirtyRect.left.toInt();
  final y = dirtyRect.top.toInt();
  final w = dirtyRect.width.toInt();
  final h = dirtyRect.height.toInt();

  // 区域像素数 × 4 通道
  final deltaSize = w * h * 4;
  final delta = Uint8List(deltaSize);

  for (int dy = 0; dy < h; dy++) {
    for (int dx = 0; dx < w; dx++) {
      // 全图像素索引
      final fullIdx = ((y + dy) * canvasWidth + (x + dx)) * 4;
      // 区域内像素索引
      final regionIdx = (dy * w + dx) * 4;

      // XOR 运算
      delta[regionIdx] =
          (oldRgba != null ? oldRgba[fullIdx] : 0) ^ newRgba[fullIdx];
      delta[regionIdx + 1] =
          (oldRgba != null ? oldRgba[fullIdx + 1] : 0) ^ newRgba[fullIdx + 1];
      delta[regionIdx + 2] =
          (oldRgba != null ? oldRgba[fullIdx + 2] : 0) ^ newRgba[fullIdx + 2];
      delta[regionIdx + 3] =
          (oldRgba != null ? oldRgba[fullIdx + 3] : 0) ^ newRgba[fullIdx + 3];
    }
  }

  return delta;
}

/// 应用区域增量到 RGBA 数据
///
/// 将 XOR Delta 应用到当前 RGBA 数据，恢复旧像素值。
/// 支持自动解压缩。
///
/// 参数：
/// - [currentRgba]: 当前图像的 RGBA 数据
/// - [canvasWidth]: 画布宽度
/// - [step]: 增量步骤
///
/// 返回：应用增量后的 RGBA 数据（新数组）
Uint8List applyRegionDelta(
  Uint8List currentRgba,
  int canvasWidth,
  UndoRegionDeltaStep step,
) {
  // 复制当前数据
  final result = Uint8List.fromList(currentRgba);

  final x = step.x;
  final y = step.y;
  final w = step.width;
  final h = step.height;

  // 解压缩（如果需要）
  final delta = decompressDelta(
    step.delta,
    step.originalSize,
    step.isCompressed,
  );

  for (int dy = 0; dy < h; dy++) {
    for (int dx = 0; dx < w; dx++) {
      // 全图像素索引
      final fullIdx = ((y + dy) * canvasWidth + (x + dx)) * 4;
      // 区域内像素索引
      final regionIdx = (dy * w + dx) * 4;

      // XOR 运算恢复旧值
      result[fullIdx] ^= delta[regionIdx];
      result[fullIdx + 1] ^= delta[regionIdx + 1];
      result[fullIdx + 2] ^= delta[regionIdx + 2];
      result[fullIdx + 3] ^= delta[regionIdx + 3];
    }
  }

  return result;
}

/// 统计增量中非零像素数量
///
/// 用于统计实际改变的像素数
int countChangedPixels(Uint8List delta, int width, int height) {
  int count = 0;
  for (int i = 0; i < delta.length; i += 4) {
    // 任一通道非零即视为改变
    if (delta[i] != 0 ||
        delta[i + 1] != 0 ||
        delta[i + 2] != 0 ||
        delta[i + 3] != 0) {
      count++;
    }
  }
  return count;
}

/// 创建完整的增量步骤
///
/// 封装了 computeDirtyRect + computeRegionDelta 的完整流程
///
/// 参数：
/// - [layerIndex]: 图层索引
/// - [oldRgba]: 旧图像 RGBA（可为 null）
/// - [newRgba]: 新图像 RGBA
/// - [canvasWidth]: 画布宽度
/// - [canvasHeight]: 画布高度
/// - [revision]: 当前版本号
/// - [enableCompression]: 是否启用压缩（默认 true）
///
/// 返回：增量步骤，如果无变化返回 null
UndoRegionDeltaStep? createDeltaStep({
  required int layerIndex,
  required Uint8List? oldRgba,
  required Uint8List newRgba,
  required int canvasWidth,
  required int canvasHeight,
  required int revision,
  bool enableCompression = true,
}) {
  // 1. 计算包围盒
  final dirtyRect = computeDirtyRect(
    oldRgba,
    newRgba,
    canvasWidth,
    canvasHeight,
  );
  if (dirtyRect.isEmpty) return null;

  // 2. 计算区域增量
  final delta = computeRegionDelta(oldRgba, newRgba, canvasWidth, dirtyRect);
  final originalSize = delta.length;

  // 3. 统计改变像素数
  final changedPixels = countChangedPixels(
    delta,
    dirtyRect.width.toInt(),
    dirtyRect.height.toInt(),
  );

  // 4. 压缩（可选）
  Uint8List finalDelta = delta;
  bool isCompressed = false;
  if (enableCompression && delta.length >= kCompressionThreshold) {
    final compressed = compressDelta(delta);
    if (compressed.length < delta.length) {
      finalDelta = compressed;
      isCompressed = true;
    }
  }

  // 5. 创建增量步骤
  return UndoRegionDeltaStep(
    layerIndex: layerIndex,
    x: dirtyRect.left.toInt(),
    y: dirtyRect.top.toInt(),
    width: dirtyRect.width.toInt(),
    height: dirtyRect.height.toInt(),
    delta: finalDelta,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    revision: revision,
    originalSize: originalSize,
    changedPixels: changedPixels,
    isCompressed: isCompressed,
  );
}
