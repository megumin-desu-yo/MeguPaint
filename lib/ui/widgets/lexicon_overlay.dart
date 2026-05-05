import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/providers/lexicon_provider.dart';
import '../../presentation/models/lexicon_record.dart';
import 'app_toast.dart';

/// 词库管理界面 (作为覆盖层显示)
class LexiconOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const LexiconOverlay({super.key, required this.onClose});

  @override
  ConsumerState<LexiconOverlay> createState() => _LexiconOverlayState();
}

class _LexiconOverlayState extends ConsumerState<LexiconOverlay>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _itemController = TextEditingController();
  final Set<String> _selectedKeys = {};
  final Set<String> _selectedItemKeys = {};
  bool _isSelectAll = false;
  bool _isItemsSelectAll = false;

  String? _editingLexiconKey;
  String? _focusingItemKey; // 当前获取焦点的词条Key
  final FocusNode _addRowFocusNode = FocusNode(); // 新增行的焦点控制
  final Map<String, FocusNode> _itemFocusNodes = {}; // 缓存每行的 FocusNode
  final Map<String, TextEditingController> _itemControllers =
      {}; // 缓存每行的 Controller

  FocusNode _getFocusNode(String key) {
    return _itemFocusNodes.putIfAbsent(key, () => FocusNode());
  }

  TextEditingController _getController(String key) {
    return _itemControllers.putIfAbsent(key, () => TextEditingController());
  }

  // 动画控制
  late final AnimationController _animationController;
  late final Animation<Offset> _editPanelAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _editPanelAnimation =
        Tween<Offset>(
          begin: const Offset(-0.1, 0.0), // 稍微偏移
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _itemController.dispose();
    _animationController.dispose();
    _addRowFocusNode.dispose();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    for (final controller in _itemControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _closeEditPanel() async {
    await _animationController.reverse();
    setState(() {
      _editingLexiconKey = null;
      _selectedItemKeys.clear();
      _isItemsSelectAll = false;
      _focusingItemKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lexiconState = ref.watch(lexiconProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth * 0.3;

    return GestureDetector(
      onTap: widget.onClose, // 点击背景关闭整个侧边栏
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 词库管理面板 (左侧)
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: GestureDetector(
                  onTap: () {
                    // 点击词库管理面板时，如果词条编辑面板有焦点，清除它
                    if (_focusingItemKey != null) {
                      setState(() => _focusingItemKey = null);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 10,
                          offset: const Offset(4, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildLexiconList(lexiconState),
                    ),
                  ),
                ),
              ),
              // 词库编辑面板 (滑入动画)
              if (_editingLexiconKey != null)
                Positioned(
                  left: 16 + panelWidth + 24,
                  top: 0,
                  bottom: 0,
                  width: panelWidth,
                  child: SlideTransition(
                    position: _editPanelAnimation,
                    child: GestureDetector(
                      onTap: () {}, // 拦截点击，防止关闭侧边栏
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(25),
                              blurRadius: 10,
                              offset: const Offset(4, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _buildItemList(lexiconState),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLexiconList(LexiconState lexiconState) {
    return Column(
      children: [
        // 顶部输入区域 (词库)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('词库管理', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '词库名称',
                  hintText: '输入词库名称',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '词库描述',
                  hintText: '输入词库描述',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _handleAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建词库'),
                ),
              ),
            ],
          ),
        ),
        // 批量操作 (词库)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: _isSelectAll,
                onChanged: (value) => _handleSelectAll(value ?? false),
              ),
              const Text('全选'),
              const Spacer(),
              if (_selectedKeys.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: _handleBatchDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: Text('删除(${_selectedKeys.length})'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _handleExport,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('导出'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        // 词库列表
        Expanded(
          child: lexiconState.records.isEmpty
              ? _buildEmptyState('暂无词库')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: lexiconState.records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final record = lexiconState.records[index];
                    final isSelected = _selectedKeys.contains(record.key);
                    return _buildLexiconTile(record, isSelected);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildItemList(LexiconState lexiconState) {
    final record = lexiconState.records.firstWhere(
      (r) => r.key == _editingLexiconKey,
      orElse: () => LexiconRecord(name: '未知'),
    );

    return Column(
      children: [
        // 顶部区域 (词条)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '编辑词库: ${record.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _closeEditPanel,
                  ),
                ],
              ),
            ],
          ),
        ),
        // 批量操作 (词条)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: _isItemsSelectAll,
                onChanged: (value) =>
                    _handleItemsSelectAll(value ?? false, record.items),
              ),
              const Text('全选'),
              const Spacer(),
              if (_selectedItemKeys.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: _handleItemsBatchDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: Text('删除(${_selectedItemKeys.length})'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        // 词条列表 (Excel 风格)
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: record.items.length + 1, // 最后一行是待新增行
            itemBuilder: (context, index) {
              if (index < record.items.length) {
                final item = record.items[index];
                final isSelected = _selectedItemKeys.contains(item.key);
                final focusNode = _getFocusNode(item.key);
                final nextItemKey = (index + 1 < record.items.length)
                    ? record.items[index + 1].key
                    : null;

                return _buildExcelRow(
                  item,
                  isSelected,
                  focusNode,
                  nextItemKey: nextItemKey,
                );
              } else {
                // 最后一行：快速添加行
                return _buildExcelAddRow();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExcelRow(
    LexiconItem item,
    bool isSelected,
    FocusNode focusNode, {
    String? nextItemKey,
  }) {
    final controller = _getController(item.key);
    // 仅在非编辑状态同步内容，避免 build 时重置导致光标跳动
    if (!focusNode.hasFocus && controller.text != item.content) {
      controller.value = TextEditingValue(
        text: item.content,
        selection: TextSelection.fromPosition(
          TextPosition(offset: item.content.length),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        color: _focusingItemKey == item.key
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(30)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Checkbox(
              value: isSelected,
              onChanged: (value) => _handleItemSelect(item.key, value ?? false),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: 1,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              onTap: () {
                if (_focusingItemKey != item.key) {
                  setState(() => _focusingItemKey = item.key);
                }
              },
              onChanged: (value) async {
                await ref
                    .read(lexiconProvider.notifier)
                    .updateItem(_editingLexiconKey!, item.key, value);
              },
              onSubmitted: (value) async {
                // 兼容 Windows (\r\n) 和 Unix (\n) 换行符
                final normalizedValue = value
                    .replaceAll('\r\n', '\n')
                    .replaceAll('\r', '\n');
                if (normalizedValue.contains('\n')) {
                  final lines = normalizedValue
                      .split('\n')
                      .where((l) => l.trim().isNotEmpty)
                      .toList();
                  if (lines.isNotEmpty) {
                    // 更新当前行内容为第一行
                    await ref
                        .read(lexiconProvider.notifier)
                        .updateItem(
                          _editingLexiconKey!,
                          item.key,
                          lines[0].trim(),
                        );
                    // 批量添加其余行
                    for (int i = 1; i < lines.length; i++) {
                      await ref
                          .read(lexiconProvider.notifier)
                          .addItem(_editingLexiconKey!, lines[i].trim());
                    }
                    // 回车逻辑：拆分后直接跳到下一行/新行
                    if (nextItemKey != null) {
                      setState(() => _focusingItemKey = nextItemKey);
                      _getFocusNode(nextItemKey).requestFocus();
                      return;
                    }
                    await ref
                        .read(lexiconProvider.notifier)
                        .addItem(_editingLexiconKey!, "");
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final updatedRecord = ref
                          .read(lexiconProvider)
                          .records
                          .firstWhere((r) => r.key == _editingLexiconKey);
                      if (updatedRecord.items.isNotEmpty) {
                        final newItemKey = updatedRecord.items.last.key;
                        setState(() => _focusingItemKey = newItemKey);
                        _getFocusNode(newItemKey).requestFocus();
                      }
                    });
                    return;
                  }
                }

                // 单行正常保存逻辑
                if (normalizedValue.trim().isNotEmpty) {
                  await ref
                      .read(lexiconProvider.notifier)
                      .updateItem(
                        _editingLexiconKey!,
                        item.key,
                        normalizedValue.trim(),
                      );
                } else {
                  await ref
                      .read(lexiconProvider.notifier)
                      .updateItem(_editingLexiconKey!, item.key, "");
                }

                if (nextItemKey != null) {
                  setState(() => _focusingItemKey = nextItemKey);
                  _getFocusNode(nextItemKey).requestFocus();
                } else {
                  await ref
                      .read(lexiconProvider.notifier)
                      .addItem(_editingLexiconKey!, "");
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final updatedRecord = ref
                        .read(lexiconProvider)
                        .records
                        .firstWhere((r) => r.key == _editingLexiconKey);
                    if (updatedRecord.items.isNotEmpty) {
                      final newItemKey = updatedRecord.items.last.key;
                      setState(() => _focusingItemKey = newItemKey);
                      _getFocusNode(newItemKey).requestFocus();
                    }
                  });
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => ref
                .read(lexiconProvider.notifier)
                .removeItem(_editingLexiconKey!, item.key),
          ),
        ],
      ),
    );
  }

  Widget _buildExcelAddRow() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withAlpha(50),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 48,
            child: Icon(Icons.add, size: 18, color: Colors.grey),
          ),
          Expanded(
            child: TextField(
              controller: _itemController,
              focusNode: _addRowFocusNode,
              maxLines: 1,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                hintText: '输入或粘贴词条...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              onChanged: (value) async {
                // 兼容 Windows (\r\n) 和 Unix (\n) 换行符
                final normalizedValue = value
                    .replaceAll('\r\n', '\n')
                    .replaceAll('\r', '\n');
                if (normalizedValue.contains('\n')) {
                  final lines = normalizedValue
                      .split('\n')
                      .where((l) => l.trim().isNotEmpty)
                      .toList();
                  if (lines.isNotEmpty) {
                    for (final line in lines) {
                      await ref
                          .read(lexiconProvider.notifier)
                          .addItem(_editingLexiconKey!, line.trim());
                    }
                    _itemController.clear();
                    _addRowFocusNode.requestFocus();
                  }
                }
              },
              onSubmitted: (value) async {
                // 兼容 Windows (\r\n) 和 Unix (\n) 换行符
                final normalizedValue = value
                    .replaceAll('\r\n', '\n')
                    .replaceAll('\r', '\n');
                if (normalizedValue.contains('\n')) {
                  final lines = normalizedValue
                      .split('\n')
                      .where((l) => l.trim().isNotEmpty)
                      .toList();
                  if (lines.isNotEmpty) {
                    for (final line in lines) {
                      await ref
                          .read(lexiconProvider.notifier)
                          .addItem(_editingLexiconKey!, line.trim());
                    }
                    _itemController.clear();
                    return; // 处理完成后返回
                  }
                }

                // 单行正常保存逻辑
                if (normalizedValue.trim().isNotEmpty) {
                  await ref
                      .read(lexiconProvider.notifier)
                      .addItem(_editingLexiconKey!, normalizedValue.trim());
                  _itemController.clear();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).disabledColor,
        ),
      ),
    );
  }

  Widget _buildLexiconTile(LexiconRecord record, bool isSelected) {
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: isSelected,
        onChanged: (value) => _handleSelect(record.key, value ?? false),
      ),
      title: Text(
        record.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        record.description.isNotEmpty ? record.description : '暂无描述',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.list_alt, size: 20),
            tooltip: '编辑词条',
            onPressed: () {
              setState(() {
                _editingLexiconKey = record.key;
                _selectedItemKeys.clear();
                _isItemsSelectAll = false;
                _focusingItemKey = null;
              });
              _animationController.forward();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) => _handleMenuAction(value, record),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('重命名/描述')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }

  void _handleItemSelect(String key, bool selected) {
    setState(() {
      if (selected) {
        _selectedItemKeys.add(key);
      } else {
        _selectedItemKeys.remove(key);
      }
    });
  }

  void _handleItemsSelectAll(bool selected, List<LexiconItem> items) {
    setState(() {
      _isItemsSelectAll = selected;
      if (selected) {
        _selectedItemKeys.clear();
        _selectedItemKeys.addAll(items.map((i) => i.key));
      } else {
        _selectedItemKeys.clear();
      }
    });
  }

  void _handleItemsBatchDelete() {
    ref
        .read(lexiconProvider.notifier)
        .removeItems(_editingLexiconKey!, _selectedItemKeys.toList());
    setState(() {
      _selectedItemKeys.clear();
      _isItemsSelectAll = false;
    });
  }

  void _handleAdd() {
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    if (name.isEmpty) {
      toast.error(context, '请输入词库名称');
      return;
    }

    final record = LexiconRecord(name: name, description: description);
    ref.read(lexiconProvider.notifier).addRecord(record);
    if (mounted) toast.success(context, '已新建');

    _nameController.clear();
    _descriptionController.clear();
  }

  void _handleSelect(String key, bool selected) {
    setState(() {
      if (selected) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
      _isSelectAll =
          _selectedKeys.length == ref.read(lexiconProvider).records.length;
    });
  }

  void _handleSelectAll(bool selected) {
    setState(() {
      _isSelectAll = selected;
      if (selected) {
        _selectedKeys.clear();
        _selectedKeys.addAll(
          ref.read(lexiconProvider).records.map((r) => r.key),
        );
      } else {
        _selectedKeys.clear();
      }
    });
  }

  void _handleBatchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedKeys.length} 条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(lexiconProvider.notifier)
          .removeRecords(_selectedKeys.toList());
      setState(() {
        _selectedKeys.clear();
        _isSelectAll = false;
      });
      if (mounted) toast.success(context, '已删除');
    }
  }

  void _handleExport() {
    final jsonStr = ref.read(lexiconProvider.notifier).exportToJson();
    Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) toast.success(context, '已导出到剪贴板');
  }

  void _handleMenuAction(String action, LexiconRecord record) async {
    switch (action) {
      case 'edit':
        _showEditDialog(record);
        break;
      case 'delete':
        await ref.read(lexiconProvider.notifier).removeRecord(record.key);
        if (mounted) toast.success(context, '已删除');
        break;
    }
  }

  void _showEditDialog(LexiconRecord record) {
    final nameController = TextEditingController(text: record.name);
    final descriptionController = TextEditingController(
      text: record.description,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑词库'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '词库名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '词库描述',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newRecord = record.copyWith(
                name: nameController.text.trim(),
                description: descriptionController.text.trim(),
              );
              await ref.read(lexiconProvider.notifier).updateRecord(newRecord);
              if (context.mounted) {
                Navigator.pop(context);
                toast.success(context, '已更新');
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
