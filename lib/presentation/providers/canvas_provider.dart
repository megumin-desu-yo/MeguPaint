import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 画布状态
class CanvasState {
  final String name;
  final int width;
  final int height;
  final bool isInitialized;

  const CanvasState({
    this.name = '',
    this.width = 0,
    this.height = 0,
    this.isInitialized = false,
  });

  CanvasState copyWith({
    String? name,
    int? width,
    int? height,
    bool? isInitialized,
  }) {
    return CanvasState(
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// 画布状态管理器
class CanvasNotifier extends StateNotifier<CanvasState> {
  CanvasNotifier() : super(const CanvasState());

  /// 创建新画布
  Future<void> createNew({
    required String name,
    required int width,
    required int height,
  }) async {
    state = CanvasState(
      name: name,
      width: width,
      height: height,
      isInitialized: true,
    );
  }

  /// 清空画布
  void clear() {
    state = const CanvasState();
  }
}

/// 画布Provider
final canvasProvider = StateNotifierProvider<CanvasNotifier, CanvasState>(
  (ref) => CanvasNotifier(),
);
