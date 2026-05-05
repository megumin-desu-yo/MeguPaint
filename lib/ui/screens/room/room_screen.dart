import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../presentation/models/identity_record.dart';
import '../../../presentation/models/lexicon_record.dart';
import '../../../presentation/providers/artwork_provider.dart';
import '../../../presentation/providers/auth_provider.dart';
import '../../../presentation/providers/connection_provider.dart';
import '../../../presentation/providers/identity_provider.dart';
import '../../../presentation/providers/layer_provider.dart';
import '../../../presentation/providers/lexicon_provider.dart';
import '../../../services/network/tcp_client_service.dart'
    show RoomInfo, RoomMember, ChatMessage, CardPickBroadcast, GuessCard;
import '../../../services/project/project_service.dart';
import '../../widgets/app_toast.dart';
import '../canvas/canvas_screen.dart';

import '../../widgets/room/vote_barrage_item.dart';
import '../../widgets/room/danmaku_overlay.dart';
import '../../widgets/room/fly_ball.dart';
import '../../widgets/room/game_cards.dart';
import '../../widgets/room/review_widgets.dart';
import '../../widgets/room/common_widgets.dart';

class RoomScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String serverKey;
  final String roomName;

  const RoomScreen({
    super.key,
    required this.roomId,
    required this.serverKey,
    required this.roomName,
  });

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen>
    with TickerProviderStateMixin {
  int _topMode = 0; // 0: 房间大厅, 1: 接龙, 2: 结算, 3: 协同
  int _activeTab = 0; // 0: 聊天, 1: 设置

  // 复盘动画相关状态
  int _currentReviewPathIdx = 0;
  int _currentReviewStepIdx = 0;
  bool _showGuessInfo = false; // 是否显示猜测信息
  Timer? _reviewTimer;
  bool _isClearingReviewStage = false;
  int _lastServerReviewPathIndex = 0;
  int _lastServerReviewStepIndex = 0;
  Timer? _reviewClearTimer;
  final List<Map<String, dynamic>> _activeReviewDanmakus = []; // 当前复盘路径的弹幕
  final Map<String, Uint8List?> _reviewPngCache = {}; // 复盘PNG缓存，避免闪烁

  // 领奖台倒计时
  Timer? _podiumTimer;
  int _podiumSecondsLeft = 0;

  final GlobalKey _flyRootKey = GlobalKey();
  final Map<String, GlobalKey> _scoreAnchorKeys = {};
  final GlobalKey _favoriteAnchorKey = GlobalKey();

  int _lastVoteBarrageCount = 0;
  int? _lastFavoriteIndex;
  Map<String, int> _lastMemberScores = {};
  final List<FlySource> _flySources = [];
  final List<FlyBall> _activeFlyBalls = [];
  final Map<String, int> _scorePulseTokens = {};
  String? _tempLexiconKey; // 用于记录临时选择的词库
  int? _tempMaxPlayers;
  int? _tempRoomTypeCode;
  int? _tempRounds;
  int? _tempRoundTime;
  int? _tempCanvasWidth;
  int? _tempCanvasHeight;

  // 房间设置控制器
  late final TextEditingController _roomNameController;
  late final FocusNode _chatInputFocusNode;

  // 聊天控制器
  late final TextEditingController _chatController;
  late final ScrollController _chatScrollController;

  // 倒计时相关
  Timer? _countdownTimer;
  int _countdownSeconds = 0;
  bool _countdownActive = false;
  bool _wasAllReady = false; // 上一次是否全员准备

  // 游戏阶段倒计时
  Timer? _gamePhaseTimer;
  int _gamePhaseSeconds = 0;
  bool _drawingUploaded = false; // 本轮绘画是否已上传
  GamePhase? _lastGamePhase; // 追踪上一次游戏阶段
  bool _gameAutoSwitched = false; // 是否已自动切换到接龙页（每局游戏仅一次）
  int? _myPickedCardIndex; // 本轮我选的卡牌索引
  final TextEditingController _guessController = TextEditingController();
  bool _guessSubmitted = false; // 本轮猜测是否已提交
  bool _canvasReady = false; // 画布是否已初始化（选择尺寸后）
  bool _canvasDialogShown = false; // 画布尺寸对话框是否已弹出（防止重复弹出）
  bool _isCanvasDialogOpen = false; // 画布尺寸对话框是否正在显示
  bool _collabCanvasAutoInitRequested = false;
  int? _myWordPickIndex; // 词条翻牌阶段我选择的卡牌索引

  // 弹幕相关
  int _lastDanmakuMsgCount = 0; // 上次处理的消息数量
  final List<DanmakuItem> _danmakuItems = [];
  int _danmakuIdCounter = 0;
  final Random _danmakuRandom = Random();

  @override
  void initState() {
    super.initState();
    _roomNameController = TextEditingController();
    _chatInputFocusNode = FocusNode();
    _chatController = TextEditingController();
    _chatScrollController = ScrollController();
  }

  Widget _buildTopModeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return TopModeButton(
      label: label,
      icon: icon,
      selected: selected,
      enabled: enabled,
      onTap: onTap,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _gamePhaseTimer?.cancel();
    _reviewTimer?.cancel();
    _reviewClearTimer?.cancel();
    _podiumTimer?.cancel();
    for (final b in _activeFlyBalls) {
      b.controller.dispose();
    }
    _guessController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatInputFocusNode.dispose();
    _roomNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pool = ref.watch(connectionProvider);
    final members = pool.roomMembers;
    final messages = pool.chatMessages;
    final auth = ref.watch(authProvider);

    _maybeEnqueueVoteFlySources(pool);
    _maybeEnqueueFavoriteFlySource(pool);
    _maybeProcessScoreDeltas(pool);

    // 结算阶段：进入投票/最爱选择时，停止本地复盘动画，避免UI重叠
    if (pool.gamePhase == GamePhase.reviewing &&
        (pool.isVoting || pool.canPickFavorite)) {
      _reviewTimer?.cancel();
      _reviewTimer = null;
    }

    // 复盘进度完全由服务端驱动：这里只做过场和“猜测信息延迟显示”，不修改索引
    if (pool.gamePhase == GamePhase.reviewing && _topMode == 2) {
      final serverPath = pool.reviewPathIndex;
      final serverStep = pool.reviewStepIndex;

      if (serverPath != _lastServerReviewPathIndex) {
        _reviewTimer?.cancel();
        _reviewTimer = null;
        _reviewClearTimer?.cancel();

        setState(() {
          _isClearingReviewStage = true;
          _showGuessInfo = false;
          _activeReviewDanmakus.clear();
        });

        _reviewClearTimer = Timer(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          setState(() {
            _isClearingReviewStage = false;
          });
        });
      }

      if (serverStep != _lastServerReviewStepIndex) {
        _reviewTimer?.cancel();
        _reviewTimer = null;

        // stepIndex 变化时，先隐藏猜测信息，3秒后再显示
        setState(() {
          _showGuessInfo = false;
        });
        _reviewTimer = Timer(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          if (_topMode != 2) return;
          setState(() {
            _showGuessInfo = true;
          });
        });
      }

      _lastServerReviewPathIndex = serverPath;
      _lastServerReviewStepIndex = serverStep;
    }

    final roomId = widget.roomId;
    final roomName = widget.roomName;

    // 使用最新的房间ID（支持房间转让后更新）
    final currentRoomId = pool.currentRoomId ?? roomId;

    // 从已存在的房间列表中查找当前房间以获取设置信息
    final roomInfo = pool.rooms.firstWhere(
      (r) => r.roomId.toLowerCase() == currentRoomId.toLowerCase(),
      orElse: () => RoomInfo(
        roomId: currentRoomId,
        roomName: roomName,
        roomTypeCode: 0x01,
        currentPlayers: pool.roomMembers.length,
        maxPlayers: 8,
        ownerName: '',
        serverKey: '',
      ),
    );

    // 房主判断：roomId已固定不再随房主变更，改为用房间列表的ownerName判断
    final isOwner =
        roomInfo.ownerName.toLowerCase() == auth.username.toLowerCase();

    // 每次 build 时更新控制器文本（如果用户没有在编辑，或者房间信息发生了变化）
    if (!_roomNameController.selection.isValid) {
      _roomNameController.text = roomInfo.roomName;
    }

    int selectedRoomType = _tempRoomTypeCode ?? roomInfo.roomTypeCode;
    final isCollabRoom = selectedRoomType == 0x02; // 协同房间

    // 检测全员准备状态 + 词库存在 → 触发倒计时
    // 注意：必须限制在 idle 阶段，避免 ended/reviewing/领奖台展示期间误触发，导致自动开新一局
    final allReady = members.length >= 2 && members.every((m) => m.isReady);
    final hasLexicon =
        pool.roomLexiconJson != null && pool.roomLexiconJson!.isNotEmpty;
    final shouldCountdown =
        pool.gamePhase == GamePhase.idle &&
        pool.showPodium != true &&
        allReady &&
        hasLexicon &&
        !pool.isGameActive;

    // 当全员准备且词库存在时，启动5秒倒计时
    if (shouldCountdown && !_wasAllReady && !_countdownActive) {
      _startCountdown(isOwner, pool);
    }
    // 如果条件不再满足且正在倒计时，取消
    if (!shouldCountdown && _countdownActive) {
      _cancelCountdown();
    }
    _wasAllReady = shouldCountdown;

    // 游戏刚开始时自动切到接龙页（仅首次切换，之后允许自由切换）
    if (pool.isGameActive && _topMode != 1 && !_gameAutoSwitched) {
      _gameAutoSwitched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _topMode = 1);
      });
    }
    // 游戏结束后重置标记，下次新游戏可再次自动切换
    if (!pool.isGameActive) {
      _gameAutoSwitched = false;
    }

    // 游戏阶段变化时重置相关状态并启动倒计时
    if (pool.gamePhase != _lastGamePhase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _gamePhaseTimer?.cancel();
        _reviewTimer?.cancel();
        final newPhase = pool.gamePhase;

        if (newPhase == GamePhase.reviewing) {
          // 进入复盘结算界面
          setState(() {
            _topMode = 2;
            _showGuessInfo = false;
            _isClearingReviewStage = false;
            _lastServerReviewPathIndex = 0;
            _lastServerReviewStepIndex = 0;
          });
        } else if (newPhase == GamePhase.wordPicking) {
          _myWordPickIndex = null;
          _gamePhaseSeconds = pool.wordPickTime;
          _startGamePhaseTimer();
        } else if (newPhase == GamePhase.drawing) {
          _drawingUploaded = false;
          _canvasReady = false;
          _canvasDialogShown = false;
          _gamePhaseSeconds = pool.drawTime;
          _startGamePhaseTimer();
        } else if (newPhase == GamePhase.cardPicking) {
          // 如果作画阶段未上传画作，立即触发自动保存上传
          if (!_drawingUploaded) {
            _captureAndUploadDrawing();
          }
          _myPickedCardIndex = null;
          _guessSubmitted = false;
          _guessController.clear();
          _gamePhaseSeconds = pool.cardPickTime;
          _startGamePhaseTimer();
        } else if (newPhase == GamePhase.guessing) {
          _guessSubmitted = false;
          _gamePhaseSeconds = pool.guessTime;
          _startGamePhaseTimer();
        }
        _lastGamePhase = newPhase;
        if (mounted) setState(() {});
      });
    }

    final chatController = _chatController;
    final chatScrollController = _chatScrollController;

    // 检测新聊天消息，生成弹幕
    if (messages.length > _lastDanmakuMsgCount) {
      for (int i = _lastDanmakuMsgCount; i < messages.length; i++) {
        final msg = messages[i];
        _danmakuItems.add(
          DanmakuItem(
            id: _danmakuIdCounter++,
            sender: msg.sender,
            content: msg.content,
            topRatio: _danmakuRandom.nextDouble() * 0.5,
          ),
        );
      }
      // 限制弹幕数量，避免长时间运行累积过多
      const maxDanmakuCount = 30;
      if (_danmakuItems.length > maxDanmakuCount) {
        _danmakuItems.removeRange(0, _danmakuItems.length - maxDanmakuCount);
      }
      _lastDanmakuMsgCount = messages.length;
    }
    // 消息列表被清空时（如离开房间后重新进入），重置计数
    if (messages.length < _lastDanmakuMsgCount) {
      _lastDanmakuMsgCount = messages.length;
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTopModeButton(
                            label: '大厅',
                            icon: Icons.meeting_room_outlined,
                            selected: _topMode == 0,
                            enabled: true,
                            onTap: () {
                              setState(() => _topMode = 0);
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _buildTopModeButton(
                            label: isCollabRoom ? '画布' : '接龙',
                            icon: isCollabRoom ? Icons.brush : Icons.swap_horiz,
                            selected: _topMode == 1,
                            enabled: isCollabRoom || pool.isGameActive,
                            onTap: () {
                              if (!isCollabRoom && !pool.isGameActive) return;
                              setState(() => _topMode = 1);
                            },
                          ),
                        ),
                        if (!isCollabRoom) ...[
                          const SizedBox(width: 4),
                          Expanded(
                            child: _buildTopModeButton(
                              label: '结算',
                              icon: Icons.assignment_turned_in_outlined,
                              selected: _topMode == 2,
                              enabled:
                                  pool.gamePhase == GamePhase.reviewing ||
                                  pool.gamePhase == GamePhase.ended,
                              onTap: () {
                                setState(() => _topMode = 2);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (pool.isGameActive) ...[
                  const SizedBox(width: 16),
                  _buildGameStatusInTopBar(pool, auth),
                ],
                const Spacer(),
                if (_countdownActive && !pool.isGameActive)
                  Expanded(
                    child: Center(
                      child: Text(
                        '游戏将在 $_countdownSeconds 秒后开始',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  )
                else
                  const Expanded(child: SizedBox()),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.logout),
                  color: Theme.of(context).colorScheme.error,
                  tooltip: '退出房间',
                  onPressed: () => _leaveRoom(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              key: _flyRootKey,
              children: [
                _topMode == 1 && (isCollabRoom || pool.isGameActive)
                    ? (isCollabRoom
                          ? _buildCollabCanvasArea(context)
                          : _buildGameContent(pool, auth, members))
                    : _topMode == 2
                    ? _buildReviewContent(pool, auth, members)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          // 第一栏：成员列表 (宽度 300)
                          SizedBox(
                            width: 300,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).dividerColor.withOpacity(0.2),
                                  ),
                                ),
                              ),
                              child: _buildMemberContent(
                                members,
                                auth,
                                ref,
                                isOwner,
                                roomInfo,
                                selectedRoomType,
                              ),
                            ),
                          ),
                          // 第二栏：聊天/设置 (宽度 380)
                          SizedBox(
                            width: 300,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).dividerColor.withOpacity(0.2),
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  // 顶部Tab栏
                                  Container(
                                    height: 52,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withOpacity(0.5),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Theme.of(
                                            context,
                                          ).dividerColor.withOpacity(0.1),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        _buildTabButton('聊天', Icons.chat, 0),
                                        _buildTabButton(
                                          '设置',
                                          Icons.settings,
                                          1,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 内容区域
                                  Expanded(
                                    child: _activeTab == 0
                                        ? _buildChatContent(
                                            messages,
                                            auth,
                                            chatScrollController,
                                            chatController,
                                          )
                                        : _buildSettingsContent(
                                            isOwner,
                                            selectedRoomType,
                                            _roomNameController,
                                            _tempMaxPlayers ??
                                                roomInfo.maxPlayers,
                                            _tempRounds ?? roomInfo.rounds,
                                            _tempRoundTime ??
                                                roomInfo.roundTime,
                                            _tempLexiconKey ??
                                                roomInfo.lexiconKey,
                                            roomInfo,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 第三栏：协同画布区域（协同房间）或茶绘区域（接龙房间）
                          Expanded(
                            child: Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow
                                  .withOpacity(0.5),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.brush_outlined,
                                      size: 64,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.25),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      '待开发',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withOpacity(0.5),
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                // 弹幕覆盖层
                DanmakuOverlay(
                  items: _danmakuItems,
                  onItemComplete: (id) {
                    setState(() {
                      _danmakuItems.removeWhere((e) => e.id == id);
                    });
                  },
                ),
                Positioned.fill(
                  child: IgnorePointer(child: _buildFlyBallLayer()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  GlobalKey _getScoreAnchorKey(String fingerprintHex) {
    return _scoreAnchorKeys.putIfAbsent(fingerprintHex, () => GlobalKey());
  }

  Offset? _getAnchorOffset(GlobalKey key) {
    final rootContext = _flyRootKey.currentContext;
    if (rootContext == null) return null;
    final rootBox = rootContext.findRenderObject() as RenderBox?;
    final ctx = key.currentContext;
    if (rootBox == null || ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final global = box.localToGlobal(box.size.center(Offset.zero));
    return rootBox.globalToLocal(global);
  }

  void _maybeEnqueueVoteFlySources(ConnectionPoolState pool) {
    final barrages = pool.voteBarrages;
    if (barrages.length <= _lastVoteBarrageCount) {
      _lastVoteBarrageCount = barrages.length;
      return;
    }

    final rootContext = _flyRootKey.currentContext;
    if (rootContext == null) {
      _lastVoteBarrageCount = barrages.length;
      return;
    }
    final rootBox = rootContext.findRenderObject() as RenderBox?;
    if (rootBox == null || !rootBox.hasSize) {
      _lastVoteBarrageCount = barrages.length;
      return;
    }

    for (int i = _lastVoteBarrageCount; i < barrages.length; i++) {
      final v = barrages[i];
      final isUp = v['isUp'] == true;
      if (!isUp) continue;

      final top = 100.0 + (i % 5) * 60.0 + 18.0;
      final from = Offset(rootBox.size.width - 40.0, top);
      _flySources.add(FlySource(from: from, color: Colors.green.shade400));
    }

    _lastVoteBarrageCount = barrages.length;
  }

  void _maybeEnqueueFavoriteFlySource(ConnectionPoolState pool) {
    final favoriteIndex = pool.favoriteChosenIndex;
    if (favoriteIndex == null || favoriteIndex == 255) {
      _lastFavoriteIndex = favoriteIndex;
      return;
    }
    if (_lastFavoriteIndex == favoriteIndex) return;

    final anchor = _getAnchorOffset(_favoriteAnchorKey);
    if (anchor == null) {
      _lastFavoriteIndex = favoriteIndex;
      return;
    }

    _flySources.add(
      FlySource(
        from: anchor,
        color: Colors.amber.shade600,
        type: FlySourceType.favorite,
      ),
    );
    _lastFavoriteIndex = favoriteIndex;
  }

  void _maybeProcessScoreDeltas(ConnectionPoolState pool) {
    final current = pool.memberScores;
    if (_lastMemberScores.isEmpty) {
      _lastMemberScores = Map<String, int>.from(current);
      return;
    }

    final increased = <String, int>{};
    for (final entry in current.entries) {
      final old = _lastMemberScores[entry.key] ?? 0;
      final delta = entry.value - old;
      if (delta > 0) {
        increased[entry.key] = delta;
      }
    }
    if (increased.isEmpty) {
      _lastMemberScores = Map<String, int>.from(current);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final inc in increased.entries) {
        final fp = inc.key;
        final delta = inc.value;
        for (int i = 0; i < delta; i++) {
          final source = _flySources.isNotEmpty
              ? _flySources.removeAt(0)
              : FlySource(
                  from: const Offset(520, 260),
                  color: Colors.green.shade400,
                );
          _launchFlyBall(source, fp);
        }
      }
    });

    _lastMemberScores = Map<String, int>.from(current);
  }

  void _launchFlyBall(FlySource source, String fingerprintHex) {
    final dest = _getAnchorOffset(_getScoreAnchorKey(fingerprintHex));
    if (dest == null) return;

    final start = source.from;
    final control = Offset(
      (start.dx + dest.dx) / 2,
      min(start.dy, dest.dy) - 120,
    );
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    final anim = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    final ball = FlyBall(
      controller: controller,
      anim: anim,
      start: start,
      control: control,
      end: dest,
      color: source.color,
      targetFp: fingerprintHex,
    );

    setState(() {
      _activeFlyBalls.add(ball);
    });

    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;

      final token = (_scorePulseTokens[fingerprintHex] ?? 0) + 1;
      _scorePulseTokens[fingerprintHex] = token;
      if (mounted) setState(() {});

      Future.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        if (_scorePulseTokens[fingerprintHex] != token) return;
        _scorePulseTokens.remove(fingerprintHex);
        setState(() {});
      });

      controller.dispose();
      if (mounted) {
        setState(() {
          _activeFlyBalls.remove(ball);
        });
      }
    });

    controller.forward();
  }

  Widget _buildFlyBallLayer() {
    if (_activeFlyBalls.isEmpty) return const SizedBox.expand();
    return AnimatedBuilder(
      animation: Listenable.merge(_activeFlyBalls.map((e) => e.controller)),
      builder: (context, child) {
        return CustomPaint(
          painter: FlyBallPainter(balls: _activeFlyBalls),
          child: const SizedBox.expand(),
        );
      },
    );
  }

  Widget _buildMemberContent(
    List<RoomMember> members,
    dynamic auth,
    WidgetRef ref,
    bool isOwner,
    RoomInfo roomInfo,
    int roomTypeCode,
  ) {
    final isSolitaire = roomTypeCode == 0x01;
    return Column(
      children: [
        // 成员列表标题栏
        Container(
          width: double.infinity,
          height: 52, // 统一高度
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.people_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '成员 (${members.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: const Icon(Icons.refresh),
                tooltip: '刷新成员列表',
                onPressed: () {
                  ref.read(connectionProvider.notifier).refreshRoomMembers();
                },
              ),
            ],
          ),
        ),
        // 成员列表内容
        Expanded(
          child: members.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: Colors.grey.withOpacity(0.3),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '暂无成员',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: members.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final isOffline = !member.isOnline;
                    // 房主判断：改为基于 RoomInfo.ownerName 判断，不再简单依赖列表索引 0
                    final isRoomOwner =
                        roomInfo.ownerName.isNotEmpty &&
                        member.username.toLowerCase() ==
                            roomInfo.ownerName.toLowerCase();
                    final identityState = ref.watch(identityProvider);
                    final identityRecord = identityState.findByFingerprint(
                      member.fingerprintHex,
                    );
                    final isVerified = identityRecord != null;
                    final isMe = member.username == auth.username;

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (isRoomOwner
                                              ? Colors.amber
                                              : (isVerified
                                                    ? Colors.green
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.primary))
                                          .withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: isRoomOwner
                                  ? Colors.amber
                                  : isVerified
                                  ? Colors.green
                                  : Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                              child: Text(
                                member.username.isNotEmpty
                                    ? member.username[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isRoomOwner || isVerified
                                      ? Colors.white
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                          if (member.isReady && isSolitaire)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).scaffoldBackgroundColor,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${member.username}#${member.fingerprintHex.length >= 4 ? member.fingerprintHex.substring(0, 4) : member.fingerprintHex}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isMe
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isOffline
                                    ? Colors.grey
                                    : isMe
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isOffline)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.25),
                                ),
                              ),
                              child: const Text(
                                '已掉线',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (isMe)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '(我)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.6),
                                ),
                              ),
                            ),
                          if (isRoomOwner)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.amber.withOpacity(0.3),
                                ),
                              ),
                              child: const Text(
                                '房主',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        isVerified
                            ? (identityRecord.remark.isNotEmpty
                                  ? identityRecord.remark
                                  : member.fingerprintHex)
                            : member.fingerprintHex,
                        style: TextStyle(
                          fontSize: 10,
                          color: isOffline
                              ? Colors.grey
                              : (isVerified ? Colors.green : Colors.grey),
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isMe && !isOffline && isSolitaire)
                            TextButton(
                              onPressed: () {
                                ref
                                    .read(connectionProvider.notifier)
                                    .sendReadyRequest(!member.isReady);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: member.isReady
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: member.isReady
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.2),
                                  ),
                                ),
                              ),
                              child: Text(
                                member.isReady ? '取消' : '准备',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: member.isReady
                                      ? Colors.green
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          if (!isMe)
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.more_vert,
                                size: 18,
                                color: Colors.grey,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onSelected: (value) => _handleIdentityAction(
                                context,
                                ref,
                                value,
                                member.fingerprintHex,
                                member.username,
                                identityRecord,
                              ),
                              itemBuilder: (context) => [
                                if (isOwner && roomTypeCode != 0x02)
                                  const PopupMenuItem(
                                    value: 'transfer',
                                    child: Row(
                                      children: [
                                        Icon(Icons.swap_horiz, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          '转让房主',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (isVerified) ...[
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          '编辑备注',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          '移除记录',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else
                                  const PopupMenuItem(
                                    value: 'add',
                                    child: Row(
                                      children: [
                                        Icon(Icons.verified_user, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          '添加验证',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTabButton(String label, IconData icon, int index) {
    return TabButton(
      label: label,
      icon: icon,
      isSelected: _activeTab == index,
      onTap: () => setState(() => _activeTab = index),
    );
  }

  Widget _buildChatContent(
    List<ChatMessage> messages,
    dynamic auth,
    ScrollController scrollController,
    TextEditingController controller,
  ) {
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: Colors.grey.withOpacity(0.3),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '暂无聊天记录',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.sender == auth.username;
                    final showTime =
                        index == 0 ||
                        msg.timestamp
                                .difference(messages[index - 1].timestamp)
                                .inMinutes >
                            5;

                    return Column(
                      children: [
                        if (showTime)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              '${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.withOpacity(0.8),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe) _buildChatAvatar(msg.sender),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          msg.sender,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .withOpacity(0.5),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(12),
                                          topRight: const Radius.circular(12),
                                          bottomLeft: Radius.circular(
                                            isMe ? 12 : 0,
                                          ),
                                          bottomRight: Radius.circular(
                                            isMe ? 0 : 12,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.05,
                                            ),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        msg.content,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isMe
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onPrimary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isMe)
                                _buildChatAvatar(msg.sender, isMe: true),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.1),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: _chatInputFocusNode,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        ref
                            .read(connectionProvider.notifier)
                            .sendChatMessage(val);
                        controller.clear();
                        _chatInputFocusNode.requestFocus();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send_rounded, size: 20),
                onPressed: () {
                  final val = controller.text;
                  if (val.trim().isNotEmpty) {
                    ref.read(connectionProvider.notifier).sendChatMessage(val);
                    controller.clear();
                    _chatInputFocusNode.requestFocus();
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatAvatar(String name, {bool isMe = false}) {
    return ChatAvatar(name: name, isMe: isMe);
  }

  Widget _buildSettingsContent(
    bool isOwner,
    int selectedRoomType,
    TextEditingController nameController,
    int maxPlayers,
    int rounds,
    int roundTime,
    String selectedLexiconKey,
    RoomInfo roomInfo,
  ) {
    final lexiconState = ref.watch(lexiconProvider);
    final isSolitaire = selectedRoomType == 0x01;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildSettingItem(
          label: '房间类型',
          icon: Icons.category_outlined,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  selectedRoomType == 0x02 ? '协同' : '接龙',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 6),
                Text(
                  '（创建后不可更改）',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        _buildSettingItem(
          label: '房间名称',
          icon: Icons.drive_file_rename_outline,
          child: TextField(
            controller: nameController,
            enabled: isOwner,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              hintText: '输入房间名称',
            ),
            onSubmitted: isOwner
                ? (val) {
                    final newName = val.trim();
                    if (newName.isNotEmpty) {
                      ref
                          .read(connectionProvider.notifier)
                          .updateRoom(
                            roomName: newName,
                            roomTypeCode: selectedRoomType,
                            maxPlayers: maxPlayers,
                            rounds: rounds,
                            roundTime: roundTime,
                            lexiconKey: selectedLexiconKey,
                            canvasWidth: _tempCanvasWidth ?? 1280,
                            canvasHeight: _tempCanvasHeight ?? 720,
                          );
                    }
                  }
                : null,
          ),
        ),
        const SizedBox(height: 24),

        _buildSettingItem(
          label: '画布大小',
          icon: Icons.photo_size_select_large_outlined,
          child: DropdownButtonFormField<int>(
            value: (() {
              final w = _tempCanvasWidth ?? 1280;
              final h = _tempCanvasHeight ?? 720;
              if (w == 1280 && h == 720) return 0;
              if (w == 1920 && h == 1080) return 1;
              if (w == 2560 && h == 1440) return 2;
              if (w == 3840 && h == 2160) return 3;
              return 0;
            })(),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              border: UnderlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 0,
                child: Text('720p (1280×720)', style: TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: 1,
                child: Text(
                  '1080p (1920×1080)',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              DropdownMenuItem(
                value: 2,
                child: Text('2K (2560×1440)', style: TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: 3,
                child: Text('4K (3840×2160)', style: TextStyle(fontSize: 13)),
              ),
            ],
            onChanged: isOwner
                ? (val) {
                    int w = 1280;
                    int h = 720;
                    if (val == 1) {
                      w = 1920;
                      h = 1080;
                    } else if (val == 2) {
                      w = 2560;
                      h = 1440;
                    } else if (val == 3) {
                      w = 3840;
                      h = 2160;
                    }
                    setState(() {
                      _tempCanvasWidth = w;
                      _tempCanvasHeight = h;
                    });
                    ref
                        .read(connectionProvider.notifier)
                        .updateRoom(
                          roomName: nameController.text.trim(),
                          roomTypeCode: selectedRoomType,
                          maxPlayers: maxPlayers,
                          rounds: rounds,
                          roundTime: roundTime,
                          lexiconKey: selectedLexiconKey,
                          canvasWidth: w,
                          canvasHeight: h,
                        );
                  }
                : null,
          ),
        ),
        const SizedBox(height: 24),

        if (isSolitaire) ...[
          _buildSettingItem(
            label: '词库选择',
            icon: Icons.menu_book_outlined,
            child: isOwner
                ? DropdownButtonFormField<String>(
                    value: selectedLexiconKey.isEmpty
                        ? null
                        : selectedLexiconKey,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: UnderlineInputBorder(),
                    ),
                    items: lexiconState.records.map((r) {
                      return DropdownMenuItem(
                        value: r.key,
                        child: Text(
                          r.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _tempLexiconKey = val;
                        });
                        final record = lexiconState.records.firstWhere(
                          (r) => r.key == val,
                        );
                        toast.info(context, '已选择词库: ${record.name}');
                        final notifier = ref.read(connectionProvider.notifier);
                        notifier.updateRoom(
                          roomName: nameController.text.trim(),
                          roomTypeCode: selectedRoomType,
                          maxPlayers: maxPlayers,
                          rounds: rounds,
                          roundTime: roundTime,
                          lexiconKey: val,
                        );
                        // 将词库数据上传到服务器
                        final lexiconJson = jsonEncode(record.toJson());
                        notifier.uploadLexicon(lexiconJson);
                      }
                    },
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedLexiconKey.isEmpty ? '未选择词库' : '已选择词库',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (selectedLexiconKey.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            // 优先从服务器词库数据预览
                            final pool = ref.read(connectionProvider);
                            final serverJson = pool.roomLexiconJson;
                            LexiconRecord? record;
                            if (serverJson != null && serverJson.isNotEmpty) {
                              try {
                                final map =
                                    jsonDecode(serverJson)
                                        as Map<String, dynamic>;
                                record = LexiconRecord.fromJson(map);
                              } catch (_) {}
                            }
                            // 回退到本地词库
                            record ??= lexiconState.records.firstWhere(
                              (r) => r.key == selectedLexiconKey,
                              orElse: () => LexiconRecord(
                                name: '未知',
                                key: selectedLexiconKey,
                              ),
                            );
                            _showLexiconViewDialog(context, record);
                          },
                          child: const Text('查看内容'),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
        ],

        _buildSettingItem(
          label: '人数上限: $maxPlayers',
          icon: Icons.group_add_outlined,
          child: Slider(
            value: maxPlayers.toDouble(),
            min: 2,
            max: 16,
            divisions: 14,
            label: maxPlayers.toString(),
            onChanged: isOwner
                ? (val) {
                    final newMax = val.round();
                    setState(() {
                      _tempMaxPlayers = newMax;
                    });
                    ref
                        .read(connectionProvider.notifier)
                        .updateRoom(
                          roomName: nameController.text.trim(),
                          roomTypeCode: selectedRoomType,
                          maxPlayers: newMax,
                          rounds: rounds,
                          roundTime: roundTime,
                          lexiconKey: selectedLexiconKey,
                        );
                  }
                : null,
          ),
        ),
        const SizedBox(height: 24),

        if (isSolitaire) ...[
          _buildSettingItem(
            label: '回合数: $rounds',
            icon: Icons.repeat_on_outlined,
            child: Slider(
              value: rounds.toDouble(),
              min: 1,
              max: 20,
              divisions: 19,
              label: rounds.toString(),
              onChanged: isOwner
                  ? (val) {
                      final newRounds = val.round();
                      setState(() {
                        _tempRounds = newRounds;
                      });
                      ref
                          .read(connectionProvider.notifier)
                          .updateRoom(
                            roomName: nameController.text.trim(),
                            roomTypeCode: selectedRoomType,
                            maxPlayers: maxPlayers,
                            rounds: newRounds,
                            roundTime: roundTime,
                            lexiconKey: selectedLexiconKey,
                          );
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 24),

          _buildSettingItem(
            label: '每回合时间: $roundTime 秒',
            icon: Icons.timer_outlined,
            child: Slider(
              value: _encodeTime(roundTime),
              min: 0,
              max: 100,
              divisions: 100,
              label: '$roundTime秒',
              onChanged: isOwner
                  ? (val) {
                      final newRoundTime = _decodeTime(val);
                      setState(() {
                        _tempRoundTime = newRoundTime;
                      });
                      ref
                          .read(connectionProvider.notifier)
                          .updateRoom(
                            roomName: nameController.text.trim(),
                            roomTypeCode: selectedRoomType,
                            maxPlayers: maxPlayers,
                            rounds: rounds,
                            roundTime: newRoundTime,
                            lexiconKey: selectedLexiconKey,
                          );
                    }
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSettingItem({
    required String label,
    required IconData icon,
    required Widget child,
  }) {
    return SettingItem(label: label, icon: icon, child: child);
  }

  double _encodeTime(int seconds) {
    if (seconds <= 180) {
      return (seconds / 180) * 30;
    } else if (seconds <= 1200) {
      return 30 + ((seconds - 180) / (1200 - 180)) * 40;
    } else {
      return 70 + ((seconds - 1200) / (3600 - 1200)) * 30;
    }
  }

  int _decodeTime(double value) {
    double seconds;
    if (value <= 30) {
      seconds = (value / 30) * 180;
    } else if (value <= 70) {
      seconds = 180 + ((value - 30) / 40) * (1200 - 180);
    } else {
      seconds = 1200 + ((value - 70) / 30) * (3600 - 1200);
    }
    if (seconds <= 60) return (seconds / 5).round() * 5;
    if (seconds <= 300) return (seconds / 10).round() * 10;
    if (seconds <= 1200) return (seconds / 30).round() * 30;
    return (seconds / 60).round() * 60;
  }

  void _showLexiconViewDialog(BuildContext context, LexiconRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('查看词库: ${record.name}'),
        content: SizedBox(
          width: 400,
          height: 500,
          child: record.items.isEmpty
              ? const Center(child: Text('此词库暂无词条'))
              : ListView.builder(
                  itemCount: record.items.length,
                  itemBuilder: (context, index) {
                    final item = record.items[index];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      title: Text(item.content),
                    );
                  },
                ),
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

  void _leaveRoom(BuildContext context, WidgetRef ref) async {
    await ref.read(connectionProvider.notifier).leaveRoom();
    if (context.mounted) {
      toast.info(context, '已离开房间');
      Navigator.pop(context);
    }
  }

  /// 处理身份认证操作
  void _handleIdentityAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    String fingerprint,
    String username,
    IdentityRecord? existingIdentity,
  ) {
    switch (action) {
      case 'transfer':
        _showTransferRoomDialog(context, ref, fingerprint, username);
        break;
      case 'add':
        _showAddIdentityDialog(context, ref, fingerprint, username);
        break;
      case 'edit':
        _showEditIdentityDialog(
          context,
          ref,
          fingerprint,
          existingIdentity!.remark,
        );
        break;
      case 'delete':
        _deleteIdentity(context, ref, fingerprint);
        break;
    }
  }

  /// 显示转让房间确认对话框
  void _showTransferRoomDialog(
    BuildContext context,
    WidgetRef ref,
    String fingerprint,
    String username,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('转让房主'),
        content: Text('确定要将房主转让给 $username 吗？\n转让后您将成为普通成员。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await ref
                  .read(connectionProvider.notifier)
                  .transferRoom(
                    newOwnerUsername: username,
                    newOwnerFingerprintHex: fingerprint,
                  );
              if (!context.mounted) return;
              if (success) {
                toast.success(context, '已转让房主给 $username');
              } else {
                toast.error(context, '转让失败');
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示添加认证对话框
  void _showAddIdentityDialog(
    BuildContext context,
    WidgetRef ref,
    String fingerprint,
    String username,
  ) {
    final controller = TextEditingController(text: username);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加身份认证'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '指纹: $fingerprint',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '备注名称',
                hintText: '输入自定义备注名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final remark = controller.text.trim();
              if (remark.isNotEmpty) {
                final record = IdentityRecord(
                  username: username,
                  fingerprintHex: fingerprint,
                  remark: remark,
                );
                ref.read(identityProvider.notifier).addRecord(record);
                toast.success(context, '已添加认证: $remark');
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示修改认证对话框
  void _showEditIdentityDialog(
    BuildContext context,
    WidgetRef ref,
    String fingerprint,
    String currentNickname,
  ) {
    final controller = TextEditingController(text: currentNickname);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改认证备注'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '指纹: $fingerprint',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '备注名称',
                hintText: '输入自定义备注名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final remark = controller.text.trim();
              if (remark.isNotEmpty) {
                final record = IdentityRecord(
                  username: '',
                  fingerprintHex: fingerprint,
                  remark: remark,
                );
                ref.read(identityProvider.notifier).updateRecord(record);
                toast.success(context, '已更新认证: $remark');
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 删除认证
  void _deleteIdentity(
    BuildContext context,
    WidgetRef ref,
    String fingerprint,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除此身份认证吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(identityProvider.notifier).removeRecord(fingerprint);
              toast.success(context, '已删除认证');
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ============ 接龙游戏相关方法 ============

  /// 启动5秒倒计时
  void _startCountdown(bool isOwner, dynamic pool) {
    _countdownActive = true;
    _countdownSeconds = 5;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownSeconds--;
      });
      if (_countdownSeconds <= 0) {
        timer.cancel();
        _countdownActive = false;
        // 房主负责生成卡牌并广播游戏开始
        if (isOwner) {
          _initiateGame();
        }
      }
    });
    setState(() {});
  }

  /// 取消倒计时
  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownActive = false;
    _countdownSeconds = 0;
    if (mounted) setState(() {});
  }

  /// 房主发起游戏：从词库随机抽取与用户数相同的不重复词条
  void _initiateGame() {
    final pool = ref.read(connectionProvider);
    final lexiconJson = pool.roomLexiconJson;
    if (lexiconJson == null || lexiconJson.isEmpty) return;

    try {
      final map = jsonDecode(lexiconJson) as Map<String, dynamic>;
      final record = LexiconRecord.fromJson(map);
      final memberCount = pool.roomMembers.length;
      if (record.items.isEmpty || memberCount == 0) return;

      // 随机抽取 memberCount 个不同索引
      final random = Random();
      final allIndices = List<int>.generate(record.items.length, (i) => i);
      allIndices.shuffle(random);
      final selected = allIndices.take(memberCount).toList();

      // 发送游戏开始请求
      ref.read(connectionProvider.notifier).sendGameStart(selected);
    } catch (_) {}
  }

  /// 启动游戏阶段倒计时
  void _startGamePhaseTimer() {
    _gamePhaseTimer?.cancel();
    _gamePhaseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _gamePhaseSeconds--;
      });
      if (_gamePhaseSeconds <= 0) {
        timer.cancel();
        _onGamePhaseTimerEnd();
      }
    });
  }

  /// 游戏阶段倒计时结束时的处理
  void _onGamePhaseTimerEnd() {
    final pool = ref.read(connectionProvider);
    if (pool.gamePhase == GamePhase.drawing && !_drawingUploaded) {
      // 作画时间到，自动截图上传
      _captureAndUploadDrawing();
    } else if (pool.gamePhase == GamePhase.guessing && !_guessSubmitted) {
      // 猜测时间到，提交空猜测
      _submitGuess('');
    }
  }

  /// 合成所有可见图层为PNG字节（调用画布内部的图层合成逻辑）
  Future<Uint8List?> _compositeLayersToPng() async {
    final artworkState = ref.read(artworkProvider);
    final artwork = artworkState.artwork;
    if (artwork == null) return null;

    final layerState = ref.read(layerProvider);
    final visibleLayers = layerState.layers.where((l) => l.isVisible).toList();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // 白色背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, artwork.width.toDouble(), artwork.height.toDouble()),
      Paint()..color = Colors.white,
    );
    for (final layer in visibleLayers) {
      if (layer.pixels != null) {
        final paint = Paint()..filterQuality = FilterQuality.none;
        if (layer.opacity < 1.0) {
          paint.color = Color.fromRGBO(255, 255, 255, layer.opacity);
        }
        canvas.drawImage(layer.pixels!, Offset.zero, paint);
      }
    }
    final picture = recorder.endRecording();
    final compositeImage = await picture.toImage(artwork.width, artwork.height);

    final byteData = await compositeImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    compositeImage.dispose();
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  }

  /// 保存.mgp项目文件到本地临时目录，返回文件字节
  Future<Uint8List?> _saveMgpLocally() async {
    final artworkState = ref.read(artworkProvider);
    final artwork = artworkState.artwork;
    if (artwork == null) return null;

    final layerState = ref.read(layerProvider);
    final tempDir = await getTemporaryDirectory();
    final tempPath =
        '${tempDir.path}/game_drawing_${DateTime.now().millisecondsSinceEpoch}.mgp';

    final ok = await ProjectService().saveProjectFile(
      artwork: artwork,
      drawLayers: layerState.layers,
      activeLayerIndex: layerState.activeLayerIndex,
      customPath: tempPath,
    );
    if (ok) {
      final file = File(tempPath);
      return await file.readAsBytes();
    }
    return null;
  }

  /// 完成绘画：本地生成.png和.mgp，然后上传到服务器
  Future<void> _captureAndUploadDrawing() async {
    if (_drawingUploaded) return;
    _drawingUploaded = true;

    try {
      // 1. 合成图层生成PNG
      final pngBytes = await _compositeLayersToPng();
      if (pngBytes != null) {
        ref.read(connectionProvider.notifier).sendDrawingUpload(pngBytes);
      }

      // 2. 保存.mgp到本地（作为存档）
      await _saveMgpLocally();
    } catch (_) {}

    ref.read(connectionProvider.notifier).sendDrawingComplete();
    if (mounted) setState(() {});
  }

  /// 提交猜测
  void _submitGuess(String guess) {
    if (_guessSubmitted) return;
    _guessSubmitted = true;
    final cardIndex = _myPickedCardIndex ?? -1;
    if (cardIndex >= 0) {
      ref.read(connectionProvider.notifier).sendGuessSubmit(cardIndex, guess);
    }
    if (mounted) setState(() {});
  }

  /// 构建游戏内容（根据游戏阶段分发）
  Widget _buildGameContent(
    dynamic pool,
    dynamic auth,
    List<RoomMember> members,
  ) {
    final phase = pool.gamePhase as GamePhase;

    return switch (phase) {
      GamePhase.wordPicking => _buildWordPickingPhaseUI(pool, auth),
      GamePhase.drawing => _buildDrawingPhaseUI(pool, auth),
      GamePhase.cardPicking => _buildCardPickingPhaseUI(pool, auth, members),
      GamePhase.guessing => _buildGuessingPhaseUI(pool, auth),
      GamePhase.roundResult => _buildRoundResultUI(pool),
      GamePhase.reviewing => _buildReviewContent(pool, auth, members),
      GamePhase.ended => _buildGameEndUI(pool),
      _ => _buildWaitingUI(),
    };
  }

  /// 在已有顶栏中构建游戏状态元素
  Widget _buildGameStatusInTopBar(dynamic pool, dynamic auth) {
    final phase = pool.gamePhase as GamePhase;
    String phaseText;
    IconData phaseIcon;
    Color phaseColor;

    switch (phase) {
      case GamePhase.wordPicking:
        phaseText = '词条翻牌中';
        phaseIcon = Icons.style_outlined;
        phaseColor = Colors.deepPurple;
        break;
      case GamePhase.drawing:
        phaseText = '正在作画';
        phaseIcon = Icons.brush_outlined;
        phaseColor = Colors.orange;
        break;
      case GamePhase.cardPicking:
        phaseText = '卡牌抽取中';
        phaseIcon = Icons.layers_outlined;
        phaseColor = Colors.blue;
        break;
      case GamePhase.guessing:
        phaseText = '正在猜测';
        phaseIcon = Icons.help_outline;
        phaseColor = Colors.purple;
        break;
      case GamePhase.roundResult:
        phaseText = '回合结算中';
        phaseIcon = Icons.assessment;
        phaseColor = Colors.teal;
        break;
      case GamePhase.reviewing:
        phaseText = '复盘结算中';
        phaseIcon = Icons.assignment_turned_in_outlined;
        phaseColor = Colors.amber;
        break;
      case GamePhase.ended:
        phaseText = '游戏已结束';
        phaseIcon = Icons.emoji_events;
        phaseColor = Colors.amber;
        break;
      case GamePhase.idle:
        phaseText = '待机中';
        phaseIcon = Icons.pause_circle_outline;
        phaseColor = Colors.grey;
        break;
    }

    // Bug 1: 确保系统自动分配卡牌后 _myPickedCardIndex 已更新
    if (_myPickedCardIndex == null &&
        (phase == GamePhase.guessing || phase == GamePhase.cardPicking)) {
      final cardPicks = pool.cardPicks as Map<int, CardPickBroadcast>;
      final myUsername = auth.username as String;
      for (final entry in cardPicks.entries) {
        if (entry.value.username == myUsername) {
          _myPickedCardIndex = entry.key;
          break;
        }
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 阶段标识
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: phaseColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: phaseColor.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(phaseIcon, size: 14, color: phaseColor),
              const SizedBox(width: 6),
              Text(
                phaseText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: phaseColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // 回合信息
        if (pool.currentRound > 0)
          Text(
            '${pool.currentRound}/${pool.totalRounds}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        const SizedBox(width: 16),
        // 分隔线
        Container(
          width: 1,
          height: 20,
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
        const SizedBox(width: 16),

        // 动态插入内容
        if (phase == GamePhase.drawing && _canvasReady) ...[
          // 绘画词
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '绘画词：',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
                Text(
                  pool.drawingWord as String,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 提交按钮
          if (!_drawingUploaded)
            SizedBox(
              height: 32,
              child: FilledButton.icon(
                onPressed: _captureAndUploadDrawing,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.check, size: 14),
                label: const Text(
                  '提交',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            )
          else
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
        ],

        if (phase == GamePhase.guessing) ...[
          if (!_guessSubmitted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 160,
                  height: 32,
                  child: TextField(
                    controller: _guessController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '输入猜测...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty && _myPickedCardIndex != null) {
                        setState(() => _guessSubmitted = true);
                        ref
                            .read(connectionProvider.notifier)
                            .sendGuessSubmit(_myPickedCardIndex!, val.trim());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton.filled(
                    onPressed: () {
                      final val = _guessController.text.trim();
                      if (val.isNotEmpty && _myPickedCardIndex != null) {
                        setState(() => _guessSubmitted = true);
                        ref
                            .read(connectionProvider.notifier)
                            .sendGuessSubmit(_myPickedCardIndex!, val);
                      }
                    },
                    icon: const Icon(Icons.send, size: 14),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.purple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
        ],

        // 倒计时
        if (_gamePhaseSeconds > 0 &&
            (phase == GamePhase.wordPicking ||
                phase == GamePhase.drawing ||
                phase == GamePhase.cardPicking ||
                phase == GamePhase.guessing)) ...[
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _gamePhaseSeconds <= 5
                  ? Colors.red.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: _gamePhaseSeconds <= 5 ? Colors.red : phaseColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_gamePhaseSeconds}s',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: _gamePhaseSeconds <= 5 ? Colors.red : phaseColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 等待中UI
  Widget _buildWaitingUI() {
    return const WaitingUI(message: '等待游戏阶段...');
  }

  // ============ 词条翻牌阶段 ============

  Widget _buildWordPickingPhaseUI(dynamic pool, dynamic auth) {
    final cardCount = pool.wordCardCount as int;
    final wordCardPicks = pool.wordCardPicks as Map<int, CardPickBroadcast>;
    final myPickedWord = pool.myPickedWord as String?;
    final myUsername = auth.username as String;
    final excludeIdx = pool.wordExcludeCardIndex as int;
    final myAlreadyPicked =
        _myWordPickIndex != null ||
        wordCardPicks.values.any((p) => p.username == myUsername);

    // 显示所有卡牌（自己的卡灰色标记，不可点击）
    final allIndices = List.generate(cardCount, (i) => i);

    return Column(
      children: [
        // 提示 + 已选词条展示
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                myAlreadyPicked && myPickedWord != null
                    ? '你抽到的词条'
                    : '翻开一张卡牌抽取你的绘画词条',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (myAlreadyPicked && myPickedWord != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    myPickedWord,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '等待其他玩家翻牌...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        // 卡牌网格（与猜测阶段一致的布局，自己的卡灰色显示）
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const cardWidth = 150.0;
              const cardHeight = 200.0;
              const spacing = 30.0;
              final availableWidth = constraints.maxWidth;
              int columns = ((availableWidth + spacing) / (cardWidth + spacing))
                  .floor();
              if (columns < 1) columns = 1;
              final gridWidth = columns * cardWidth + (columns - 1) * spacing;
              final horizontalPadding = max(
                0.0,
                (availableWidth - gridWidth) / 2,
              );

              return GridView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 12,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: cardHeight,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: allIndices.length,
                itemBuilder: (context, cardIdx) {
                  final isMyOwnCard = cardIdx == excludeIdx;
                  final pick = wordCardPicks[cardIdx];
                  final isFlipped = pick != null;
                  final isMyPick = pick?.username == myUsername;
                  final canPick =
                      !myAlreadyPicked && !isFlipped && !isMyOwnCard;

                  // 自己的卡牌：未被抽取时灰色禁用；被抽取后展示抽取者信息
                  if (isMyOwnCard && !isFlipped) {
                    return _buildWordCardOwn(
                      key: ValueKey('wo_$cardIdx'),
                      index: cardIdx,
                    );
                  }

                  if (isMyOwnCard && isFlipped) {
                    return _buildWordCardFront(
                      key: ValueKey('wf_$cardIdx'),
                      isMyPick: false,
                      pick: pick,
                      myPickedWord: myPickedWord,
                    );
                  }

                  return GestureDetector(
                    onTap: canPick
                        ? () {
                            setState(() => _myWordPickIndex = cardIdx);
                            ref
                                .read(connectionProvider.notifier)
                                .sendCardPick(cardIdx);
                          }
                        : null,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        );
                      },
                      child: isFlipped
                          ? _buildWordCardFront(
                              key: ValueKey('wf_$cardIdx'),
                              isMyPick: isMyPick,
                              pick: pick,
                              myPickedWord: myPickedWord,
                            )
                          : _buildWordCardBack(
                              key: ValueKey('wb_$cardIdx'),
                              index: cardIdx,
                              canPick: canPick,
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWordCardFront({
    required Key key,
    required bool isMyPick,
    required CardPickBroadcast? pick,
    required String? myPickedWord,
  }) {
    return WordCardFront(
      key: key,
      isMyPick: isMyPick,
      pick: pick,
      myPickedWord: myPickedWord,
    );
  }

  Widget _buildWordCardBack({
    required Key key,
    required int index,
    required bool canPick,
  }) {
    return WordCardBack(key: key, index: index, canPick: canPick);
  }

  /// 自己的词条卡牌（灰色禁用状态）
  Widget _buildWordCardOwn({required Key key, required int index}) {
    return WordCardOwn(key: key, index: index);
  }

  // ============ 作画阶段 ============

  /// 弹出画布尺寸选择对话框，确认后初始化画布
  void _showGameCanvasDialog() {
    if (_isCanvasDialogOpen) return; // 防止重复弹出
    _isCanvasDialogOpen = true;
    final widthController = TextEditingController(text: '1920');
    final heightController = TextEditingController(text: '1080');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('选择画布尺寸'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widthController,
                    decoration: const InputDecoration(
                      labelText: '宽度',
                      border: OutlineInputBorder(),
                      suffixText: 'px',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: heightController,
                    decoration: const InputDecoration(
                      labelText: '高度',
                      border: OutlineInputBorder(),
                      suffixText: 'px',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('2k'),
                  onPressed: () {
                    widthController.text = '2560';
                    heightController.text = '1440';
                  },
                ),
                ActionChip(
                  label: const Text('1080p'),
                  onPressed: () {
                    widthController.text = '1920';
                    heightController.text = '1080';
                  },
                ),
                ActionChip(
                  label: const Text('720p'),
                  onPressed: () {
                    widthController.text = '1280';
                    heightController.text = '720';
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final width = int.tryParse(widthController.text) ?? 1920;
              final height = int.tryParse(heightController.text) ?? 1080;
              Navigator.pop(ctx);
              _isCanvasDialogOpen = false;
              // 初始化画布：重置图层 → 创建新画作
              ref.read(layerProvider.notifier).reset();
              await ref
                  .read(artworkProvider.notifier)
                  .createNew(name: '游戏绘画', width: width, height: height);
              if (mounted) {
                setState(() => _canvasReady = true);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawingPhaseUI(dynamic pool, dynamic auth) {
    // 画布未初始化时显示选择尺寸界面
    if (!_canvasReady) {
      // 自动弹出对话框（仅一次，通过双重标记防止重复弹出）
      if (!_canvasDialogShown && !_isCanvasDialogOpen) {
        _canvasDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              !_canvasReady &&
              !_drawingUploaded &&
              !_isCanvasDialogOpen) {
            _showGameCanvasDialog();
          }
        });
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.brush_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            const Text('请先选择画布尺寸...'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _showGameCanvasDialog,
              child: const Text('选择画布尺寸'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 画布区域（直接嵌入CanvasScreen）
        Expanded(child: const CanvasScreen()),
      ],
    );
  }

  // ============ 卡牌抽取阶段 ============

  Widget _buildCardPickingPhaseUI(
    dynamic pool,
    dynamic auth,
    List<RoomMember> members,
  ) {
    final guessCards = pool.guessCards as List<GuessCard>;
    final cardPicks = pool.cardPicks as Map<int, CardPickBroadcast>;
    final myUsername = auth.username as String;
    final myAlreadyPicked = cardPicks.values.any(
      (p) => p.username == myUsername,
    );

    // Bug 1: 如果系统自动分配了卡牌（cardPickBroadcast已到达），自动更新 _myPickedCardIndex
    if (myAlreadyPicked && _myPickedCardIndex == null) {
      for (final entry in cardPicks.entries) {
        if (entry.value.username == myUsername) {
          _myPickedCardIndex = entry.key;
          break;
        }
      }
    }

    // Bug 4: 显示所有卡牌（自己的卡灰色标记，不可点击）
    final allIndices = List.generate(guessCards.length, (i) => i);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '选择一张卡牌查看对方的画作',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const cardWidth = 150.0;
              const cardHeight = 200.0;
              const spacing = 30.0;
              final availableWidth = constraints.maxWidth;
              int columns = ((availableWidth + spacing) / (cardWidth + spacing))
                  .floor();
              if (columns < 1) columns = 1;
              final gridWidth = columns * cardWidth + (columns - 1) * spacing;
              final horizontalPadding = max(
                0.0,
                (availableWidth - gridWidth) / 2,
              );

              return GridView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 12,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: cardHeight,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: allIndices.length,
                itemBuilder: (context, cardIdx) {
                  final card = guessCards[cardIdx];
                  final pick = cardPicks[cardIdx];
                  final isFlipped = pick != null;
                  final isMyPick = pick != null && pick.username == myUsername;
                  final isMyOwnCard = card.username == myUsername;
                  final canPick =
                      !myAlreadyPicked && !isFlipped && !isMyOwnCard;

                  // 自己的卡牌：未被抽取时灰色禁用；被抽取后展示抽取者信息
                  if (isMyOwnCard && !isFlipped) {
                    return _buildGuessCardOwn(
                      key: ValueKey('go_$cardIdx'),
                      index: cardIdx,
                    );
                  }

                  if (isMyOwnCard && isFlipped) {
                    return _buildGuessCardFront(
                      key: ValueKey('gf_$cardIdx'),
                      isMyPick: false,
                      card: card,
                      pick: pick,
                    );
                  }

                  return GestureDetector(
                    onTap: canPick
                        ? () {
                            _myPickedCardIndex = cardIdx;
                            ref
                                .read(connectionProvider.notifier)
                                .sendCardPick(cardIdx);
                          }
                        : null,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        );
                      },
                      child: isFlipped
                          ? _buildGuessCardFront(
                              key: ValueKey('gf_$cardIdx'),
                              isMyPick: isMyPick,
                              card: card,
                              pick: pick,
                            )
                          : _buildGuessCardBack(
                              key: ValueKey('gb_$cardIdx'),
                              index: cardIdx,
                              canPick: canPick,
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// 自己的画作卡牌（灰色禁用状态）
  Widget _buildGuessCardOwn({required Key key, required int index}) {
    return GuessCardOwn(key: key, index: index);
  }

  Widget _buildGuessCardFront({
    required Key key,
    required bool isMyPick,
    required GuessCard card,
    required CardPickBroadcast? pick,
  }) {
    return GuessCardFront(key: key, isMyPick: isMyPick, card: card, pick: pick);
  }

  Widget _buildGuessCardBack({
    required Key key,
    required int index,
    required bool canPick,
  }) {
    return GuessCardBack(key: key, index: index, canPick: canPick);
  }

  // ============ 猜测阶段 ============

  Widget _buildGuessingPhaseUI(dynamic pool, dynamic auth) {
    final pngData = pool.receivedDrawingPng as Uint8List?;
    final author = pool.receivedDrawingAuthor as String?;

    // Bug 1: 如果系统自动分配了卡牌，确保 _myPickedCardIndex 已更新
    if (_myPickedCardIndex == null) {
      final cardPicks = pool.cardPicks as Map<int, CardPickBroadcast>;
      final myUsername = auth.username as String;
      for (final entry in cardPicks.entries) {
        if (entry.value.username == myUsername) {
          _myPickedCardIndex = entry.key;
          break;
        }
      }
    }

    return Column(
      children: [
        // 绘画展示区域
        Expanded(
          child: pngData != null
              ? Column(
                  children: [
                    if (author != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '来自: $author 的画作',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(pngData, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_not_supported_outlined,
                        size: 64,
                        color: Colors.grey.withOpacity(0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '该成员未提交画作',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
  // ============ 回合结算 ============

  Widget _buildReviewContent(
    ConnectionPoolState pool,
    dynamic auth,
    List<RoomMember> members,
  ) {
    if (pool.showPodium == true) {
      return _buildScorePodiumUI(pool);
    }
    final replay = pool.replayData;
    if (replay == null) {
      return const Center(child: Text('等待复盘数据...'));
    }

    final tracks = replay['tracks'] as List<dynamic>;
    final pathIdx = pool.reviewPathIndex;
    final serverStepIndex = pool.reviewStepIndex;
    if (pathIdx >= tracks.length) {
      return const Center(child: Text('复盘已结束'));
    }

    final currentTrack = tracks[pathIdx];
    final steps = currentTrack['steps'] as List<dynamic>;

    // 服务端 stepIndex 语义为“已展示步数”。
    // - steps 播放中：serverStepIndex = 1..steps.length，对应显示 stepIndex-1
    // - 投票/最爱阶段：serverStepIndex == steps.length，应显示总结页（stepIdx==steps.length）
    final stepIdx = steps.isEmpty
        ? 0
        : (serverStepIndex <= 0
              ? 0
              : min(steps.length - 1, serverStepIndex - 1));

    // 同步到本地字段（仅用于 AnimatedSwitcher 的 key 等，不做推进）
    _currentReviewPathIdx = pathIdx;
    _currentReviewStepIdx = stepIdx;
    final originOwnerFp = currentTrack['originOwnerFp'] as String;

    return Row(
      children: [
        SizedBox(
          width: 260,
          child: _buildReviewUserList(members, pool, originOwnerFp),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: _buildReviewStage(pool, currentTrack, steps),
              ),
              if (pool.isVoting) _buildVotingOverlay(pool, currentTrack),
              if (pool.canPickFavorite)
                _buildFavoriteSelectionOverlay(pool, currentTrack),
              _buildReviewDanmakuOverlay(pool),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewUserList(
    List<RoomMember> members,
    ConnectionPoolState pool,
    String highlightedFp,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: members.length,
        itemBuilder: (context, index) {
          final member = members[index];
          final isHighlighted = member.fingerprintHex == highlightedFp;
          final score = pool.memberScores[member.fingerprintHex] ?? 0;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isHighlighted
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
              color: isHighlighted
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.05)
                  : null,
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                child: Text(
                  member.username.isNotEmpty
                      ? member.username[0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              title: Text(
                '${member.username}#${member.fingerprintHex.length >= 4 ? member.fingerprintHex.substring(0, 4) : member.fingerprintHex}',
                style: const TextStyle(fontSize: 13),
              ),
              trailing: AnimatedScale(
                scale: _scorePulseTokens.containsKey(member.fingerprintHex)
                    ? 1.25
                    : 1.0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _scorePulseTokens.containsKey(member.fingerprintHex)
                        ? Colors.amber.withOpacity(0.22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$score分',
                    key: _getScoreAnchorKey(member.fingerprintHex),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewStage(
    ConnectionPoolState pool,
    dynamic currentTrack,
    List<dynamic> steps,
  ) {
    if (_isClearingReviewStage) {
      return const SizedBox.expand();
    }

    // 投票阶段由投票蒙层展示“原词->最终词”，避免与总结页重复显示
    if (_currentReviewStepIdx >= steps.length && pool.isVoting) {
      return const SizedBox.expand();
    }

    // 最爱画作结果：在服务端推进到下一条路径前的 3 秒窗口里，展示描边高亮
    final favoriteIndex = pool.favoriteChosenIndex;
    if (!pool.isVoting &&
        !pool.canPickFavorite &&
        favoriteIndex != null &&
        favoriteIndex >= 0 &&
        favoriteIndex < steps.length) {
      final step = steps[favoriteIndex];
      return Center(
        child: Container(
          key: _favoriteAnchorKey,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber, width: 4),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 18),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '最爱画作',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 520,
                height: 420,
                child: _buildReviewStepCard(step),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
      child: _buildReviewStepCard(
        steps[_currentReviewStepIdx],
        key: ValueKey('$_currentReviewPathIdx-$_currentReviewStepIdx'),
      ),
    );
  }

  Widget _buildWordBadge(String word, Color color) {
    return WordBadge(word: word, color: color);
  }

  Widget _buildReviewStepCard(dynamic step, {Key? key}) {
    return ReviewStepCard(
      key: key,
      step: Map<String, dynamic>.from(step),
      showGuessInfo: _showGuessInfo,
      pngCache: _reviewPngCache,
    );
  }

  Widget _buildVotingOverlay(ConnectionPoolState pool, dynamic currentTrack) {
    final lastStep = (currentTrack['steps'] as List).last;
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '评价还原度',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildWordBadge(currentTrack['originWord'], Colors.blue),
                  const SizedBox(width: 12),
                  const Icon(Icons.trending_flat, color: Colors.grey),
                  const SizedBox(width: 12),
                  _buildWordBadge(lastStep['guessText'], Colors.orange),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildVoteButton(true),
                  const SizedBox(width: 60),
                  _buildVoteButton(false),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoteButton(bool isUp) {
    return InkWell(
      onTap: () => ref.read(connectionProvider.notifier).sendVoteSubmit(isUp),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(
              isUp ? Icons.check_circle : Icons.cancel,
              size: 72,
              color: isUp ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 8),
            Text(
              isUp ? '像' : '不像',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isUp ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteSelectionOverlay(
    ConnectionPoolState pool,
    dynamic currentTrack,
  ) {
    final steps = currentTrack['steps'] as List<dynamic>;
    final auth = ref.watch(authProvider);
    final isPicker =
        pool.favoritePickerUsername.isNotEmpty &&
        auth.username.toLowerCase() ==
            pool.favoritePickerUsername.toLowerCase();
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 48, 24, 24),
            child: Text(
              '请选择你最喜欢的画作（作者+5分）',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!isPicker)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '等待 ${pool.favoritePickerUsername} 选择中...',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(32),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
                childAspectRatio: 1.1,
              ),
              itemCount: steps.length,
              itemBuilder: (context, index) {
                final step = steps[index];
                final pngBase64 = step['pngBase64'] as String;
                Uint8List? imageBytes;
                if (pngBase64.isNotEmpty) {
                  try {
                    imageBytes = base64Decode(pngBase64);
                  } catch (_) {}
                }

                return InkWell(
                  onTap: isPicker
                      ? () => ref
                            .read(connectionProvider.notifier)
                            .sendFavoriteSubmit(index)
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            step['drawerName'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: imageBytes != null
                                ? Image.memory(imageBytes, fit: BoxFit.contain)
                                : const Icon(
                                    Icons.image,
                                    color: Colors.white54,
                                    size: 48,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewDanmakuOverlay(ConnectionPoolState pool) {
    return IgnorePointer(
      child: Stack(
        children: pool.voteBarrages.asMap().entries.map((entry) {
          final idx = entry.key;
          final v = entry.value;
          final isUp = v['isUp'] as bool;
          return Positioned(
            top: 100 + (idx % 5) * 60.0,
            right: 20,
            child: VoteBarrageItem(username: v['username'], isUp: isUp),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRoundResultUI(dynamic pool) {
    final results = pool.roundResults as List<Map<String, dynamic>>;
    final round = pool.currentRound as int;
    final totalRounds = pool.totalRounds as int;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '第 $round 回合结算',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? const Center(child: Text('等待结算数据...'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final r = results[index];
                    final username = r['username'] ?? '';
                    final drawWord = r['drawWord'] ?? '';
                    final guess = r['guess'] ?? '未猜测';
                    final targetUsername = r['targetUsername'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            username.isNotEmpty
                                ? username[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(
                          username,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('画的: $drawWord'),
                            if (targetUsername.isNotEmpty)
                              Text('猜 $targetUsername 的画: $guess'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            round < totalRounds ? '即将进入下一回合...' : '所有回合结束',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  // ============ 游戏结束 ============

  Widget _buildGameEndUI(dynamic pool) {
    if (pool.showPodium == true) {
      return _buildScorePodiumUI(pool);
    }
    final allResults = pool.allGameResults as List<Map<String, dynamic>>;

    return Column(
      children: [
        const SizedBox(height: 32),
        Icon(Icons.emoji_events, size: 64, color: Colors.amber.shade600),
        const SizedBox(height: 16),
        Text(
          '游戏结束！',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '共完成 ${allResults.length} 回合',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: allResults.isEmpty
              ? const Center(child: Text('暂无结算数据'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: allResults.length,
                  itemBuilder: (context, index) {
                    final roundData = allResults[index];
                    final round = roundData['round'] ?? (index + 1);
                    final results =
                        (roundData['results'] as List<dynamic>?)
                            ?.map((r) => r as Map<String, dynamic>)
                            .toList() ??
                        [];

                    return ExpansionTile(
                      title: Text(
                        '第 $round 回合',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: results.map((r) {
                        return ListTile(
                          dense: true,
                          title: Text(r['username'] ?? ''),
                          subtitle: Text(
                            '画: ${r['drawWord'] ?? ''} | 猜: ${r['guess'] ?? '未猜测'}',
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () {
              ref.read(connectionProvider.notifier).resetGame();
              setState(() => _topMode = 0);
            },
            child: const Text('返回大厅'),
          ),
        ),
      ],
    );
  }

  Widget _buildScorePodiumUI(ConnectionPoolState pool) {
    final top3 = pool.podiumTop3;
    final endAtMs = pool.podiumEndAtMs;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final left = endAtMs > 0 ? ((endAtMs - nowMs) / 1000).ceil() : 0;
    if (left != _podiumSecondsLeft) {
      _podiumTimer?.cancel();
      _podiumSecondsLeft = max(0, left);
      if (_podiumSecondsLeft > 0) {
        _podiumTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          final l = endAtMs > 0 ? ((endAtMs - now) / 1000).ceil() : 0;
          setState(() {
            _podiumSecondsLeft = max(0, l);
          });
          if (_podiumSecondsLeft <= 0) {
            t.cancel();
          }
        });
      }
    }

    String nameAt(int idx) {
      if (idx < 0 || idx >= top3.length) return '';
      return (top3[idx]['username'] ?? '').toString();
    }

    Widget podiumColumn({
      required double height,
      required Color color,
      required String title,
      required String name,
    }) {
      return PodiumColumn(
        height: height,
        color: color,
        title: title,
        name: name,
      );
    }

    return Column(
      children: [
        const SizedBox(height: 26),
        Text(
          '本局前三',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _podiumSecondsLeft > 0 ? '$_podiumSecondsLeft 秒后返回大厅' : '即将返回大厅…',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 26),
        Expanded(
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                podiumColumn(
                  height: 210,
                  color: Colors.grey.shade600,
                  title: '2',
                  name: nameAt(1),
                ),
                const SizedBox(width: 18),
                podiumColumn(
                  height: 270,
                  color: Colors.amber.shade700,
                  title: '1',
                  name: nameAt(0),
                ),
                const SizedBox(width: 18),
                podiumColumn(
                  height: 180,
                  color: Colors.brown.shade600,
                  title: '3',
                  name: nameAt(2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  // ============ 协同画布 ============

  /// 构建协同画布区域
  Widget _buildCollabCanvasArea(BuildContext context) {
    final artworkState = ref.watch(artworkProvider);
    final layerNotifier = ref.read(layerProvider.notifier);
    final isInited = artworkState.isInitialized && artworkState.artwork != null;

    final w =
        _tempCanvasWidth ??
        (layerNotifier.canvasWidth > 0 ? layerNotifier.canvasWidth : 1280);
    final h =
        _tempCanvasHeight ??
        (layerNotifier.canvasHeight > 0 ? layerNotifier.canvasHeight : 720);

    if (!isInited) {
      if (!_collabCanvasAutoInitRequested) {
        _collabCanvasAutoInitRequested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          try {
            layerNotifier.reset();
            await ref
                .read(artworkProvider.notifier)
                .createNew(name: '协同画布', width: w, height: h);
          } catch (_) {
            _collabCanvasAutoInitRequested = false;
          }
        });
      }
      return const Center(
        child: SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在初始化画布...'),
            ],
          ),
        ),
      );
    }

    final artwork = artworkState.artwork;
    if (artwork != null &&
        (artwork.width != w || artwork.height != h) &&
        (_tempCanvasWidth != null || _tempCanvasHeight != null)) {
      return Center(
        child: SizedBox(
          width: 360,
          child: FilledButton.icon(
            onPressed: () async {
              layerNotifier.reset();
              await ref
                  .read(artworkProvider.notifier)
                  .createNew(name: '协同画布', width: w, height: h);
            },
            icon: const Icon(Icons.crop_free),
            label: Text('应用画布大小（$w×$h）'),
          ),
        ),
      );
    }

    return const CanvasScreen();
  }
}
