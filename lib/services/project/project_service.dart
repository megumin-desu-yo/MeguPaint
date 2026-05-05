import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/artwork.dart';
import '../../domain/entities/layer.dart' as domain_layer;
import '../../presentation/providers/layer_provider.dart';

/// 项目文件扩展名
const String kProjectExtension = '.mgp';

/// 项目数据模型
class ProjectFile {
  final Artwork artwork;
  final List<domain_layer.Layer> domainLayers;
  final List<DrawLayer> drawLayers;
  final int activeLayerIndex;
  final String filePath;
  final DateTime lastModified;

  const ProjectFile({
    required this.artwork,
    required this.domainLayers,
    required this.drawLayers,
    required this.activeLayerIndex,
    required this.filePath,
    required this.lastModified,
  });
}

/// 项目文件服务（像素模式：图层像素数据以 PNG base64 存储）
class ProjectService {
  /// 打开项目文件选择器
  Future<ProjectFile?> pickProjectFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mgp'],
      dialogTitle: '打开MeguPaint项目',
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    if (file.path == null) {
      return null;
    }

    return await loadProjectFile(file.path!);
  }

  /// 将 ui.Image 编码为 PNG base64 字符串
  static Future<String?> _encodeImage(ui.Image? image) async {
    if (image == null) return null;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return base64Encode(byteData.buffer.asUint8List());
  }

  /// 将 PNG base64 字符串解码为 ui.Image
  static Future<ui.Image?> _decodeImage(String? base64Str) async {
    if (base64Str == null || base64Str.isEmpty) return null;
    final bytes = base64Decode(base64Str);
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 加载项目文件
  Future<ProjectFile> loadProjectFile(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('无效的项目文件格式');
    }

    final format = decoded['format'];
    final version = decoded['version'];
    if (format != 'megu_paint_project' || (version != 1 && version != 2)) {
      throw FormatException('不支持的项目格式版本');
    }

    final artworkMap = Map<String, dynamic>.from(decoded['artwork'] as Map);
    final parsedArtwork = Artwork.fromMap(artworkMap);

    final domainLayers = (decoded['domainLayers'] as List<dynamic>? ?? const [])
        .map((e) => domain_layer.Layer.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    final artwork = domainLayers.isNotEmpty
        ? parsedArtwork.copyWith(layers: domainLayers)
        : parsedArtwork;

    final rawDrawLayerMaps =
        (decoded['drawLayers'] as List<dynamic>? ?? const []);

    // 解析图层元数据
    final rawDrawLayers = rawDrawLayerMaps
        .map((e) => DrawLayer.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    // 解码图层像素数据（version 2 格式含 pixelData 字段）
    final pixelDataList = decoded['pixelData'] as List<dynamic>?;
    if (pixelDataList != null && pixelDataList.length == rawDrawLayers.length) {
      for (var i = 0; i < rawDrawLayers.length; i++) {
        final base64Str = pixelDataList[i] as String?;
        if (base64Str != null && base64Str.isNotEmpty) {
          final image = await _decodeImage(base64Str);
          if (image != null) {
            rawDrawLayers[i] = rawDrawLayers[i].copyWith(pixels: image);
          }
        }
      }
    }

    final activeLayerIndex =
        (decoded['activeLayerIndex'] as num?)?.toInt() ?? 0;

    // 按 domainLayers（权限层）对齐绘制层：确保 id 一致、顺序一致、并补齐缺失图层
    List<DrawLayer> drawLayers;
    if (domainLayers.isNotEmpty) {
      final drawLayerById = <String, DrawLayer>{
        for (final dl in rawDrawLayers) dl.id: dl,
      };

      drawLayers = domainLayers.map((dl) {
        final existing = drawLayerById[dl.id];
        if (existing == null) {
          return DrawLayer(
            id: dl.id,
            name: dl.name,
            opacity: dl.opacity,
            isVisible: dl.isVisible,
            isLocked: dl.isLocked,
          );
        }
        return DrawLayer(
          id: existing.id,
          name: dl.name,
          pixels: existing.pixels,
          opacity: dl.opacity,
          isVisible: dl.isVisible,
          isLocked: dl.isLocked,
          blendMode: existing.blendMode,
        );
      }).toList();
    } else {
      drawLayers = rawDrawLayers;
    }

    return ProjectFile(
      artwork: artwork,
      domainLayers: domainLayers,
      drawLayers: drawLayers,
      activeLayerIndex: activeLayerIndex,
      filePath: filePath,
      lastModified: stat.modified,
    );
  }

  /// 保存项目文件（像素模式，version 2）
  Future<bool> saveProjectFile({
    required Artwork artwork,
    required List<DrawLayer> drawLayers,
    List<domain_layer.Layer>? domainLayers,
    int activeLayerIndex = 0,
    String? customPath,
  }) async {
    String savePath;

    if (customPath != null) {
      savePath = customPath;
    } else {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存MeguPaint项目',
        fileName: '${artwork.name}$kProjectExtension',
        type: FileType.custom,
        allowedExtensions: ['mgp'],
      );

      if (result == null) {
        return false;
      }
      savePath = result;
    }

    // 确保扩展名
    if (!savePath.endsWith(kProjectExtension)) {
      savePath += kProjectExtension;
    }

    final file = File(savePath);

    final resolvedDomainLayers = domainLayers ?? artwork.layers;

    // 输出时按 domainLayers 顺序稳定排列 drawLayers，避免索引错位
    final drawLayerById = <String, DrawLayer>{
      for (final dl in drawLayers) dl.id: dl,
    };
    final orderedDrawLayers = resolvedDomainLayers.map((l) {
      final existing = drawLayerById[l.id];
      if (existing == null) {
        return DrawLayer(
          id: l.id,
          name: l.name,
          opacity: l.opacity,
          isVisible: l.isVisible,
          isLocked: l.isLocked,
        );
      }
      return DrawLayer(
        id: existing.id,
        name: l.name,
        pixels: existing.pixels,
        opacity: l.opacity,
        isVisible: l.isVisible,
        isLocked: l.isLocked,
        blendMode: existing.blendMode,
      );
    }).toList();

    // 编码每个图层的像素数据为 PNG base64
    final pixelDataList = <String?>[];
    for (final dl in orderedDrawLayers) {
      pixelDataList.add(await _encodeImage(dl.pixels));
    }

    final payload = <String, dynamic>{
      'format': 'megu_paint_project',
      'version': 2,
      'savedAt': DateTime.now().toIso8601String(),
      'artwork': artwork.toMap(),
      'domainLayers': resolvedDomainLayers.map((e) => e.toMap()).toList(),
      'drawLayers': orderedDrawLayers.map((e) => e.toMap()).toList(),
      'pixelData': pixelDataList,
      'activeLayerIndex': activeLayerIndex,
    };

    await file.writeAsString(jsonEncode(payload));

    return true;
  }

  /// 获取默认项目目录
  Future<String> getDefaultProjectDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/MeguPaint/Projects');
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    return projectDir.path;
  }
}
