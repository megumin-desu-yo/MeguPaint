import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/layer.dart' as domain_layer;
import '../../domain/utils/identity_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../presentation/providers/artwork_provider.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../presentation/providers/connection_provider.dart';
import '../../presentation/providers/layer_provider.dart';
import '../../services/network/tcp_client_service.dart' show CollabLayerOpType;
import '../widgets/app_toast.dart';

/// 图层面板组件
class LayerPanel extends ConsumerWidget {
  final int selectedLayerIndex;
  final void Function(int index) onLayerSelected;
  final AppLocalizations l10n;
  final ToastManager toast;
  final bool isCollabRoom;

  const LayerPanel({
    super.key,
    required this.selectedLayerIndex,
    required this.onLayerSelected,
    required this.l10n,
    required this.toast,
    this.isCollabRoom = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworkState = ref.watch(artworkProvider);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text(
                  l10n.translate('panel_layers'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                // 添加图层按钮
                if (isCollabRoom)
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: l10n.translate('new_layer'),
                    onPressed: () {
                      final username = ref.read(authProvider).username;
                      ref.read(connectionProvider.notifier).sendCollabLayerOp(
                        CollabLayerOpType.add,
                        {'name': '$username 的图层'},
                      );
                    },
                  )
                else
                  PopupMenuButton<bool>(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: l10n.translate('new_layer'),
                    onSelected: (withPermission) {
                      ref
                          .read(artworkProvider.notifier)
                          .addLayer(withPermission: withPermission);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: false,
                        child: Text(l10n.translate('layer_public')),
                      ),
                      PopupMenuItem(
                        value: true,
                        child: Text(l10n.translate('layer_owned')),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // 图层列表
          Expanded(
            child: artworkState.layers.isEmpty
                ? Center(child: Text(l10n.translate('background_layer')))
                : ListView.builder(
                    itemCount: artworkState.layers.length,
                    reverse: true, // 从上到下显示，最新在上
                    itemBuilder: (context, index) {
                      final layer = artworkState.layers[index];
                      final authState = ref.watch(authProvider);
                      // 使用 AnimatedSwitcher 实现交换动画
                      final layers = artworkState.layers;
                      VoidCallback? onMoveUp;
                      VoidCallback? onMoveDown;
                      if (isCollabRoom) {
                        if (index < layers.length - 1) {
                          onMoveUp = () {
                            final newOrder = List<String>.from(
                              layers.map((l) => l.id),
                            );
                            final id = newOrder.removeAt(index);
                            newOrder.insert(index + 1, id);
                            ref
                                .read(connectionProvider.notifier)
                                .sendCollabLayerOp(CollabLayerOpType.reorder, {
                                  'order': newOrder,
                                });
                          };
                        }
                        if (index > 0) {
                          onMoveDown = () {
                            final newOrder = List<String>.from(
                              layers.map((l) => l.id),
                            );
                            final id = newOrder.removeAt(index);
                            newOrder.insert(index - 1, id);
                            ref
                                .read(connectionProvider.notifier)
                                .sendCollabLayerOp(CollabLayerOpType.reorder, {
                                  'order': newOrder,
                                });
                          };
                        }
                      } else {
                        onMoveUp = index < layers.length - 1
                            ? () => ref
                                  .read(artworkProvider.notifier)
                                  .moveLayer(index, index + 1)
                            : null;
                        onMoveDown = index > 0
                            ? () => ref
                                  .read(artworkProvider.notifier)
                                  .moveLayer(index, index - 1)
                            : null;
                      }
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: _LayerItem(
                          key: ValueKey(layer.id),
                          layer: layer,
                          index: index,
                          totalLayers: layers.length,
                          currentUserId: authState.username,
                          isSelected: selectedLayerIndex == index,
                          isCollabRoom: isCollabRoom,
                          collabOwnerId: isCollabRoom
                              ? (ref
                                        .read(layerProvider)
                                        .layers
                                        .where((dl) => dl.id == layer.id)
                                        .firstOrNull
                                        ?.ownerId ??
                                    '')
                              : '',
                          l10n: l10n,
                          toast: toast,
                          onSelect: () => onLayerSelected(index),
                          onMoveUp: onMoveUp,
                          onMoveDown: onMoveDown,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 图层项组件
class _LayerItem extends ConsumerWidget {
  final domain_layer.Layer layer;
  final int index;
  final int totalLayers;
  final String currentUserId;
  final bool isSelected;
  final bool isCollabRoom;

  /// 协同模式下从 DrawLayer.ownerId 取得；空字符串表示公共图层
  final String collabOwnerId;
  final AppLocalizations l10n;
  final ToastManager toast;
  final VoidCallback onSelect;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _LayerItem({
    super.key,
    required this.layer,
    required this.index,
    required this.totalLayers,
    required this.currentUserId,
    required this.isSelected,
    this.isCollabRoom = false,
    this.collabOwnerId = '',
    required this.l10n,
    required this.toast,
    required this.onSelect,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 协同模式用 collabOwnerId 直接判断权限；本地模式用签名系统
    final domain_layer.LayerPermissionStatus permissionStatus;
    final bool canEdit;
    if (isCollabRoom) {
      if (collabOwnerId.isEmpty) {
        permissionStatus = domain_layer.LayerPermissionStatus.public;
      } else if (collabOwnerId == currentUserId) {
        permissionStatus = domain_layer.LayerPermissionStatus.owned;
      } else {
        permissionStatus = domain_layer.LayerPermissionStatus.others;
      }
      canEdit = collabOwnerId.isEmpty || collabOwnerId == currentUserId;
    } else {
      permissionStatus = layer.getPermissionStatus(currentUserId);
      canEdit = layer.canEdit(currentUserId);
    }

    // 指纹：本地模式从 ownerPublicId 派生；协同模式直接用用户名
    String? ownerFingerprint;
    String? displayOwner;
    if (isCollabRoom) {
      if (collabOwnerId.isNotEmpty) {
        displayOwner = collabOwnerId;
      }
    } else {
      final ownerPublicId = layer.ownerPublicId;
      if (ownerPublicId != null && ownerPublicId.isNotEmpty) {
        try {
          ownerFingerprint = IdentityUtils.getUserFingerprintFromPublicIdHex(
            ownerPublicId,
            bytes: 8,
          );
          displayOwner = '${layer.ownerId}#$ownerFingerprint';
        } catch (_) {}
      }
    }

    // 根据权限状态选择颜色和标签
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (permissionStatus) {
      case domain_layer.LayerPermissionStatus.public:
        statusColor = Colors.grey;
        statusLabel = l10n.translate('layer_public');
        statusIcon = Icons.public;
        break;
      case domain_layer.LayerPermissionStatus.owned:
        statusColor = Colors.green;
        statusLabel = l10n.translate('layer_owned');
        statusIcon = Icons.person;
        break;
      case domain_layer.LayerPermissionStatus.others:
        statusColor = Colors.orange;
        statusLabel = l10n.translate('layer_others');
        statusIcon = Icons.lock;
        break;
    }

    return Container(
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
        minTileHeight: 40,
        minVerticalPadding: 0,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        horizontalTitleGap: 6,
        minLeadingWidth: 36,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 可见性
            IconButton(
              icon: Icon(
                layer.isVisible ? Icons.visibility : Icons.visibility_off,
                size: 18,
              ),
              onPressed: () {
                if (isCollabRoom) {
                  ref.read(connectionProvider.notifier).sendCollabLayerOp(
                    CollabLayerOpType.setVisibility,
                    {'layerId': layer.id, 'isVisible': !layer.isVisible},
                  );
                } else {
                  ref
                      .read(artworkProvider.notifier)
                      .setLayerVisibility(index, !layer.isVisible);
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: layer.isVisible
                  ? l10n.translate('layer_hidden')
                  : l10n.translate('layer_visible'),
            ),
            // 锁定状态
            IconButton(
              icon: Icon(
                layer.isLocked ? Icons.lock : Icons.lock_open,
                size: 18,
              ),
              onPressed: canEdit
                  ? () {
                      if (isCollabRoom) {
                        ref.read(connectionProvider.notifier).sendCollabLayerOp(
                          CollabLayerOpType.setLock,
                          {'layerId': layer.id, 'isLocked': !layer.isLocked},
                        );
                      } else {
                        ref
                            .read(artworkProvider.notifier)
                            .setLayerLocked(index, !layer.isLocked);
                      }
                    }
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: layer.isLocked
                  ? l10n.translate('layer_unlocked')
                  : l10n.translate('layer_locked'),
            ),
          ],
        ),
        title: Text(layer.name),
        subtitle: Row(
          children: [
            Icon(statusIcon, size: 12, color: statusColor),
            const SizedBox(width: 4),
            Text(
              statusLabel,
              style: TextStyle(color: statusColor, fontSize: 10),
            ),
            if (displayOwner != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  displayOwner,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 上移按钮
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: onMoveUp,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: l10n.translate('layer_move_up'),
            ),
            // 下移按钮
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18),
              onPressed: onMoveDown,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: l10n.translate('layer_move_down'),
            ),
            // 更多菜单
            SizedBox(
              width: 24,
              height: 24,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 18),
                enabled: canEdit,
                onSelected: (value) =>
                    _handleMenuAction(value, context, ref, permissionStatus),
                popUpAnimationStyle: AnimationStyle.noAnimation,
                itemBuilder: (context) =>
                    _buildMenuItems(context, permissionStatus),
              ),
            ),
          ],
        ),
        onTap: () {
          onSelect();
          ref.read(layerProvider.notifier).setActiveLayerIndex(index);
        },
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
    domain_layer.LayerPermissionStatus permissionStatus,
  ) {
    return [
      // 重命名
      PopupMenuItem(
        value: 'rename',
        child: Row(
          children: [
            const Icon(Icons.edit, size: 18),
            const SizedBox(width: 8),
            Text(l10n.translate('layer_rename')),
          ],
        ),
      ),
      // 不透明度
      PopupMenuItem(
        value: 'opacity',
        child: Row(
          children: [
            const Icon(Icons.opacity, size: 18),
            const SizedBox(width: 8),
            Text(l10n.translate('layer_opacity')),
          ],
        ),
      ),
      const PopupMenuDivider(),
      // 向上合并
      if (index < totalLayers - 1)
        PopupMenuItem(
          value: 'merge_up',
          child: Row(
            children: [
              const Icon(Icons.merge_type, size: 18),
              const SizedBox(width: 8),
              Text(l10n.translate('layer_merge_up')),
            ],
          ),
        ),
      // 向下合并
      if (index > 0)
        PopupMenuItem(
          value: 'merge_down',
          child: Row(
            children: [
              const Icon(
                Icons.merge_type,
                size: 18,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(width: 8),
              Text(l10n.translate('layer_merge_down')),
            ],
          ),
        ),
      const PopupMenuDivider(),
      // 权限相关
      if (permissionStatus == domain_layer.LayerPermissionStatus.public)
        PopupMenuItem(
          value: 'add_permission',
          child: Text(l10n.translate('add_permission')),
        ),
      if (permissionStatus == domain_layer.LayerPermissionStatus.owned)
        PopupMenuItem(
          value: 'remove_permission',
          child: Text(l10n.translate('remove_permission')),
        ),
      // 删除
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete, size: 18, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              l10n.translate('delete_layer'),
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ),
      ),
    ];
  }

  void _handleMenuAction(
    String value,
    BuildContext context,
    WidgetRef ref,
    domain_layer.LayerPermissionStatus permissionStatus,
  ) {
    switch (value) {
      case 'rename':
        _showRenameDialog(context, ref);
        break;
      case 'opacity':
        _showOpacityDialog(context, ref);
        break;
      case 'merge_up':
        if (!isCollabRoom) {
          ref.read(artworkProvider.notifier).mergeLayer(index, 'up').then((
            success,
          ) {
            if (!success && context.mounted) {
              final errorMsg = ref.read(artworkProvider).errorMessage;
              if (errorMsg != null && errorMsg.isNotEmpty) {
                toast.error(context, errorMsg);
              } else {
                toast.error(context, l10n.translate('error_no_permission'));
              }
            }
          });
        }
        break;
      case 'merge_down':
        if (!isCollabRoom) {
          ref.read(artworkProvider.notifier).mergeLayer(index, 'down').then((
            success,
          ) {
            if (!success && context.mounted) {
              final errorMsg = ref.read(artworkProvider).errorMessage;
              if (errorMsg != null && errorMsg.isNotEmpty) {
                toast.error(context, errorMsg);
              } else {
                toast.error(context, l10n.translate('error_no_permission'));
              }
            }
          });
        }
        break;
      case 'delete':
        if (isCollabRoom) {
          ref.read(connectionProvider.notifier).sendCollabLayerOp(
            CollabLayerOpType.remove,
            {'layerId': layer.id},
          );
        } else {
          ref.read(artworkProvider.notifier).deleteLayer(index);
        }
        break;
      case 'add_permission':
        if (!isCollabRoom) {
          ref.read(artworkProvider.notifier).addLayerPermission(index);
        }
        break;
      case 'remove_permission':
        if (!isCollabRoom) {
          ref.read(artworkProvider.notifier).removeLayerPermission(index);
        }
        break;
    }
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: layer.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('layer_rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.translate('layer_name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                if (isCollabRoom) {
                  ref.read(connectionProvider.notifier).sendCollabLayerOp(
                    CollabLayerOpType.rename,
                    {'layerId': layer.id, 'name': newName},
                  );
                } else {
                  ref
                      .read(artworkProvider.notifier)
                      .setLayerName(index, newName);
                }
              }
              Navigator.pop(context);
            },
            child: Text(l10n.translate('confirm')),
          ),
        ],
      ),
    );
  }

  void _showOpacityDialog(BuildContext context, WidgetRef ref) {
    double opacity = layer.opacity;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.translate('layer_opacity')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(opacity * 100).toStringAsFixed(0)}%'),
              Slider(
                value: opacity,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                onChanged: (v) {
                  setState(() => opacity = v);
                  if (isCollabRoom) {
                    ref.read(connectionProvider.notifier).sendCollabLayerOp(
                      CollabLayerOpType.setOpacity,
                      {'layerId': layer.id, 'opacity': v},
                    );
                  } else {
                    ref
                        .read(artworkProvider.notifier)
                        .setLayerOpacity(index, v);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.translate('confirm')),
            ),
          ],
        ),
      ),
    );
  }
}
