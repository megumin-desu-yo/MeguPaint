# 笔刷系统添加与使用指南

> 适用于 `lib/domain/brush` 下的新一代笔刷体系。本文档覆盖架构、开发流程以及在 UI 中的使用方法。

## 1. 架构速览

| 层级 | 关键文件 | 说明 |
| --- | --- | --- |
| 输入采样 | `lib/presentation/providers/drawing_provider.dart` | `DrawPoint` 记录坐标、压力、倾斜、旋转、速度、时间戳，并通过稳定算法输出轨迹。 |
| 引擎调度 | `lib/domain/brush/brush_engine.dart` / `brush_system.dart` | `BrushEngine` 抽象提供通用算法工具，`BrushSystem` 统一注册引擎、管理预设、驱动渲染。 |
| 预设配置 | `lib/domain/brush/brush_preset.dart` / `default_presets.dart` | 描述笔刷外观、动态映射、抖动及稳定参数，附带 10 个内置预设。 |
| 渲染核心 | `lib/domain/brush/stamp.dart` / `stamp_renderer.dart` | 引擎输出 `Stamp` 序列，由 `StampRenderer` 做径向渐变、椭圆变形或批量点渲染。 |
| UI / 状态 | `lib/ui/widgets/brush_selector.dart`、`canvas_screen.dart` | 右侧面板提供预设选择/调整，`_RasterPainter`+`BrushSystem` 负责实时预览与烧录。 |

## 2. 数据流

1. **输入采样**：指针事件 → `DrawingNotifier` 生成 `DrawPoint` 序列（包含压力/倾斜等）。
2. **参数选择**：`BrushPresetNotifier` 提供当前预设，右侧面板可即时修改。
3. **引擎生成**：`BrushSystem.generateStamps()` 根据点序列与预设调用对应引擎输出 `Stamp`。
4. **即时预览**：`_RasterPainter` 将 `Stamp` 渲染至离屏 `PictureRecorder`，绘制到画布。
5. **烧录图层**：笔画结束后 `burnStrokeToLayer()` 叠加至 `ui.Image` 像素，提交给 `LayerNotifier`。

## 3. 核心模块说明

### 3.1 DrawPoint 与输入增强
- 位置：`lib/presentation/providers/drawing_provider.dart`
- 字段：`pressure / tilt / rotation / velocity / timestamp`，在 `_extractPressure` 与稳定算法中填充。

### 3.2 BrushEngine 抽象
- 位置：`lib/domain/brush/brush_engine.dart`
- 职责：
  - `generateStamps()`：从稳定后的 `DrawPoint` 序列生成 `Stamp`。
  - 工具方法：`applyDynamicMapping`、`applyJitter`、`applyScatter`、`applyColorJitter`、`interpolatePositions` 等，统一处理压感曲线、抖动与插值。
- 注册：通过 `BrushEngineRegistry.register()` 在 `BrushSystem._initialize()` 中注册。

### 3.3 Stamp / StampRenderer
- `Stamp`：描述单个“印”的位置、尺寸、硬度、圆度、颜色、旋转。
- `StampRenderer.renderStamps()`：根据硬度决定使用径向渐变或硬边绘制；在特定条件下可使用 `drawPoints` 批量优化。

### 3.4 BrushPreset / DefaultPresets
- `BrushPreset`：
  - `engineType` 决定底层引擎。
  - `DynamicMapping`（大小/不透明/圆度等）结合 `ResponseCurve` 控制压力、速度、倾斜响应。
  - `JitterSettings` 控制尺寸/角度/颜色抖动。
  - `stabilization` & `stabilizationFactor` 控制画笔平滑。
- `DefaultPresets`：内置硬/柔圆、2B/HB 铅笔、喷枪、马克笔、墨水、书法、速写、干笔共 10 款；可作为自定义预设的模板。

### 3.5 BrushSystem 门面
- 位置：`lib/domain/brush/brush_system.dart`
- 功能：
  - 注册所有引擎与内置预设。
  - `generateStamps()` 调用对应 `BrushEngine`。
  - `renderStroke()` 封装“生成 + 渲染”流程，供 `_RasterPainter` 与 `burnStrokeToLayer()` 调用。
  - 管理用户自定义预设（导入、导出、添加、删除）。

### 3.6 状态管理与 UI
- Providers：
  - `drawingProvider`：维护当前笔画点列。
  - `brushProvider`：兼容旧 UI 的 `BrushSettings`。（仍用于部分滑块，颜色等属性会同步到预设。）
  - `brushPresetProvider`：新系统的核心，保存当前选中预设及全部预设列表。
