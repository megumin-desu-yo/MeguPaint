import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'app_toast.dart';

/// 复盘管理界面 (作为覆盖层显示，仿照词库管理布局)
class ReplayOverlay extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const ReplayOverlay({super.key, required this.onClose});

  @override
  ConsumerState<ReplayOverlay> createState() => _ReplayOverlayState();
}

class _ReplayOverlayState extends ConsumerState<ReplayOverlay>
    with SingleTickerProviderStateMixin {
  List<dynamic> _history = [];
  final Set<int> _selectedIndices = {}; // 选中的复盘索引
  bool _isSelectAll = false;

  int? _viewingIndex; // 当前查看的复盘索引
  List<dynamic>? _replayData; // 当前复盘数据

  // 动画控制
  late final AnimationController _animationController;
  late final Animation<Offset> _detailPanelAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _detailPanelAnimation =
        Tween<Offset>(begin: const Offset(0.1, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final box = await Hive.openBox('replays');
      final history = box.get('history', defaultValue: []);
      setState(() {
        _history = List<dynamic>.from(history);
      });
    } catch (e) {
      debugPrint('加载复盘历史失败: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final box = await Hive.openBox('replays');
      await box.put('history', _history);
    } catch (e) {
      debugPrint('保存复盘历史失败: $e');
    }
  }

  void _selectReplay(int index) {
    final record = _history[index];
    setState(() {
      _viewingIndex = index;
      _replayData = record['data'];
    });
    _animationController.forward();
  }

  void _closeDetailPanel() async {
    await _animationController.reverse();
    setState(() {
      _viewingIndex = null;
      _replayData = null;
    });
  }

  void _importReplayData() {
    _showPasteDialog();
  }

  void _showPasteDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴复盘数据'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '在此粘贴从服务器或局末收到的 JSON 数据',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final data = jsonDecode(controller.text);
                final replayList = data is List ? data : [data];
                final newRecord = {
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'data': replayList,
                };
                setState(() {
                  _history.insert(0, newRecord);
                });
                await _saveHistory();
                if (context.mounted) {
                  Navigator.pop(context);
                  toast.success(context, '已导入');
                }
              } catch (e) {
                toast.error(context, '解析失败: $e');
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  void _handleSelect(int index, bool selected) {
    setState(() {
      if (selected) {
        _selectedIndices.add(index);
      } else {
        _selectedIndices.remove(index);
      }
      _isSelectAll = _selectedIndices.length == _history.length;
    });
  }

  void _handleSelectAll(bool selected) {
    setState(() {
      _isSelectAll = selected;
      if (selected) {
        _selectedIndices.clear();
        _selectedIndices.addAll(List.generate(_history.length, (i) => i));
      } else {
        _selectedIndices.clear();
      }
    });
  }

  Future<void> _handleBatchDelete() async {
    if (_selectedIndices.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIndices.length} 条复盘记录吗？'),
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
      final indices = _selectedIndices.toList()..sort((a, b) => b - a);
      for (final idx in indices) {
        _history.removeAt(idx);
      }
      await _saveHistory();
      setState(() {
        _selectedIndices.clear();
        _isSelectAll = false;
      });
      if (mounted) toast.success(context, '已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth * 0.3;

    return GestureDetector(
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 左侧：复盘列表面板
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: GestureDetector(
                  onTap: () {},
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
                      child: _buildHistoryListPanel(),
                    ),
                  ),
                ),
              ),
              // 右侧：复盘详情面板 (占用剩余空间)
              if (_viewingIndex != null)
                Positioned(
                  left: 16 + panelWidth + 24,
                  top: 0,
                  bottom: 0,
                  right: 16,
                  child: SlideTransition(
                    position: _detailPanelAnimation,
                    child: GestureDetector(
                      onTap: () {},
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
                          child: _buildReplayDetailPanel(),
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

  /// 左侧复盘列表面板
  Widget _buildHistoryListPanel() {
    return Column(
      children: [
        // 顶部标题区域
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
                  Text('复盘列表', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _importReplayData,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('导入复盘'),
              ),
            ],
          ),
        ),
        // 批量操作区域
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: _isSelectAll,
                onChanged: _history.isEmpty
                    ? null
                    : (value) => _handleSelectAll(value ?? false),
              ),
              const Text('全选'),
              const Spacer(),
              if (_selectedIndices.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: _handleBatchDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: Text('删除(${_selectedIndices.length})'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        // 复盘列表
        Expanded(
          child: _history.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final record = _history[index];
                    final isSelected = _selectedIndices.contains(index);
                    return _buildReplayTile(record, index, isSelected);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_edu_outlined,
            size: 64,
            color: Theme.of(context).disabledColor.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无复盘数据',
            style: TextStyle(
              color: Theme.of(context).disabledColor,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplayTile(dynamic record, int index, bool isSelected) {
    final timestamp = record['timestamp'] as int;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final data = record['data'] as List;

    return ListTile(
      dense: true,
      leading: Checkbox(
        value: isSelected,
        onChanged: (value) => _handleSelect(index, value ?? false),
      ),
      title: Text(
        '复盘记录 $dateStr',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('包含 ${data.length} 条词条轨迹'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.visibility, size: 20),
            tooltip: '查看详情',
            onPressed: () => _selectReplay(index),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) => _handleMenuAction(value, index),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action, int index) async {
    switch (action) {
      case 'delete':
        setState(() {
          _history.removeAt(index);
          _selectedIndices.remove(index);
        });
        await _saveHistory();
        if (mounted) toast.success(context, '已删除');
        break;
    }
  }

  /// 右侧复盘详情面板
  Widget _buildReplayDetailPanel() {
    final record = _history[_viewingIndex!];
    final timestamp = record['timestamp'] as int;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        // 顶部标题区域
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '复盘详情 - $dateStr',
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _closeDetailPanel,
              ),
            ],
          ),
        ),
        // 复盘轨迹列表
        Expanded(
          child: _replayData == null || _replayData!.isEmpty
              ? Center(
                  child: Text(
                    '无轨迹数据',
                    style: TextStyle(color: Theme.of(context).disabledColor),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _replayData!.length,
                  itemBuilder: (context, index) {
                    final track = _replayData![index];
                    return _buildTrackCard(track);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTrackCard(dynamic track) {
    return _TrackCard(track: track);
  }
}

/// 轨迹卡片组件（独立 StatefulWidget 管理滚动状态）
class _TrackCard extends StatefulWidget {
  final dynamic track;

  const _TrackCard({required this.track});

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateScrollState);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollState);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      final newCanScrollLeft = currentScroll > 10;
      final newCanScrollRight = currentScroll < maxScroll - 10;
      if (newCanScrollLeft != _canScrollLeft ||
          newCanScrollRight != _canScrollRight) {
        setState(() {
          _canScrollLeft = newCanScrollLeft;
          _canScrollRight = newCanScrollRight;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final originWord = track['originWord'] ?? '未知';
    final originOwner = track['originOwnerName'] ?? '匿名';
    final List<dynamic> steps = track['steps'] ?? [];

    // 初始化后检查滚动状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollState();
    });

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            tileColor: Theme.of(
              context,
            ).colorScheme.primaryContainer.withOpacity(0.3),
            title: Text(
              '初始词条: $originWord',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('发起人: $originOwner'),
            leading: const Icon(Icons.auto_awesome),
            trailing: steps.length > 3
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 左箭头
                      IconButton(
                        icon: Icon(
                          Icons.chevron_left,
                          color: _canScrollLeft
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                        ),
                        onPressed: _canScrollLeft
                            ? () {
                                _scrollController.animateTo(
                                  _scrollController.offset - 200,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                      ),
                      // 右箭头
                      IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          color: _canScrollRight
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                        ),
                        onPressed: _canScrollRight
                            ? () {
                                _scrollController.animateTo(
                                  _scrollController.offset + 200,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                      ),
                    ],
                  )
                : null,
          ),
          // 滚动区域 + 左右渐变遮罩
          Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOriginNode(originWord),
                    ...steps.map((step) => _buildStepNode(step)).toList(),
                  ],
                ),
              ),
              // 左侧渐变遮罩
              if (_canScrollLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Theme.of(context).colorScheme.surface,
                          Theme.of(context).colorScheme.surface.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
              // 右侧渐变遮罩
              if (_canScrollRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Theme.of(context).colorScheme.surface,
                          Theme.of(context).colorScheme.surface.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOriginNode(String word) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text('起点', style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(word, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStepNode(dynamic step) {
    final drawer = step['drawerName'] ?? '匿名';
    final guesser = step['guesserName'] ?? '匿名';
    final guess = step['guessText'] ?? '';
    final pngBase64 = step['pngBase64'] ?? '';

    return Row(
      children: [
        const Icon(Icons.arrow_forward, color: Colors.grey, size: 20),
        const SizedBox(width: 8),
        Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.brush, size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '画师: $drawer',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (pngBase64.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    color: Colors.white,
                    child: Image.memory(
                      base64Decode(pngBase64),
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.help_outline, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '猜测: $guesser',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  guess,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
