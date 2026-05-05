import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/providers/identity_provider.dart';
import '../../presentation/models/identity_record.dart';
import 'app_toast.dart';

/// 身份认证侧边栏
class IdentityDrawer extends ConsumerStatefulWidget {
  const IdentityDrawer({super.key});

  @override
  ConsumerState<IdentityDrawer> createState() => _IdentityDrawerState();
}

class _IdentityDrawerState extends ConsumerState<IdentityDrawer> {
  final _usernameController = TextEditingController();
  final _fingerprintController = TextEditingController();
  final _remarkController = TextEditingController();
  final Set<String> _selectedKeys = {};
  bool _isSelectAll = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _fingerprintController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identityState = ref.watch(identityProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth / 3;

    return Drawer(
      width: drawerWidth,
      child: Column(
        children: [
          // 顶部输入区域
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
                Text('身份认证', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                // 用户名输入框
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    hintText: '输入用户名',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // 指纹输入框
                TextField(
                  controller: _fingerprintController,
                  decoration: const InputDecoration(
                    labelText: '指纹',
                    hintText: '输入指纹（十六进制）',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                // 备注输入框
                TextField(
                  controller: _remarkController,
                  decoration: const InputDecoration(
                    labelText: '备注（可选，默认为用户名）',
                    hintText: '输入备注',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                // 添加按钮
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _handleAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                  ),
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
          // 列表区域
          Expanded(
            child: identityState.records.isEmpty
                ? Center(
                    child: Text(
                      '暂无身份记录',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: identityState.records.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final record = identityState.records[index];
                      final isSelected = _selectedKeys.contains(record.key);
                      return _buildRecordTile(record, isSelected);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(IdentityRecord record, bool isSelected) {
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: isSelected,
        onChanged: (value) => _handleSelect(record.key, value ?? false),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              record.username,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            record.remark,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: Text(
        record.fingerprintHex,
        style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (value) => _handleMenuAction(value, record),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'copy_fingerprint',
            child: Row(
              children: [
                Icon(Icons.copy, size: 18),
                SizedBox(width: 8),
                Text('复制指纹'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'copy_username',
            child: Row(
              children: [
                Icon(Icons.person, size: 18),
                SizedBox(width: 8),
                Text('复制用户名'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, size: 18),
                SizedBox(width: 8),
                Text('编辑'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('删除', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleAdd() {
    final username = _usernameController.text.trim();
    final fingerprint = _fingerprintController.text.trim();
    final remark = _remarkController.text.trim();

    if (username.isEmpty) {
      toast.error(context, '请输入用户名');
      return;
    }
    if (fingerprint.isEmpty) {
      toast.error(context, '请输入指纹');
      return;
    }

    final record = IdentityRecord(
      username: username,
      fingerprintHex: fingerprint,
      remark: remark.isNotEmpty ? remark : null,
    );

    ref.read(identityProvider.notifier).addRecord(record);
    toast.success(context, '已添加');

    _usernameController.clear();
    _fingerprintController.clear();
    _remarkController.clear();
  }

  void _handleSelect(String key, bool selected) {
    setState(() {
      if (selected) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
      _isSelectAll =
          _selectedKeys.length == ref.read(identityProvider).records.length;
    });
  }

  void _handleSelectAll(bool selected) {
    setState(() {
      _isSelectAll = selected;
      if (selected) {
        _selectedKeys.clear();
        _selectedKeys.addAll(
          ref.read(identityProvider).records.map((r) => r.key),
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
          .read(identityProvider.notifier)
          .removeRecords(_selectedKeys.toList());
      setState(() {
        _selectedKeys.clear();
        _isSelectAll = false;
      });
      toast.success(context, '已删除');
    }
  }

  void _handleExport() {
    final json = ref.read(identityProvider.notifier).exportToJson();
    Clipboard.setData(ClipboardData(text: json));
    toast.success(context, '已导出到剪贴板');
  }

  void _handleMenuAction(String action, IdentityRecord record) async {
    switch (action) {
      case 'copy_fingerprint':
        Clipboard.setData(ClipboardData(text: record.fingerprintHex));
        toast.success(context, '已复制指纹');
        break;
      case 'copy_username':
        Clipboard.setData(ClipboardData(text: record.username));
        toast.success(context, '已复制用户名');
        break;
      case 'edit':
        _showEditDialog(record);
        break;
      case 'delete':
        await ref.read(identityProvider.notifier).removeRecord(record.key);
        toast.success(context, '已删除');
        break;
    }
  }

  void _showEditDialog(IdentityRecord record) {
    final usernameController = TextEditingController(text: record.username);
    final fingerprintController = TextEditingController(
      text: record.fingerprintHex,
    );
    final remarkController = TextEditingController(text: record.remark);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑身份记录'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fingerprintController,
                decoration: const InputDecoration(
                  labelText: '指纹',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkController,
                decoration: const InputDecoration(
                  labelText: '备注',
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
                username: usernameController.text.trim(),
                fingerprintHex: fingerprintController.text.trim(),
                remark: remarkController.text.trim(),
              );
              await ref.read(identityProvider.notifier).updateRecord(newRecord);
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
