import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../presentation/providers/artwork_provider.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/providers/connection_provider.dart';
import '../../../presentation/providers/layer_provider.dart';
import '../../../presentation/providers/settings_provider.dart';
import '../../../services/network/tcp_client_service.dart' as tcp_client;
import '../../../services/network/tcp_client_service.dart'
    show ConnectionStatus, RoomInfo;
import '../../../services/project/project_service.dart';
import '../canvas/canvas_screen.dart';
import '../login/login_screen.dart';
import '../room/room_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/identity_drawer.dart';
import '../../widgets/lexicon_overlay.dart';
import '../../widgets/replay_overlay.dart';

enum _ServerPanelMode { serverConnection, roomList }

/// 主页屏幕
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Widget? _activeDrawer;

  void _closeLexiconOverlay() {
    _scaffoldKey.currentState?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.verified_user),
              tooltip: '身份认证',
              onPressed: () {
                setState(() {
                  _activeDrawer = const IdentityDrawer();
                });
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: '词条编辑',
              onPressed: () {
                setState(() {
                  _activeDrawer = LexiconOverlay(onClose: _closeLexiconOverlay);
                });
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '复盘查看',
              onPressed: () {
                setState(() {
                  _activeDrawer = ReplayOverlay(onClose: _closeLexiconOverlay);
                });
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
          ],
        ),
        leadingWidth: 144,
        actions: [
          _buildConnectionStatusIndicator(ref),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                authState.username,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context, ref),
            tooltip: l10n.translate('logout'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      drawer: _activeDrawer,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 900;

          final leftContent = _buildLeftMainSection(
            context,
            ref,
            l10n,
            settings,
          );
          final rightContent = _buildServerConnectionSection(
            context,
            ref,
            l10n,
          );

          if (isNarrow) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      leftContent,
                      const SizedBox(height: 24),
                      rightContent,
                    ],
                  ),
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: SingleChildScrollView(child: leftContent),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: rightContent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLeftMainSection(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AppSettings settings,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.brush, size: 100, color: Colors.deepPurple),
        const SizedBox(height: 24),
        Text(
          'MeguPaint',
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('app_subtitle'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 48),
        ElevatedButton.icon(
          onPressed: () => _showNewCanvasDialog(context, ref),
          icon: const Icon(Icons.add),
          label: Text(l10n.translate('new_canvas')),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _openProject(context, ref),
          icon: const Icon(Icons.folder_open),
          label: Text(l10n.translate('open_project')),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 32),
        if (settings.defaultCanvasWidth > 0) ...[
          const Divider(),
          const SizedBox(height: 16),
          Text(
            l10n.translate('recent_projects'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.translate('no_recent_projects')),
        ],
      ],
    );
  }

  Widget _buildConnectionStatusIndicator(WidgetRef ref) {
    final pool = ref.watch(connectionProvider);
    final values = pool.connections.values.toList();
    final authenticatedCount = values
        .where((e) => e.status == ConnectionStatus.authenticated)
        .length;
    final authenticatingCount = values
        .where((e) => e.status == ConnectionStatus.authenticating)
        .length;
    final connectedCount = values
        .where((e) => e.status == ConnectionStatus.connected)
        .length;
    final connectingCount = values
        .where((e) => e.status == ConnectionStatus.connecting)
        .length;
    final errorCount = values
        .where((e) => e.status == ConnectionStatus.error)
        .length;

    ConnectionStatus aggregateStatus = ConnectionStatus.disconnected;
    if (authenticatedCount > 0) {
      aggregateStatus = ConnectionStatus.authenticated;
    } else if (authenticatingCount > 0) {
      aggregateStatus = ConnectionStatus.authenticating;
    } else if (connectedCount > 0) {
      aggregateStatus = ConnectionStatus.connected;
    } else if (connectingCount > 0) {
      aggregateStatus = ConnectionStatus.connecting;
    } else if (errorCount > 0) {
      aggregateStatus = ConnectionStatus.error;
    }

    IconData icon = Icons.cloud_off;
    Color color = Colors.grey;
    String tooltip = '未连接';

    switch (aggregateStatus) {
      case ConnectionStatus.connected:
        icon = Icons.cloud_done;
        color = Colors.blue;
        tooltip = '已连接: $connectedCount';
        break;
      case ConnectionStatus.authenticating:
        icon = Icons.cloud_sync;
        color = Colors.orange;
        tooltip = '验证中: $authenticatingCount';
        break;
      case ConnectionStatus.authenticated:
        icon = Icons.verified_user;
        color = Colors.green;
        tooltip = '已认证: $authenticatedCount';
        break;
      case ConnectionStatus.connecting:
        icon = Icons.cloud_queue;
        color = Colors.orange;
        tooltip = '连接中: $connectingCount';
        break;
      case ConnectionStatus.error:
        icon = Icons.cloud_off;
        color = Colors.red;
        tooltip = '连接错误: $errorCount';
        break;
      case ConnectionStatus.disconnected:
        icon = Icons.cloud_off;
        color = Colors.grey;
        tooltip = '未连接';
        break;
    }
    return Tooltip(
      message: tooltip,
      child: Icon(icon, color: color),
    );
  }

  Widget _buildServerConnectionSection(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final pool = ref.watch(connectionProvider);
    final authState = ref.watch(authProvider);
    final defaultText = pool.savedServerIp.isNotEmpty
        ? '${pool.savedServerIp}:${pool.savedServerPort}'
        : '';
    final addController = TextEditingController(text: defaultText);

    return _ServerConnectionPanel(
      pool: pool,
      authState: authState,
      l10n: l10n,
      addController: addController,
    );
  }

  void _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authProvider.notifier).logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _showNewCanvasDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final widthController = TextEditingController(text: '1920');
    final heightController = TextEditingController(text: '1080');
    final nameController = TextEditingController(
      text: l10n.translate('untitled_project'),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('dialog_new_canvas')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: l10n.translate('project_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widthController,
                    decoration: InputDecoration(
                      labelText: l10n.translate('width'),
                      border: const OutlineInputBorder(),
                      suffixText: 'px',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: heightController,
                    decoration: InputDecoration(
                      labelText: l10n.translate('height'),
                      border: const OutlineInputBorder(),
                      suffixText: 'px',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _buildPresetButton(
                  context,
                  '1080p',
                  1920,
                  1080,
                  widthController,
                  heightController,
                ),
                _buildPresetButton(
                  context,
                  '2K',
                  2560,
                  1440,
                  widthController,
                  heightController,
                ),
                _buildPresetButton(
                  context,
                  '4K',
                  3840,
                  2160,
                  widthController,
                  heightController,
                ),
                _buildPresetButton(
                  context,
                  'A4',
                  2480,
                  3508,
                  widthController,
                  heightController,
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final width = int.tryParse(widthController.text) ?? 1920;
              final height = int.tryParse(heightController.text) ?? 1080;
              final name = nameController.text;
              Navigator.pop(context);
              ref.read(layerProvider.notifier).reset();
              await ref
                  .read(artworkProvider.notifier)
                  .createNew(name: name, width: width, height: height);
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CanvasScreen()),
                );
              }
            },
            child: Text(l10n.translate('create')),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(
    BuildContext context,
    String label,
    int width,
    int height,
    TextEditingController widthController,
    TextEditingController heightController,
  ) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        widthController.text = width.toString();
        heightController.text = height.toString();
      },
    );
  }

  Future<void> _openProject(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final projectService = ProjectService();
    try {
      final project = await projectService.pickProjectFile();
      if (project == null) return;
      await ref.read(artworkProvider.notifier).openArtwork(project.artwork);
      ref
          .read(layerProvider.notifier)
          .loadFromProject(
            layers: project.drawLayers,
            activeLayerIndex: project.activeLayerIndex,
          );
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CanvasScreen()),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      toast.error(context, '${l10n.translate('open_project')}: $e');
    }
  }
}

