import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:megu_paint/services/delta/region_delta.dart';

void main() {
  group('压缩功能', () {
    test('小数据不压缩', () {
      final data = Uint8List.fromList(List.filled(100, 128));
      final compressed = compressDelta(data);
      expect(compressed.length, equals(data.length));
    });

    test('大数据压缩有效', () {
      // 创建一个有规律的数据（压缩效果好）
      final data = Uint8List.fromList(List.filled(10000, 128));
      final compressed = compressDelta(data);
      expect(compressed.length, lessThan(data.length));
    });

    test('随机数据压缩效果差', () {
      // 随机数据压缩效果差，可能不压缩
      final data = Uint8List(10000);
      for (int i = 0; i < data.length; i++) {
        data[i] = (i * 17 + 13) % 256; // 伪随机
      }
      final compressed = compressDelta(data);
      // 随机数据可能压缩后更大，此时返回原数据
      expect(compressed.length, lessThanOrEqualTo(data.length));
    });

    test('压缩后解压缩数据一致', () {
      final original = Uint8List.fromList(List.filled(10000, 128));
      final compressed = compressDelta(original);

      if (compressed.length < original.length) {
        final decompressed = decompressDelta(compressed, original.length, true);
        expect(decompressed, equals(original));
      }
    });

    test('createDeltaStep 启用压缩', () {
      final oldRgba = Uint8List.fromList(List.filled(256 * 256 * 4, 0));
      final newRgba = Uint8List.fromList(List.filled(256 * 256 * 4, 0));

      // 修改一个大区域（压缩效果好）
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final idx = (y * 256 + x) * 4;
          newRgba[idx] = 128;
          newRgba[idx + 3] = 255;
        }
      }

      final step = createDeltaStep(
        layerIndex: 0,
        oldRgba: oldRgba,
        newRgba: newRgba,
        canvasWidth: 256,
        canvasHeight: 256,
        revision: 0,
        enableCompression: true,
      );

      expect(step, isNotNull);
      expect(step!.isCompressed, isTrue);
      expect(step.deltaSize, lessThan(step.originalSize));
    });

    test('createDeltaStep 禁用压缩', () {
      final oldRgba = Uint8List.fromList(List.filled(256 * 256 * 4, 0));
      final newRgba = Uint8List.fromList(List.filled(256 * 256 * 4, 0));

      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final idx = (y * 256 + x) * 4;
          newRgba[idx] = 128;
          newRgba[idx + 3] = 255;
        }
      }

      final step = createDeltaStep(
        layerIndex: 0,
        oldRgba: oldRgba,
        newRgba: newRgba,
        canvasWidth: 256,
        canvasHeight: 256,
        revision: 0,
        enableCompression: false,
      );

      expect(step, isNotNull);
      expect(step!.isCompressed, isFalse);
      expect(step.deltaSize, equals(step.originalSize));
    });

    test('压缩数据 applyRegionDelta 正确', () {
      final size = 128;
      final oldRgba = Uint8List.fromList(List.filled(size * size * 4, 0));
      final newRgba = Uint8List.fromList(List.filled(size * size * 4, 0));

      // 修改中心区域
      for (int y = 32; y < 96; y++) {
        for (int x = 32; x < 96; x++) {
          final idx = (y * size + x) * 4;
          newRgba[idx] = 255;
          newRgba[idx + 3] = 255;
        }
      }

      final step = createDeltaStep(
        layerIndex: 0,
        oldRgba: oldRgba,
        newRgba: newRgba,
        canvasWidth: size,
        canvasHeight: size,
        revision: 0,
        enableCompression: true,
      );

      expect(step, isNotNull);

      // 应用 delta 恢复 oldRgba
      final restored = applyRegionDelta(newRgba, size, step!);
      expect(restored, equals(oldRgba));
    });
  });

  group('压缩性能测试', () {
    test('压缩性能 - 64x64 区域', () {
      final size = 512;
      final oldRgba = Uint8List.fromList(List.filled(size * size * 4, 0));
      final newRgba = Uint8List.fromList(List.filled(size * size * 4, 0));

      // 修改 64x64 区域
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final idx = (y * size + x) * 4;
          newRgba[idx] = (x + y) % 256;
          newRgba[idx + 3] = 255;
        }
      }

      final stopwatch = Stopwatch()..start();
      final step = createDeltaStep(
        layerIndex: 0,
        oldRgba: oldRgba,
        newRgba: newRgba,
        canvasWidth: size,
        canvasHeight: size,
        revision: 0,
        enableCompression: true,
      );
      stopwatch.stop();

      print('\n=== 压缩性能测试 ===');
      print('区域: 64x64');
      print('原始大小: ${step!.originalSize} 字节');
      print('压缩后: ${step.deltaSize} 字节');
      print('压缩率: ${(step.compressionRatio * 100).toStringAsFixed(1)}%');
      print('压缩耗时: ${stopwatch.elapsedMilliseconds}ms');

      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('压缩性能 - 128x128 区域', () {
      final size = 512;
      final oldRgba = Uint8List.fromList(List.filled(size * size * 4, 0));
      final newRgba = Uint8List.fromList(List.filled(size * size * 4, 0));

      // 修改 128x128 区域
      for (int y = 0; y < 128; y++) {
        for (int x = 0; x < 128; x++) {
          final idx = (y * size + x) * 4;
          newRgba[idx] = (x + y) % 256;
          newRgba[idx + 3] = 255;
        }
      }

      final stopwatch = Stopwatch()..start();
      final step = createDeltaStep(
        layerIndex: 0,
        oldRgba: oldRgba,
        newRgba: newRgba,
        canvasWidth: size,
        canvasHeight: size,
        revision: 0,
        enableCompression: true,
      );
      stopwatch.stop();

      print('\n区域: 128x128');
      print('原始大小: ${step!.originalSize} 字节 (${step.originalSize / 1024}KB)');
      print('压缩后: ${step.deltaSize} 字节 (${step.deltaSize / 1024}KB)');
      print('压缩率: ${(step.compressionRatio * 100).toStringAsFixed(1)}%');
      print('压缩耗时: ${stopwatch.elapsedMilliseconds}ms');

      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('解压缩性能', () {
      final size = 256;
      final oldRgba = Uint8List.fromList(List.filled(size * size * 4, 0));
      final newRgba = Uint8List.fromList(List.filled(size * size * 4, 0));

      // 修改 64x64 区域
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final idx = (y * size + x) * 4;
          newRgba[idx] = 128;
          newRgba[idx + 3] = 255;
        }
      }

      final step = createDeltaStep(
        layerIndex: 0,
        oldRgba: oldRgba,
        newRgba: newRgba,
        canvasWidth: size,
        canvasHeight: size,
        revision: 0,
        enableCompression: true,
      );

      final stopwatch = Stopwatch()..start();
      final restored = applyRegionDelta(newRgba, size, step!);
      stopwatch.stop();

      print('\n解压缩耗时: ${stopwatch.elapsedMilliseconds}ms');
      expect(restored, equals(oldRgba));
      expect(stopwatch.elapsedMilliseconds, lessThan(20));
    });

    test('内存占用对比（含压缩）', () {
      final canvasSize = 2048;
      final fullImageSize = canvasSize * canvasSize * 4;

      // 模拟一笔笔画：64x64 区域
      final regionSize = 64;
      final originalDeltaSize = regionSize * regionSize * 4;

      // 模拟压缩率 30%（典型 XOR delta 压缩效果）
      final compressedDeltaSize = (originalDeltaSize * 0.3).toInt();

      final fullSizeMB = fullImageSize / (1024 * 1024);
      final originalDeltaKB = originalDeltaSize / 1024;
      final compressedDeltaKB = compressedDeltaSize / 1024;

      print('\n=== 内存占用对比（含压缩）===');
      print('画布尺寸: ${canvasSize}x$canvasSize');
      print('全图 RGBA: ${fullSizeMB.toStringAsFixed(1)}MB');
      print('单笔 Delta (64x64 未压缩): ${originalDeltaKB.toStringAsFixed(1)}KB');
      print('单笔 Delta (64x64 压缩后): ${compressedDeltaKB.toStringAsFixed(1)}KB');
      print('压缩节省: ${((1 - 0.3) * 100).toStringAsFixed(0)}%');

      // 50 步 undo 对比
      final oldUndo50 = fullSizeMB * 50;
      final newUndo50Uncompressed = originalDeltaKB * 50 / 1024;
      final newUndo50Compressed = compressedDeltaKB * 50 / 1024;

      print('\n50 步 Undo:');
      print('旧方案: ${oldUndo50.toStringAsFixed(1)}MB');
      print('新方案(未压缩): ${newUndo50Uncompressed.toStringAsFixed(1)}MB');
      print('新方案(压缩): ${newUndo50Compressed.toStringAsFixed(1)}MB');
      print('总节省: ${(oldUndo50 - newUndo50Compressed).toStringAsFixed(1)}MB');
    });
  });

  group('包围盒计算 (computeDirtyRect)', () {
    test('无变化时返回空包围盒', () {
      final rgba = Uint8List.fromList(List.filled(16, 0)); // 1x1 像素
      final rect = computeDirtyRect(rgba, rgba, 1, 1);
      expect(rect.isEmpty, isTrue);
    });

    test('单个像素变化', () {
      final oldRgba = Uint8List.fromList(List.filled(64 * 4, 0)); // 4x4 全透明
      final newRgba = Uint8List.fromList(List.filled(64 * 4, 0));
      // 修改 (1, 1) 像素为红色
      final idx = (1 * 4 + 1) * 4;
      newRgba[idx] = 255; // R
      newRgba[idx + 1] = 0; // G
      newRgba[idx + 2] = 0; // B
      newRgba[idx + 3] = 255; // A

      final rect = computeDirtyRect(oldRgba, newRgba, 4, 4);
      expect(rect.isEmpty, isFalse);
      // 应该对齐到 64 像素边界，但 4x4 画布会被裁剪
      expect(rect.left, equals(0));
      expect(rect.top, equals(0));
      expect(rect.width, equals(4));
      expect(rect.height, equals(4));
    });

    test('多个像素变化 - 计算最小包围盒', () {
      final oldRgba = Uint8List.fromList(List.filled(100 * 4, 0)); // 10x10
      final newRgba = Uint8List.fromList(List.filled(100 * 4, 0));

      // 修改 (2, 3) 和 (7, 8)
      for (final pos in [(2, 3), (7, 8)]) {
        final idx = (pos.$2 * 10 + pos.$1) * 4;
        newRgba[idx] = 255;
        newRgba[idx + 3] = 255;
      }

      final rect = computeDirtyRect(oldRgba, newRgba, 10, 10);
      expect(rect.isEmpty, isFalse);
      // 64 像素对齐后，10x10 画布会被扩展到边界
      expect(rect.left, equals(0));
      expect(rect.top, equals(0));
      expect(rect.width, equals(10));
      expect(rect.height, equals(10));
    });

    test('大画布 64 像素对齐', () {
      final oldRgba = Uint8List.fromList(
        List.filled(256 * 256 * 4, 0),
      ); // 256x256
      final newRgba = Uint8List.fromList(List.filled(256 * 256 * 4, 0));

      // 修改 (65, 65) - 应该对齐到 64 边界
      final idx = (65 * 256 + 65) * 4;
      newRgba[idx] = 255;
      newRgba[idx + 3] = 255;

      final rect = computeDirtyRect(oldRgba, newRgba, 256, 256);
      expect(rect.left, equals(64)); // 对齐到 64
      expect(rect.top, equals(64));
      // (65, 65) 对齐后：minX=64, maxX=128, width=64
      expect(rect.width, equals(64));
      expect(rect.height, equals(64));
    });
  });

  group('XOR Delta 计算 (computeRegionDelta)', () {
    test('全零 XOR 全零 = 全零', () {
      final oldRgba = Uint8List.fromList(List.filled(16, 0));
      final newRgba = Uint8List.fromList(List.filled(16, 0));
      final rect = Rect.fromLTWH(0, 0, 1, 1);

      final delta = computeRegionDelta(oldRgba, newRgba, 1, rect);
      expect(delta.every((b) => b == 0), isTrue);
    });

    test('XOR 可逆性：A XOR B XOR B = A', () {
      final oldRgba = Uint8List.fromList([0, 0, 0, 0, 100, 100, 100, 255]);
      final newRgba = Uint8List.fromList([255, 0, 0, 255, 100, 100, 100, 255]);
      final rect = Rect.fromLTWH(0, 0, 2, 1);

      final delta = computeRegionDelta(oldRgba, newRgba, 2, rect);

      // 验证 delta[0-3] = old[0-3] XOR new[0-3]
      expect(delta[0], equals(0 ^ 255));
      expect(delta[1], equals(0 ^ 0));
      expect(delta[2], equals(0 ^ 0));
      expect(delta[3], equals(0 ^ 255));

      // 验证 delta[4-7] = old[4-7] XOR new[4-7] = 0（相同像素）
      expect(delta[4], equals(100 ^ 100));
      expect(delta[5], equals(100 ^ 100));
    });

    test('null oldRgba 视为全零', () {
      final newRgba = Uint8List.fromList([255, 128, 64, 255]);
      final rect = Rect.fromLTWH(0, 0, 1, 1);

      final delta = computeRegionDelta(null, newRgba, 1, rect);
      expect(delta[0], equals(255));
      expect(delta[1], equals(128));
      expect(delta[2], equals(64));
      expect(delta[3], equals(255));
    });
  });

  group('Delta 应用 (applyRegionDelta)', () {
    test('应用 Delta 恢复原像素', () {
      final oldRgba = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      final newRgba = Uint8List.fromList([100, 200, 150, 255, 50, 60, 70, 80]);
      final rect = Rect.fromLTWH(0, 0, 2, 1);

      // 计算 delta
      final delta = computeRegionDelta(oldRgba, newRgba, 2, rect);

      // 创建 delta step
      final step = UndoRegionDeltaStep(
        layerIndex: 0,
        x: 0,
        y: 0,
        width: 2,
        height: 1,
        delta: delta,
        canvasWidth: 2,
        canvasHeight: 1,
        revision: 0,
        originalSize: delta.length,
        changedPixels: 1,
      );

      // 应用 delta 恢复 oldRgba
      final restored = applyRegionDelta(newRgba, 2, step);
      expect(restored[0], equals(10));
      expect(restored[1], equals(20));
      expect(restored[2], equals(30));
      expect(restored[3], equals(40));
      expect(restored[4], equals(50));
      expect(restored[5], equals(60));
      expect(restored[6], equals(70));
      expect(restored[7], equals(80));
    });

    test('多次应用 Delta 不影响结果', () {
      final oldRgba = Uint8List.fromList([10, 20, 30, 40]);
      final newRgba = Uint8List.fromList([100, 200, 150, 255]);
      final rect = Rect.fromLTWH(0, 0, 1, 1);

      final delta = computeRegionDelta(oldRgba, newRgba, 1, rect);

      final step = UndoRegionDeltaStep(
        layerIndex: 0,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        delta: delta,
        canvasWidth: 1,
        canvasHeight: 1,
        revision: 0,
        originalSize: delta.length,
        changedPixels: 1,
      );

      // 第一次应用
      final restored1 = applyRegionDelta(newRgba, 1, step);
      // 第二次应用（会再次 XOR，结果应该是 newRgba）
      final restored2 = applyRegionDelta(restored1, 1, step);

      expect(restored2[0], equals(newRgba[0]));
      expect(restored2[1], equals(newRgba[1]));
      expect(restored2[2], equals(newRgba[2]));
      expect(restored2[3], equals(newRgba[3]));
    });
  });

  group('完整流程 (createDeltaStep)', () {
    test('无变化返回 null', () {
      final rgba = Uint8List.fromList(List.filled(64, 0));
      final step = createDeltaStep(
        layerIndex: 0,
        oldRgba: rgba,
        newRgba: Uint8List.fromList(rgba),
        canvasWidth: 2,
        canvasHeight: 2,
        revision: 0,
      );
      expect(step, isNull);
    });

    test('有变化返回有效 step', () {
      final oldRgba = Uint8List.fromList(List.filled(64, 0));
      final newRgba = Uint8List.fromList(List.filled(64, 0));
      newRgba[0] = 255;
      newRgba[3] = 255;

      final step = createDeltaStep(
        layerIndex: 0,
        oldRgba: oldRgba,
        newRgba: newRgba,
        canvasWidth: 2,
        canvasHeight: 2,
        revision: 0,
      );

      expect(step, isNotNull);
      expect(step!.layerIndex, equals(0));
      expect(step.revision, equals(0));
      expect(step.changedPixels, equals(1));
    });
  });

  group('序列化 (encode/decode)', () {
    test('序列化后反序列化数据一致', () {
      final delta = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final step = UndoRegionDeltaStep(
        layerIndex: 2,
        x: 64,
        y: 128,
        width: 32,
        height: 16,
        delta: delta,
        canvasWidth: 512,
        canvasHeight: 512,
        revision: 42,
        originalSize: 1024,
        changedPixels: 100,
        isCompressed: false,
      );

      final encoded = step.encode();
      final decoded = UndoRegionDeltaStep.decode(encoded);

      expect(decoded.layerIndex, equals(2));
      expect(decoded.x, equals(64));
      expect(decoded.y, equals(128));
      expect(decoded.width, equals(32));
      expect(decoded.height, equals(16));
      expect(decoded.canvasWidth, equals(512));
      expect(decoded.canvasHeight, equals(512));
      expect(decoded.revision, equals(42));
      expect(decoded.originalSize, equals(1024));
      expect(decoded.changedPixels, equals(100));
      expect(decoded.isCompressed, isFalse);
      expect(decoded.delta, equals(delta));
    });
  });

  group('性能测试', () {
    test('包围盒计算性能 - 1024x1024 画布', () {
      final size = 1024;
      final oldRgba = Uint8List.fromList(List.filled(size * size * 4, 0));
      final newRgba = Uint8List.fromList(List.filled(size * size * 4, 0));

      // 模拟一笔画线：修改 100 个像素
      for (int i = 0; i < 100; i++) {
        final idx = (i * size + i) * 4;
        newRgba[idx] = 255;
        newRgba[idx + 3] = 255;
      }

      final stopwatch = Stopwatch()..start();
      final rect = computeDirtyRect(oldRgba, newRgba, size, size);
      stopwatch.stop();

      print(
        '包围盒计算 (${size}x$size, 100像素变化): ${stopwatch.elapsedMilliseconds}ms',
      );
      print('包围盒: ${rect.left}, ${rect.top} ${rect.width}x${rect.height}');

      expect(rect.isEmpty, isFalse);
      expect(stopwatch.elapsedMilliseconds, lessThan(100)); // 应该 < 100ms
    });

    test('Delta 计算性能 - 128x128 区域', () {
      final canvasSize = 512;
      final regionSize = 128;
      final oldRgba = Uint8List.fromList(
        List.filled(canvasSize * canvasSize * 4, 0),
      );
      final newRgba = Uint8List.fromList(
        List.filled(canvasSize * canvasSize * 4, 0),
      );

      // 修改 128x128 区域
      for (int y = 0; y < regionSize; y++) {
        for (int x = 0; x < regionSize; x++) {
          final idx = (y * canvasSize + x) * 4;
          newRgba[idx] = (x + y) % 256;
          newRgba[idx + 3] = 255;
        }
      }

      final rect = Rect.fromLTWH(
        0,
        0,
        regionSize.toDouble(),
        regionSize.toDouble(),
      );

      final stopwatch = Stopwatch()..start();
      final delta = computeRegionDelta(oldRgba, newRgba, canvasSize, rect);
      stopwatch.stop();

      final deltaSizeKB = delta.length / 1024;
      final fullSizeKB = canvasSize * canvasSize * 4 / 1024;
      final compressionRatio = deltaSizeKB / fullSizeKB * 100;

      print('Delta 计算 (128x128 区域): ${stopwatch.elapsedMilliseconds}ms');
      print('Delta 大小: ${deltaSizeKB.toStringAsFixed(1)}KB');
      print('全图大小: ${fullSizeKB.toStringAsFixed(1)}KB');
      print('区域占比: ${compressionRatio.toStringAsFixed(1)}%');

      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('Delta 应用性能 - 128x128 区域', () {
      final canvasSize = 512;
      final regionSize = 128;
      final currentRgba = Uint8List.fromList(
        List.filled(canvasSize * canvasSize * 4, 0),
      );

      // 创建 delta
      final delta = Uint8List.fromList(
        List.filled(regionSize * regionSize * 4, 255),
      );

      final step = UndoRegionDeltaStep(
        layerIndex: 0,
        x: 0,
        y: 0,
        width: regionSize,
        height: regionSize,
        delta: delta,
        canvasWidth: canvasSize,
        canvasHeight: canvasSize,
        revision: 0,
        originalSize: delta.length,
        changedPixels: regionSize * regionSize,
      );

      final stopwatch = Stopwatch()..start();
      final result = applyRegionDelta(currentRgba, canvasSize, step);
      stopwatch.stop();

      print('Delta 应用 (128x128 区域): ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
      expect(result.length, equals(canvasSize * canvasSize * 4));
    });

    test('内存占用对比', () {
      final canvasSize = 2048;
      final fullImageSize = canvasSize * canvasSize * 4; // RGBA

      // 模拟一笔笔画：假设修改了 64x64 区域
      final regionSize = 64;
      final deltaSize = regionSize * regionSize * 4;

      final fullSizeMB = fullImageSize / (1024 * 1024);
      final deltaSizeKB = deltaSize / 1024;

      print('\n=== 内存占用对比 ===');
      print('画布尺寸: ${canvasSize}x$canvasSize');
      print('全图 RGBA: ${fullSizeMB.toStringAsFixed(1)}MB');
      print('单笔 Delta (64x64): ${deltaSizeKB.toStringAsFixed(1)}KB');
      print(
        '内存节省: ${((1 - deltaSize / fullImageSize) * 100).toStringAsFixed(1)}%',
      );

      // 50 步 undo 对比
      final oldUndo50 = fullSizeMB * 50;
      final newUndo50 = deltaSizeKB * 50 / 1024; // 转为 MB

      print('\n50 步 Undo:');
      print('旧方案: ${oldUndo50.toStringAsFixed(1)}MB');
      print('新方案: ${newUndo50.toStringAsFixed(1)}MB');
      print('节省: ${(oldUndo50 - newUndo50).toStringAsFixed(1)}MB');
    });
  });

  group('Undo/Redo 循环测试', () {
    test('多次 undo/redo 数据一致性', () {
      final size = 16;
      final states = <Uint8List>[];

      // 创建初始状态
      states.add(Uint8List.fromList(List.filled(size * size * 4, 0)));

      // 创建 5 个不同状态
      for (int i = 1; i <= 5; i++) {
        final newState = Uint8List.fromList(states.last);
        // 修改中心像素
        final idx = (size ~/ 2 * size + size ~/ 2) * 4;
        newState[idx] = i * 50;
        newState[idx + 3] = 255;
        states.add(newState);
      }

      // 创建 delta steps
      final deltaSteps = <UndoRegionDeltaStep>[];
      for (int i = 1; i < states.length; i++) {
        final step = createDeltaStep(
          layerIndex: 0,
          oldRgba: states[i - 1],
          newRgba: states[i],
          canvasWidth: size,
          canvasHeight: size,
          revision: i,
        );
        if (step != null) {
          deltaSteps.add(step);
        }
      }

      // 从最终状态开始 undo
      var currentRgba = Uint8List.fromList(states.last);

      for (int i = deltaSteps.length - 1; i >= 0; i--) {
        final step = deltaSteps[i];
        currentRgba = applyRegionDelta(currentRgba, size, step);

        // 验证恢复到的状态
        final expectedState = states[i];
        expect(
          currentRgba,
          equals(expectedState),
          reason: 'Undo step $i should restore to state $i',
        );
      }

      // Redo
      for (int i = 0; i < deltaSteps.length; i++) {
        // 计算 redo delta（反向）
        final rect = deltaSteps[i].rect;
        final redoDelta = computeRegionDelta(
          states[i],
          states[i + 1],
          size,
          rect,
        );

        final redoStep = UndoRegionDeltaStep(
          layerIndex: 0,
          x: deltaSteps[i].x,
          y: deltaSteps[i].y,
          width: deltaSteps[i].width,
          height: deltaSteps[i].height,
          delta: redoDelta,
          canvasWidth: size,
          canvasHeight: size,
          revision: i + 1,
          originalSize: redoDelta.length,
          changedPixels: deltaSteps[i].changedPixels,
        );

        currentRgba = applyRegionDelta(currentRgba, size, redoStep);

        expect(
          currentRgba,
          equals(states[i + 1]),
          reason: 'Redo step $i should restore to state ${i + 1}',
        );
      }
    });
  });
}