- UI：
  - `BrushSelectorPanel`：展示预设、参数调节、保存/删除自定义预设。
  - `CanvasScreen`：右侧面板集成 `BrushSelectorPanel`；中心 `CustomPaint` 使用 `_RasterPainter` 进行实时预览。

## 4. 如何新增笔刷引擎

1. **创建引擎类**
   - 在 `lib/domain/brush/engines/` 下新建文件，例如 `charcoal_engine.dart`。
   - 继承 `BrushEngine`，实现 `id / name / engineType / generateStamps()`。
   - 使用 `interpolatePositions()` 获得均匀取样点；结合 `applyDynamicMapping()`、`applyColorJitter()` 等辅助工具实现自定义风格。

2. **注册引擎**
   ```dart
   // brush_system.dart / _initialize()
   _registry.register(CharcoalEngine());
   ```

3. **创建默认预设（可选）**
   - 在 `default_presets.dart` 内新增常量。
   - 指定 `engineType: BrushEngineType.charcoal`，配置尺寸、硬度、动态映射与抖动参数。

4. **更新枚举**
   - 如需新的 `BrushEngineType`，在 `brush_preset.dart` 中的 `enum BrushEngineType` 添加条目，并为 `BrushSelectorPanel` 的 `_engineMeta` 配置图标与名称。

5. **测试**
   - 运行应用，使用右侧面板选择新预设，检查实时预览与烧录是否符合预期。

## 5. 添加 / 编辑笔刷预设

### 5.1 静态方式（代码）
1. 在 `default_presets.dart` 中定义 `const BrushPreset` 常量。
2. 配置 `DynamicMapping`：如 `ResponseCurve.linear`、`ResponseCurve.soft` 或自定义控制点。
3. 在 `BrushSystem._initialize()` 内 ` _presets.addAll(DefaultPresets.all);` 的列表里即可自动加载。

### 5.2 运行时（UI）zd
1. 进入画布 → 右侧“笔刷”面板。
2. 选择任一预设，调整大小/不透明度/硬度/流量等参数。
3. 点击保存图标 → 输入名称 → 自动生成 `user_xxx` ID 并写入 `BrushPresetNotifier`。
4. 长按自定义预设可删除。

> **注意**：UI 中的颜色/宽度滑块仍会调用 `BrushSettings`，系统已经在 `BrushPresetNotifier` 内同步颜色变更，确保画笔与预设保持一致。

## 6. 画布中如何使用笔刷

1. **选择预设**：通过 `BrushSelectorPanel` 或快捷键。
2. **实时调整**：滑块变更即时作用于 `brushPresetProvider`，并通过 `_RasterPainter` 的 `currentPreset` 实时预览。
3. **绘制与烧录**：
   - `_RasterPainter` 调用 `BrushSystem.renderStroke()` 渲染实时预览和 pending strokes。
   - `_burnStroke()` 在笔画结束时调用 `burnStrokeToLayer()`，将 `Stamp` 渲染结果叠加到 `ui.Image` 像素。
4. **图层权限**：`_canEditActiveLayer()` 在每次绘制前验证当前用户对图层的签名权限，避免误绘。

## 7. 关键注意事项

1. **权限缓存**：`_canEditActiveLayer()` 已使用“图层 ID + 域图层数量 + 用户名”作为缓存 key，确保图层同步或用户切换后即时刷新。
2. **颜色同步**：颜色选择器与吸管 (`_pickColorAtPosition`) 均会同步到 `BrushPresetNotifier`，保证预设颜色最新。
3. **性能提示**：
   - `StampRenderer.renderStampsFast()` 会在硬边圆笔、无旋转时走批量路径。
   - 喷枪/铅笔等需要大量粒子时，可视情况调整 `spacing` 与 `flow` 以平衡性能。
4. **调试模式**：开启设置中的调试开关后，可在后续版本扩展底部状态栏/FPS 信息（当前为占位）。

## 8. FAQ

- **为什么新建预设后无法持久化？**
  - 需调用 `BrushSystem.exportUserPresets()` 将列表写入本地配置；启动时再 `importPresets()`。
- **实时预览与最终效果不一致？**
  - 确保 `pendingStrokes` 中的 `BrushPreset` 与当前预设同步；若在绘制中切换预设，建议等待当前笔画烧录后再切换。
- **如何实现压感关闭？**
  - 在预设中设置 `pressureEnabled = false`，或在 UI 中关闭“压感”开关，`DynamicMapping` 会退化为常量值。

---
如需更深入的算法说明，请参考 `笔刷.txt` 设计文档；实现细节可在相关源码文件中查看注释。希望本指南能帮助你快速添加、调试并使用笔刷。