class _ServerConnectionPanel extends StatefulWidget {
  final ConnectionPoolState pool;
  final AuthState authState;
  final AppLocalizations l10n;
  final TextEditingController addController;

  const _ServerConnectionPanel({
    required this.pool,
    required this.authState,
    required this.l10n,
    required this.addController,
  });

  @override
  State<_ServerConnectionPanel> createState() => _ServerConnectionPanelState();
}

class _ServerConnectionPanelState extends State<_ServerConnectionPanel> {
  final Set<String> _selectedKeys = {};
  _ServerPanelMode _currentMode = _ServerPanelMode.serverConnection;

  @override
  Widget build(BuildContext context) {
    final pool = widget.pool;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _buildModeTab(
                    label: '服务器',
                    icon: Icons.dns,
                    mode: _ServerPanelMode.serverConnection,
                  ),
                  const SizedBox(width: 16),
                  _buildModeTab(
                    label: '房间列表',
                    icon: Icons.meeting_room,
                    mode: _ServerPanelMode.roomList,
                  ),
                  const Spacer(),
                  if (_currentMode == _ServerPanelMode.serverConnection &&
                      _selectedKeys.isNotEmpty) ...[
                    TextButton.icon(
                      onPressed: () => _handleRefreshServerInfo(context),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新'),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          _handleBatchLogin(context, _selectedKeys.toList()),
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('登录'),
                    ),
                    TextButton.icon(
                      onPressed: () => _handleBatchDisconnect(
                        context,
                        _selectedKeys.toList(),
                      ),
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('断开'),
                    ),
                  ],
                  if (_currentMode == _ServerPanelMode.roomList) ...[
                    TextButton.icon(
                      onPressed: () => _showCreateRoomDialog(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('创建房间'),
                    ),
                    TextButton.icon(
                      onPressed: () => _handleRefreshRooms(context),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新房间'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_currentMode == _ServerPanelMode.serverConnection)
              _buildConnectionContent(pool)
            else
              _buildRoomListContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required _ServerPanelMode mode,
  }) {
    final isSelected = _currentMode == mode;
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).disabledColor;

    return InkWell(
      onTap: () => setState(() => _currentMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionContent(ConnectionPoolState pool) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.addController,
                decoration: const InputDecoration(
                  labelText: '服务器 IP',
                  hintText: '例如: 192.168.1.100 或 192.168.1.100:9527',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                keyboardType: TextInputType.text,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                final text = widget.addController.text.trim();
                if (text.isEmpty) {
                  toast.error(context, '请输入服务器 IP');
                  return;
                }
                final container = ProviderScope.containerOf(context);
                await container
                    .read(connectionProvider.notifier)
                    .addServer(text);
                if (context.mounted) toast.success(context, '已添加');
              },
              child: const Text('添加'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (pool.connections.isEmpty)
          Text('暂无服务器', style: Theme.of(context).textTheme.bodySmall)
        else ...[
          Row(
            children: [
              Checkbox(
                value:
                    _selectedKeys.length == pool.connections.length &&
                    pool.connections.isNotEmpty,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedKeys.addAll(pool.connections.keys);
                    } else {
                      _selectedKeys.clear();
                    }
                  });
                },
              ),
              const Text('全选', style: TextStyle(fontSize: 12)),
            ],
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pool.connections.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final entry = pool.connections.entries.elementAt(index);
              final key = entry.key;
              final conn = entry.value;
              final title = conn.serverName.isNotEmpty
                  ? conn.serverName
                  : '${conn.serverIp}:${conn.serverPort}';

              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Checkbox(
                  value: _selectedKeys.contains(key),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedKeys.add(key);
                      } else {
                        _selectedKeys.remove(key);
                      }
                    });
                  },
                ),
                title: Text(title, style: const TextStyle(fontSize: 14)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (conn.errorMessage != null)
                      Text(
                        conn.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 10),
                      ),
                    if (conn.status == ConnectionStatus.connected ||
                        conn.status == ConnectionStatus.authenticated)
                      Text(
                        '👥 ${conn.currentConnections}/${conn.maxConnections}  🚪 ${conn.currentRooms}/${conn.maxRooms}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStatusChip(conn.status),
                    if (conn.status == ConnectionStatus.authenticated)
                      IconButton(
                        icon: const Icon(Icons.info_outline, size: 16),
                        tooltip: '查看详情',
                        onPressed: () => _showServerDetails(context, conn),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        final container = ProviderScope.containerOf(context);
                        container
                            .read(connectionProvider.notifier)
                            .removeServer(key);
                        setState(() {
                          _selectedKeys.remove(key);
                        });
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildRoomListContent() {
    final container = ProviderScope.containerOf(context);
    final pool = container.read(connectionProvider);
    final rooms = pool.rooms;

    if (rooms.isEmpty) {
      return Text(
        '暂无房间，点击刷新按钮获取',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final room = rooms[index];
        final isFull = room.currentPlayers >= room.maxPlayers;
        // 获取所属服务器信息
        final container = ProviderScope.containerOf(context);
        final pool = container.read(connectionProvider);
        final serverConn = pool.connections[room.serverKey];
        final serverName = serverConn?.serverName.isNotEmpty == true
            ? serverConn!.serverName
            : serverConn?.serverIp ?? '未知服务器';
        final serverIp = serverConn?.serverIp ?? '';
        final serverPort = serverConn?.serverPort ?? 9527;
        final serverAddress = serverIp.isNotEmpty
            ? '$serverIp:$serverPort'
            : '';

        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.meeting_room, size: 20),
          title: Text(room.roomName, style: const TextStyle(fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${room.roomTypeName} · 房主: ${room.ownerName} · $serverName',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              if (serverAddress.isNotEmpty)
                Text(
                  serverAddress,
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (room.isGameActive) _buildRoomStatusChip('游戏中', Colors.orange),
              if (room.isGameActive) const SizedBox(width: 4),
              _buildRoomStatusChip(
                '${room.currentPlayers}/${room.maxPlayers}人',
                isFull ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 4),
              if (!isFull)
                IconButton(
                  icon: const Icon(Icons.login, size: 16),
                  tooltip: '加入房间',
                  onPressed: () => _handleJoinRoom(context, room),
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.login,
                    size: 16,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  tooltip: '房间已满',
                  onPressed: null,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoomStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10)),
    );
  }

  void _showCreateRoomDialog(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final notifier = container.read(connectionProvider.notifier);
    final authState = container.read(authProvider);
    final authenticated = notifier.authenticatedServers;

    if (!authState.isLoggedIn) {
      toast.error(context, '请先在本地登录');
      return;
    }

    if (authenticated.isEmpty) {
      toast.error(context, '请先登录至少一个服务器');
      return;
    }

    final nameController = TextEditingController(
      text: '${authState.username}的接龙房间',
    );
    final maxPlayersController = TextEditingController(text: '8');
    String? selectedServerKey = authenticated.first.key;
    int selectedRoomType = 0x01; // 默认接龙

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              const Text('创建新房间'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDialogSettingItem(
                    context: context,
                    label: '房间类型',
                    icon: Icons.category_outlined,
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedRoomType,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        border: UnderlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 0x01,
                          child: Text('接龙', style: TextStyle(fontSize: 14)),
                        ),
                        DropdownMenuItem(
                          value: 0x02,
                          child: Text('协同', style: TextStyle(fontSize: 14)),
                        ),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedRoomType = val ?? 0x01;
                          // 更新默认房间名称
                          final typeName = selectedRoomType == 0x01
                              ? '接龙'
                              : '协同';
                          nameController.text =
                              '${authState.username}的${typeName}房间';
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildDialogSettingItem(
                    context: context,
                    label: '目标服务器',
                    icon: Icons.dns_outlined,
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedServerKey,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        border: UnderlineInputBorder(),
                      ),
                      items: authenticated.map((e) {
                        final conn = e.value;
                        final label = conn.serverName.isNotEmpty
                            ? conn.serverName
                            : '${conn.serverIp}:${conn.serverPort}';
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() => selectedServerKey = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildDialogSettingItem(
                    context: context,
                    label: '房间名称',
                    icon: Icons.drive_file_rename_outline,
                    child: TextField(
                      controller: nameController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        hintText: '输入房间名称',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildDialogSettingItem(
                    context: context,
                    label: '人数上限',
                    icon: Icons.group_add_outlined,
                    child: TextField(
                      controller: maxPlayersController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        hintText: '最大支持 16 人',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check, size: 18),
              onPressed: () async {
                final name = nameController.text.trim();
                final maxPlayers = int.tryParse(maxPlayersController.text) ?? 8;

                if (name.isEmpty) {
                  toast.error(context, '房间名称不能为空');
                  return;
                }

                if (selectedServerKey == null) {
                  toast.error(context, '请选择服务器');
                  return;
                }

                Navigator.pop(dialogContext);
                final resp = await notifier.createRoom(
                  serverKey: selectedServerKey!,
                  roomName: name,
                  roomTypeCode: selectedRoomType,
                  maxPlayers: maxPlayers,
                );

                if (!context.mounted) return;

                if (resp != null && resp.success) {
                  toast.success(context, '房间创建成功');
                  // 进入房间界面
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RoomScreen(
                        roomId: resp.roomId!,
                        serverKey: selectedServerKey!,
                        roomName: name,
                      ),
                    ),
                  );
                } else {
                  toast.error(context, resp?.errorMessage ?? '创建房间失败');
                }
              },
              label: const Text('立即创建'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogSettingItem({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(left: 26), child: child),
      ],
    );
  }

  void _handleRefreshRooms(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    final notifier = container.read(connectionProvider.notifier);
    final authenticated = notifier.authenticatedServers;

    if (authenticated.isEmpty) {
      toast.error(context, '请先登录至少一个服务器');
      return;
    }

    await notifier.refreshRoomList();
    if (mounted) {
      setState(() {});
      toast.success(context, '房间列表已刷新');
    }
  }

  void _handleJoinRoom(BuildContext context, RoomInfo room) async {
    final container = ProviderScope.containerOf(context);
    final notifier = container.read(connectionProvider.notifier);
    final serverKey = room.serverKey;

    if (serverKey.isEmpty) {
      toast.error(context, '未找到对应服务器');
      return;
    }

    final resp = await notifier.joinRoom(serverKey, room.roomId);
    if (!context.mounted) return;

    if (resp != null && resp.success) {
      toast.success(context, '已加入房间');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomScreen(
            roomId: room.roomId,
            serverKey: serverKey,
            roomName: room.roomName,
          ),
        ),
      );
    } else {
      toast.error(context, resp?.errorMessage ?? '加入房间失败');
    }
  }

  void _showServerDetails(
    BuildContext context,
    tcp_client.ConnectionState conn,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dns, size: 24),
            SizedBox(width: 8),
            Text('服务器详情'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              '名称',
              conn.serverName.isNotEmpty ? conn.serverName : '未设置',
            ),
            _buildDetailRow('地址', conn.serverIp),
            _buildDetailRow('端口', conn.serverPort.toString()),
            _buildDetailRow('状态', _getStatusText(conn.status)),
            if (conn.errorMessage != null)
              _buildDetailRow('错误', conn.errorMessage!, isError: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: isError ? Colors.red : null),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return '已连接';
      case ConnectionStatus.authenticating:
        return '验证中';
      case ConnectionStatus.authenticated:
        return '已认证';
      case ConnectionStatus.connecting:
        return '连接中';
      case ConnectionStatus.error:
        return '错误';
      case ConnectionStatus.disconnected:
        return '未连接';
    }
  }

  void _handleBatchDisconnect(BuildContext context, List<String> keys) async {
    final container = ProviderScope.containerOf(context);
    await container.read(connectionProvider.notifier).disconnectMultiple(keys);
    if (mounted) toast.success(context, '已断开所选服务器');
  }

  void _handleRefreshServerInfo(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    container.read(connectionProvider.notifier).refreshAllServerInfo();
    if (mounted) toast.success(context, '已刷新服务器信息');
  }

  void _handleBatchLogin(BuildContext context, List<String> keys) async {
    final container = ProviderScope.containerOf(context);
    final auth = container.read(authProvider);
    if (!auth.isLoggedIn) {
      toast.error(context, '请先在本地登录');
      return;
    }
    await container
        .read(connectionProvider.notifier)
        .loginMultiple(keys, auth.username, auth.privateKey);
    if (mounted) toast.success(context, '正在登录所选服务器');
  }

  Widget _buildStatusChip(ConnectionStatus status) {
    String label;
    Color color;
    switch (status) {
      case ConnectionStatus.connected:
        label = '已连接';
        color = Colors.blue;
        break;
      case ConnectionStatus.authenticating:
        label = '验证中';
        color = Colors.orange;
        break;
      case ConnectionStatus.authenticated:
        label = '已认证';
        color = Colors.green;
        break;
      case ConnectionStatus.connecting:
        label = '连接中';
        color = Colors.orange;
        break;
      case ConnectionStatus.error:
        label = '错误';
        color = Colors.red;
        break;
      case ConnectionStatus.disconnected:
        label = '未连接';
        color = Colors.grey;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10)),
    );
  }
}
