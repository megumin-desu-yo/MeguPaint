import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'auth_provider.dart';
import '../../services/network/tcp_client_service.dart'
    show
        ConnectionStatus,
        ConnectionState,
        TcpClientService,
        CollabDeltaRequest,
        RoomInfo,
        JoinRoomResponse,
        CreateRoomResponse,
        RoomMember,
        RoomMemberUpdate,
        MessageType,
        ChatMessage,
        RoomOwnerTransfer,
        RoomSettingUpdate,
        CardPickBroadcast,
        DrawingPhaseBroadcast,
        GuessPhaseBroadcast,
        GuessCard,
        DrawingImageData,
        GuessResultBroadcast,
        RoundResultBroadcast,
        GameEndBroadcast,
        ReplayFileBroadcast,
        WordPickPhaseBroadcast,
        WordPickResult,
        VoteResultBroadcast,
        FavoriteSelectionStartBroadcast,
        FavoriteResultBroadcast,
        ScoreUpdateBroadcast,
        ReviewProgressBroadcast,
        ScorePodiumBroadcast,
        GameResetBroadcast,
        CollabDeltaBroadcast,
        CollabSyncRequired,
        CollabSnapshotFromServer,
        CollabLayerOpRequest,
        CollabLayerOpType,
        CollabLayerOpBroadcast,
        CollabLayerDeltaRequest,
        CollabLayerDeltaBroadcast,
        CollabMultiLayerSnapshot;
import '../../services/delta/region_delta.dart';

import 'layer_provider.dart';
import 'artwork_provider.dart';

/// 游戏阶段枚举（客户端侧）
enum GamePhase {
  idle, // 未开始/大厅
  wordPicking, // 词条翻牌阶段
  drawing, // 作画阶段
  cardPicking, // 卡牌抽取阶段
  guessing, // 猜测阶段
  roundResult, // 回合结算
  reviewing, // 复盘中
  ended, // 游戏结束
}

class ConnectionPoolState {
  final Map<String, ConnectionState> connections;
  final String savedServerIp;
  final int savedServerPort;
  final List<RoomInfo> rooms;
  final String? currentRoomId;
  final String? currentRoomServerKey;
  final List<RoomMember> roomMembers;
  final List<ChatMessage> chatMessages;
  final String? roomLexiconJson; // 当前房间词库数据
  final bool isGameActive; // 游戏是否进行中
  final List<int> gameCardIndices; // 游戏卡牌索引列表（词库中的位置）
  final Map<int, CardPickBroadcast> cardPicks; // 已选卡牌: cardIndex -> 选择者信息

  // 多回合游戏状态
  final GamePhase gamePhase; // 当前游戏阶段
  final int currentRound; // 当前回合（1-based）
  final int totalRounds; // 总回合数
  final String drawingWord; // 当前回合分配的绘画词
  final int drawTime; // 作画时间（秒）
  final int guessTime; // 猜测时间（秒）
  final int cardPickTime; // 抽卡时间（秒）
  final List<GuessCard> guessCards; // 猜测阶段卡牌列表
  final Uint8List? receivedDrawingPng; // 收到的绘画PNG数据
  final String? receivedDrawingAuthor; // 绘画作者用户名
  final String? receivedDrawingFp; // 绘画作者指纹
  final int? pickedCardIndex; // 当前用户选择的卡牌索引
  final List<Map<String, dynamic>> roundResults; // 回合结果
  final List<Map<String, dynamic>> allGameResults; // 所有回合结果（游戏结束时）
  final Map<String, String> guessResultsMap; // 猜测者fp -> 猜测文本

  // 复盘阶段状态
  final Map<String, dynamic>? replayData; // 完整复盘数据
  final bool isVoting; // 是否处于投票阶段
  final List<Map<String, dynamic>> voteBarrages; // 投票弹幕: {username, isUp}
  final Map<String, int> memberScores; // 成员积分: fp -> score
  final bool canPickFavorite; // 是否可以挑选最爱画作（第一棒特权）
  final String favoritePickerUsername; // 最爱画作选择者用户名（仅该用户可点）
  final int? favoriteChosenIndex; // 最爱画作结果（用于描边展示）
  final int reviewPathIndex; // 当前复盘路径（服务端驱动）
  final int reviewStepIndex; // 当前复盘步骤（服务端驱动）

  final bool showPodium; // 是否展示领奖台
  final int podiumEndAtMs; // 领奖台结束时间戳(ms)
  final List<Map<String, dynamic>>
  podiumTop3; // [{username, fingerprintHex, score}]

  // 词条翻牌阶段
  final int wordCardCount; // 词条卡牌数量
  final Map<int, CardPickBroadcast> wordCardPicks; // 词条卡牌选择: cardIndex -> 选择者信息
  final String? myPickedWord; // 我抽到的词条
  final int wordPickTime; // 词条翻牌时间（秒）
  final int wordExcludeCardIndex; // 词条翻牌排除的卡牌索引（-1无排除）
  final List<String> wordCardOwnerNames; // 词条卡牌所属者用户名列表（与卡牌索引对应）

  const ConnectionPoolState({
    this.connections = const {},
    this.savedServerIp = '',
    this.savedServerPort = 9527,
    this.rooms = const [],
    this.currentRoomId,
    this.currentRoomServerKey,
    this.roomMembers = const [],
    this.chatMessages = const [],
    this.roomLexiconJson,
    this.isGameActive = false,
    this.gameCardIndices = const [],
    this.cardPicks = const {},
    this.gamePhase = GamePhase.idle,
    this.currentRound = 0,
    this.totalRounds = 0,
    this.drawingWord = '',
    this.drawTime = 60,
    this.guessTime = 30,
    this.cardPickTime = 10,
    this.guessCards = const [],
    this.receivedDrawingPng,
    this.receivedDrawingAuthor,
    this.receivedDrawingFp,
    this.pickedCardIndex,
    this.roundResults = const [],
    this.allGameResults = const [],
    this.guessResultsMap = const {},
    this.replayData,
    this.isVoting = false,
    this.voteBarrages = const [],
    this.memberScores = const {},
    this.canPickFavorite = false,
    this.favoritePickerUsername = '',
    this.favoriteChosenIndex,
    this.reviewPathIndex = 0,
    this.reviewStepIndex = 0,
    this.showPodium = false,
    this.podiumEndAtMs = 0,
    this.podiumTop3 = const [],
    this.wordCardCount = 0,
    this.wordCardPicks = const {},
    this.myPickedWord,
    this.wordPickTime = 10,
    this.wordExcludeCardIndex = -1,
    this.wordCardOwnerNames = const [],
  });

  ConnectionPoolState copyWith({
    Map<String, ConnectionState>? connections,
    String? savedServerIp,
    int? savedServerPort,
    List<RoomInfo>? rooms,
    String? currentRoomId,
    String? currentRoomServerKey,
    List<RoomMember>? roomMembers,
    List<ChatMessage>? chatMessages,
    String? roomLexiconJson,
    bool? isGameActive,
    List<int>? gameCardIndices,
    Map<int, CardPickBroadcast>? cardPicks,
    GamePhase? gamePhase,
    int? currentRound,
    int? totalRounds,
    String? drawingWord,
    int? drawTime,
    int? guessTime,
    int? cardPickTime,
    List<GuessCard>? guessCards,
    Uint8List? receivedDrawingPng,
    String? receivedDrawingAuthor,
    String? receivedDrawingFp,
    int? pickedCardIndex,
    List<Map<String, dynamic>>? roundResults,
    List<Map<String, dynamic>>? allGameResults,
    Map<String, String>? guessResultsMap,
    Map<String, dynamic>? replayData,
    bool? isVoting,
    List<Map<String, dynamic>>? voteBarrages,
    Map<String, int>? memberScores,
    bool? canPickFavorite,
    String? favoritePickerUsername,
    int? favoriteChosenIndex,
    bool clearFavoriteChosenIndex = false,
    int? reviewPathIndex,
    int? reviewStepIndex,

    bool? showPodium,
    int? podiumEndAtMs,
    List<Map<String, dynamic>>? podiumTop3,
    int? wordCardCount,
    Map<int, CardPickBroadcast>? wordCardPicks,
    String? myPickedWord,
    int? wordPickTime,
    int? wordExcludeCardIndex,
    List<String>? wordCardOwnerNames,
    bool clearCurrentRoom = false,
    bool clearLexicon = false,
    bool clearGame = false,
    bool clearDrawingImage = false,
    bool clearPickedCard = false,
    bool clearWordPick = false,
  }) {
    final shouldClearGame = clearCurrentRoom || clearGame;
    return ConnectionPoolState(
      connections: connections ?? this.connections,
      savedServerIp: savedServerIp ?? this.savedServerIp,
      savedServerPort: savedServerPort ?? this.savedServerPort,
      rooms: rooms ?? this.rooms,
      currentRoomId: clearCurrentRoom
          ? null
          : (currentRoomId ?? this.currentRoomId),
      currentRoomServerKey: clearCurrentRoom
          ? null
          : (currentRoomServerKey ?? this.currentRoomServerKey),
      roomMembers: clearCurrentRoom ? [] : (roomMembers ?? this.roomMembers),
      chatMessages: clearCurrentRoom ? [] : (chatMessages ?? this.chatMessages),
      roomLexiconJson: clearCurrentRoom || clearLexicon
          ? null
          : (roomLexiconJson ?? this.roomLexiconJson),
      isGameActive: shouldClearGame
          ? false
          : (isGameActive ?? this.isGameActive),
      gameCardIndices: shouldClearGame
          ? const []
          : (gameCardIndices ?? this.gameCardIndices),
      cardPicks: shouldClearGame ? const {} : (cardPicks ?? this.cardPicks),
      gamePhase: shouldClearGame
          ? GamePhase.idle
          : (gamePhase ?? this.gamePhase),
      currentRound: shouldClearGame ? 0 : (currentRound ?? this.currentRound),
      totalRounds: shouldClearGame ? 0 : (totalRounds ?? this.totalRounds),
      drawingWord: shouldClearGame ? '' : (drawingWord ?? this.drawingWord),
      drawTime: shouldClearGame ? 60 : (drawTime ?? this.drawTime),
      guessTime: shouldClearGame ? 30 : (guessTime ?? this.guessTime),
      cardPickTime: shouldClearGame ? 10 : (cardPickTime ?? this.cardPickTime),
      guessCards: shouldClearGame ? const [] : (guessCards ?? this.guessCards),
      receivedDrawingPng: shouldClearGame || clearDrawingImage
          ? null
          : (receivedDrawingPng ?? this.receivedDrawingPng),
      receivedDrawingAuthor: shouldClearGame || clearDrawingImage
          ? null
          : (receivedDrawingAuthor ?? this.receivedDrawingAuthor),
      receivedDrawingFp: shouldClearGame || clearDrawingImage
          ? null
          : (receivedDrawingFp ?? this.receivedDrawingFp),
      pickedCardIndex: shouldClearGame || clearPickedCard
          ? null
          : (pickedCardIndex ?? this.pickedCardIndex),
      roundResults: shouldClearGame
          ? const []
          : (roundResults ?? this.roundResults),
      allGameResults: shouldClearGame
          ? const []
          : (allGameResults ?? this.allGameResults),
      guessResultsMap: shouldClearGame
          ? const {}
          : (guessResultsMap ?? this.guessResultsMap),
      replayData: shouldClearGame ? null : (replayData ?? this.replayData),
      isVoting: shouldClearGame ? false : (isVoting ?? this.isVoting),
      voteBarrages: voteBarrages ?? this.voteBarrages,
      memberScores: memberScores ?? this.memberScores,
      canPickFavorite: canPickFavorite ?? this.canPickFavorite,
      favoritePickerUsername:
          favoritePickerUsername ?? this.favoritePickerUsername,
      favoriteChosenIndex: clearFavoriteChosenIndex
          ? null
          : (favoriteChosenIndex ?? this.favoriteChosenIndex),
      reviewPathIndex: reviewPathIndex ?? this.reviewPathIndex,
      reviewStepIndex: shouldClearGame
          ? 0
          : (reviewStepIndex ?? this.reviewStepIndex),

      showPodium: shouldClearGame ? false : (showPodium ?? this.showPodium),
      podiumEndAtMs: shouldClearGame
          ? 0
          : (podiumEndAtMs ?? this.podiumEndAtMs),
      podiumTop3: shouldClearGame ? const [] : (podiumTop3 ?? this.podiumTop3),
      wordCardCount:
          wordCardCount ??
          (shouldClearGame || clearWordPick ? 0 : this.wordCardCount),
      wordCardPicks:
          wordCardPicks ??
          (shouldClearGame || clearWordPick ? const {} : this.wordCardPicks),
      myPickedWord: shouldClearGame || clearWordPick
          ? null
          : (myPickedWord ?? this.myPickedWord),
      wordPickTime:
          wordPickTime ??
          (shouldClearGame || clearWordPick ? 10 : this.wordPickTime),
      wordExcludeCardIndex:
          wordExcludeCardIndex ??
          (shouldClearGame || clearWordPick ? -1 : this.wordExcludeCardIndex),
      wordCardOwnerNames:
          wordCardOwnerNames ??
          (shouldClearGame || clearWordPick
              ? const []
              : this.wordCardOwnerNames),
    );
  }

  /// 当前是否处于协同创作房间（roomTypeCode == 0x02）
  bool get isCollabRoom {
    final rid = currentRoomId;
    if (rid == null) return false;
    try {
      final room = rooms.firstWhere(
        (r) => r.roomId.toLowerCase() == rid.toLowerCase(),
      );
      return room.roomTypeCode == 0x02;
    } catch (_) {
      return false;
    }
  }
}

class ConnectionNotifier extends StateNotifier<ConnectionPoolState> {
  static const String _boxName = 'connection';
  static const String _serversKey = 'servers';
  static const String _savedIpKey = 'serverIp';
  static const String _savedPortKey = 'serverPort';

  // ...
  static const Duration _heartbeatInterval = Duration(
    seconds: 20,
  ); //这里修改心跳间隔，这里改了服务器也要改

  final Ref ref;
  final Map<String, TcpClientService> _services = {};
  final Map<String, StreamSubscription> _memberSubscriptions = {};
  final Map<String, Timer> _heartbeatTimers = {};

  int _favoriteCloseToken = 0;
  Timer? _settingChangeTimer;
  final Map<String, String> _pendingChanges = {}; // key: 设置项, value: 最终描述

  ConnectionNotifier(this.ref) : super(const ConnectionPoolState()) {
    _loadSavedConfig();
  }

  void _startHeartbeat(String key) {
    if (_heartbeatTimers.containsKey(key)) return;
    final service = _services[key];
    if (service == null || !service.state.isConnected) return;
    _heartbeatTimers[key] = Timer.periodic(_heartbeatInterval, (_) {
      _services[key]?.sendHeartbeat();
    });
  }

  void _stopHeartbeat(String key) {
    final timer = _heartbeatTimers.remove(key);
    timer?.cancel();
  }

  String _makeKey(String ip, int port) => '$ip:$port';

  (String, int) _parseIpPort(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return ('', 9527);

    final idx = trimmed.lastIndexOf(':');
    if (idx > 0 && idx < trimmed.length - 1) {
      final ip = trimmed.substring(0, idx);
      final port = int.tryParse(trimmed.substring(idx + 1)) ?? 9527;
      return (ip, port);
    }
    return (trimmed, 9527);
  }

  Future<void> _loadSavedConfig() async {
    try {
      final box = await Hive.openBox(_boxName);
      final savedIp = box.get(_savedIpKey, defaultValue: '') as String;
      final savedPort = box.get(_savedPortKey, defaultValue: 9527) as int;

      final servers = box.get(_serversKey);
      final Map<String, ConnectionState> loaded = {};

      if (servers != null && servers is List) {
        for (final item in servers) {
          if (item is Map) {
            final ip = item['ip'] as String? ?? '';
            final port = item['port'] as int? ?? 9527;
            if (ip.isEmpty) continue;
            final key = _makeKey(ip, port);
            loaded[key] = ConnectionState(
              status: ConnectionStatus.disconnected,
              serverIp: ip,
              serverPort: port,
            );
          }
        }
      }

      state = state.copyWith(
        connections: loaded,
        savedServerIp: savedIp,
        savedServerPort: savedPort,
      );
    } catch (_) {}
  }

  Future<void> _saveServers() async {
    try {
      final box = await Hive.openBox(_boxName);
      final list = state.connections.values
          .map((e) => {'ip': e.serverIp, 'port': e.serverPort})
          .toList();
      await box.put(_serversKey, list);
    } catch (_) {}
  }

  Future<void> _saveLastConfig(String ip, int port) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_savedIpKey, ip);
      await box.put(_savedPortKey, port);
      state = state.copyWith(savedServerIp: ip, savedServerPort: port);
    } catch (_) {}
  }

  String get savedServerIp => state.savedServerIp;
  int get savedServerPort => state.savedServerPort;

  Future<void> addServer(String ipOrIpPort) async {
    final (ip, port) = _parseIpPort(ipOrIpPort);
    if (ip.isEmpty) return;

    final key = _makeKey(ip, port);
    if (state.connections.containsKey(key)) {
      await _saveLastConfig(ip, port);
      return;
    }

    final next = Map<String, ConnectionState>.from(state.connections);
    next[key] = ConnectionState(
      status: ConnectionStatus.disconnected,
      serverIp: ip,
      serverPort: port,
    );

    state = state.copyWith(connections: next);
    await _saveServers();
    await _saveLastConfig(ip, port);
  }

  Future<void> removeServer(String key) async {
    await disconnect(key);
    final next = Map<String, ConnectionState>.from(state.connections);
    next.remove(key);
    state = state.copyWith(connections: next);
    await _saveServers();
  }

  Future<bool> connect(String key) async {
    final conn = state.connections[key];
    if (conn == null) return false;

    await disconnect(key);

    final service = TcpClientService();
    _services[key] = service;

    service.onStateChanged.listen((newState) {
      final current = state.connections[key];
      if (current == null) return;
      final next = Map<String, ConnectionState>.from(state.connections);
      next[key] = newState;
      state = state.copyWith(connections: next);

      if (newState.status == ConnectionStatus.authenticated) {
        _startHeartbeat(key);
      } else if (newState.status == ConnectionStatus.disconnected ||
          newState.status == ConnectionStatus.error) {
        _stopHeartbeat(key);
      }
    });

    final success = await service.connect(conn.serverIp, port: conn.serverPort);
    if (success) {
      await _saveLastConfig(conn.serverIp, conn.serverPort);
    }
    return success;
  }

  Future<void> disconnect(String key) async {
    _stopHeartbeat(key);
    final service = _services.remove(key);
    if (service != null) {
      await service.disconnect();
      service.dispose();
    }

    final current = state.connections[key];
    if (current == null) return;

    final next = Map<String, ConnectionState>.from(state.connections);
    next[key] = ConnectionState(
      status: ConnectionStatus.disconnected,
      serverIp: current.serverIp,
      serverPort: current.serverPort,
      serverName: current.serverName,
    );
    state = state.copyWith(connections: next);
  }

  Future<bool> login(String key, String username, String privateKeyHex) async {
    var service = _services[key];
    // 如果未连接，先自动连接
    if (service == null || !service.state.isConnected) {
      final connected = await connect(key);
      if (!connected) return false;
      service = _services[key];
    }
    if (service == null || !service.state.isConnected) {
      return false;
    }
    return await service.login(username, privateKeyHex);
  }

  Future<void> connectMultiple(List<String> keys) async {
    await Future.wait(keys.map((k) => connect(k)));
  }

  Future<void> disconnectMultiple(List<String> keys) async {
    await Future.wait(keys.map((k) => disconnect(k)));
  }

  Future<void> loginMultiple(
    List<String> keys,
    String username,
    String privateKeyHex,
  ) async {
    // login 方法现在会自动连接，所以直接调用即可
    await Future.wait(keys.map((k) => login(k, username, privateKeyHex)));
  }

  void sendHeartbeat(String key) {
    _services[key]?.sendHeartbeat();
  }

  /// 刷新所有已连接服务器的信息（连接数、房间数等）
  void refreshAllServerInfo() {
    for (final service in _services.values) {
      if (service.state.isConnected) {
        service.requestServerInfo();
      }
    }
  }

  /// 获取已登录的服务器列表
  List<MapEntry<String, ConnectionState>> get authenticatedServers {
    return state.connections.entries
        .where((e) => e.value.status == ConnectionStatus.authenticated)
        .toList();
  }

  /// 创建房间
  Future<CreateRoomResponse?> createRoom({
    required String serverKey,
    required int roomTypeCode,
    required String roomName,
    required int maxPlayers,
  }) async {
    final service = _services[serverKey];
    if (service == null || !service.state.isConnected) return null;
    final resp = await service.createRoom(
      roomTypeCode: roomTypeCode,
      roomName: roomName,
      maxPlayers: maxPlayers,
    );
    if (resp != null && resp.success && resp.roomId != null) {
      state = state.copyWith(
        currentRoomId: resp.roomId,
        currentRoomServerKey: serverKey,
        chatMessages: [],
      );
      _listenRoomEvents(serverKey);
      // 创建成功后立即刷新房间列表，确保本地有 RoomInfo（包含 ownerName）
      await refreshRoomList();
    }
    return resp;
  }

  /// 刷新房间列表（从所有已认证的服务器获取）
  Future<void> refreshRoomList() async {
    final allRooms = <RoomInfo>[];
    for (final entry in authenticatedServers) {
      final serverKey = entry.key;
      final service = _services[serverKey];
      if (service == null) continue;
      final resp = await service.requestRoomList();
      if (resp != null) {
        // 给每个房间设置 serverKey
        for (final room in resp.rooms) {
          allRooms.add(
            RoomInfo(
              roomId: room.roomId,
              roomName: room.roomName,
              roomTypeCode: room.roomTypeCode,
              currentPlayers: room.currentPlayers,
              maxPlayers: room.maxPlayers,
              ownerName: room.ownerName,
              serverKey: serverKey,
              rounds: room.rounds,
              roundTime: room.roundTime,
              lexiconKey: room.lexiconKey,
              isGameActive: room.isGameActive,
            ),
          );
        }
      }
    }
    state = state.copyWith(rooms: allRooms);
  }

  /// 加入房间
  Future<JoinRoomResponse?> joinRoom(String serverKey, String roomId) async {
    final service = _services[serverKey];
    if (service == null || !service.state.isConnected) return null;
    final resp = await service.joinRoom(roomId);
    if (resp != null && resp.success) {
      state = state.copyWith(
        currentRoomId: roomId,
        currentRoomServerKey: serverKey,
        chatMessages: [],
      );
      _listenRoomEvents(serverKey);
      // 加入成功后立即请求一次成员列表
      service.requestRoomMembers(roomId);
      // 请求当前房间词库数据
      service.requestLexicon();
    }
    return resp;
  }

  /// 离开房间
  Future<void> leaveRoom() async {
    final roomId = state.currentRoomId;
    final serverKey = state.currentRoomServerKey;
    if (roomId == null || serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      await service.leaveRoom(roomId);
    }
    _memberSubscriptions[serverKey]?.cancel();
    _memberSubscriptions.remove(serverKey);
    state = state.copyWith(clearCurrentRoom: true, roomMembers: []);
  }

  /// 断线重连当前房间（仅限本局成员）
  Future<bool> reconnectCurrentRoom() async {
    final roomId = state.currentRoomId;
    final serverKey = state.currentRoomServerKey;
    if (roomId == null || serverKey == null) return false;
    final service = _services[serverKey];
    if (service == null || !service.state.isConnected) return false;

    final resp = await service.reconnectRoom(roomId);
    if (resp == null || !resp.success) return false;

    // 重连成功后加速同步（服务端会补发关键广播，这里再主动请求一遍避免丢包/时序差）
    service.requestRoomMembers(roomId);
    service.requestLexicon();
    return true;
  }

  /// 刷新房间成员
  void refreshRoomMembers() {
    final roomId = state.currentRoomId;
    final serverKey = state.currentRoomServerKey;
    if (roomId == null || serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.requestRoomMembers(roomId);
    }
  }

  /// 发送聊天消息
  void sendChatMessage(String content) {
    final roomId = state.currentRoomId;
    final serverKey = state.currentRoomServerKey;
    if (roomId == null || serverKey == null || content.trim().isEmpty) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendChatMessage(roomId, content);
    }
  }

  /// 发送准备/取消准备请求
  void sendReadyRequest(bool isReady) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendReadyRequest(isReady);
    }
  }

  /// 上传词库数据到服务器
  void uploadLexicon(String lexiconJson) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.uploadLexicon(lexiconJson);
    }
  }

  /// 请求当前房间词库数据
  void requestLexicon() {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.requestLexicon();
    }
  }

  /// 发送游戏开始请求（房主发起）
  void sendGameStart(List<int> cardIndices) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendGameStart(cardIndices);
    }
  }

  /// 发送卡牌选择请求
  void sendCardPick(int cardIndex) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendCardPick(cardIndex);
    }
  }

  /// 重置游戏状态
  void resetGame() {
    state = state.copyWith(clearGame: true);
  }

  /// 更新房间设置
  Future<bool> updateRoom({
    required String roomName,
    required int roomTypeCode,
    required int maxPlayers,
    int rounds = 5,
    int roundTime = 60,
    String lexiconKey = '',
    int canvasWidth = 1280,
    int canvasHeight = 720,
  }) async {
    final roomId = state.currentRoomId;
    final serverKey = state.currentRoomServerKey;
    if (roomId == null || serverKey == null) return false;
    final service = _services[serverKey];
    if (service == null) return false;

    final resp = await service.updateRoom(
      roomId: roomId,
      roomName: roomName,
      roomTypeCode: roomTypeCode,
      maxPlayers: maxPlayers,
      rounds: rounds,
      roundTime: roundTime,
      lexiconKey: lexiconKey,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
    );

    if (resp != null && resp.success) {
      // 检测变更内容
      final oldRoom = state.rooms.firstWhere(
        (r) => r.roomId.toLowerCase() == roomId.toLowerCase(),
        orElse: () => RoomInfo(
          roomId: '',
          roomName: '',
          roomTypeCode: 0,
          currentPlayers: 0,
          maxPlayers: 0,
          ownerName: '',
          serverKey: '',
        ),
      );
      if (oldRoom.roomId.isNotEmpty) {
        if (roomName != oldRoom.roomName) {
          _pendingChanges['roomName'] = '房间名称 → 【$roomName】';
        }
        if (maxPlayers != oldRoom.maxPlayers) {
          _pendingChanges['maxPlayers'] = '人数上限 → 【$maxPlayers 人】';
        }
        if (rounds != oldRoom.rounds) {
          _pendingChanges['rounds'] = '回合数 → 【$rounds 回合】';
        }
        if (roundTime != oldRoom.roundTime) {
          _pendingChanges['roundTime'] = '每回合时间 → 【$roundTime 秒】';
        }
        if (lexiconKey != oldRoom.lexiconKey) {
          _pendingChanges['lexiconKey'] = '词库 → 【已更改】';
        }
      }

      // 刷新房间列表
      await refreshRoomList();

      // 防抖2秒：停止修改后一次性发送最终变更
      _settingChangeTimer?.cancel();
      _settingChangeTimer = Timer(const Duration(seconds: 2), () {
        if (_pendingChanges.isNotEmpty) {
          final lines = _pendingChanges.values.map((v) => '  · $v').join('\n');
          sendChatMessage('房主修改了房间设置：\n$lines');
          _pendingChanges.clear();
        }
      });

      return true;
    }
    return false;
  }

  /// 转让房间
  Future<bool> transferRoom({
    required String newOwnerUsername,
    required String newOwnerFingerprintHex,
  }) async {
    final roomId = state.currentRoomId;
    final serverKey = state.currentRoomServerKey;
    if (roomId == null || serverKey == null) return false;
    final service = _services[serverKey];
    if (service == null) return false;

    final resp = await service.transferRoom(
      roomId: roomId,
      newOwnerUsername: newOwnerUsername,
      newOwnerFingerprintHex: newOwnerFingerprintHex,
    );
    return resp?.success ?? false;
  }

  /// 监听房间消息
  void _listenRoomEvents(String serverKey) {
    _memberSubscriptions[serverKey]?.cancel();
    final service = _services[serverKey];
    if (service == null) return;

    _memberSubscriptions[serverKey] = service.onMessage.listen((msg) {
      final typeCode = msg.$1;
      final payload = msg.$2;

      if (typeCode == MessageType.roomMemberUpdate.code) {
        final update = RoomMemberUpdate.decode(payload);
        if (update.roomId == state.currentRoomId) {
          state = state.copyWith(roomMembers: update.members);
        }
      } else if (typeCode == MessageType.chatMessage.code) {
        final chat = ChatMessage.decode(payload);
        if (chat.roomId == state.currentRoomId) {
          state = state.copyWith(chatMessages: [...state.chatMessages, chat]);
        }
      } else if (typeCode == MessageType.roomOwnerTransfer.code) {
        // 处理房间转让通知
        RoomOwnerTransfer.decode(payload);
        // roomId保持不变，将其视为“房主变更通知”，只需刷新房间列表更新owner信息
        refreshRoomList();
      } else if (typeCode == MessageType.roomSettingUpdate.code) {
        // 处理房间设置更新广播
        final update = RoomSettingUpdate.decode(payload);
        // 不区分大小写比较
        if (update.roomId.toLowerCase() ==
            (state.currentRoomId ?? '').toLowerCase()) {
          // 同步画布尺寸到 LayerNotifier，并触发一次协同同步
          final layerNotifier = ref.read(layerProvider.notifier);
          layerNotifier.setCanvasSize(update.canvasWidth, update.canvasHeight);
          layerNotifier.forceCollabNeedSync();
          _triggerCollabSync(serverKey);

          // 立即更新本地房间列表，避免异步延迟导致UI读取旧数据
          final updatedRooms = state.rooms.map((room) {
            if (room.roomId.toLowerCase() == update.roomId.toLowerCase()) {
              return room.copyWith(
                roomName: update.roomName,
                roomTypeCode: update.roomTypeCode,
                maxPlayers: update.maxPlayers,
                rounds: update.rounds,
                roundTime: update.roundTime,
                lexiconKey: update.lexiconKey,
              );
            }
            return room;
          }).toList();
          state = state.copyWith(rooms: updatedRooms);

          // 异步刷新完整列表（更新其他房间信息）
          refreshRoomList();
        }
      } else if (typeCode == MessageType.collabDeltaBroadcast.code) {
        try {
          final delta = CollabDeltaBroadcast.decode(payload);
          final myName = ref.read(authProvider).username;
          if (myName.isNotEmpty && delta.senderId == myName) {
            return;
          }
          final layerNotifier = ref.read(layerProvider.notifier);
          final ok = layerNotifier.applyCollabDeltaBroadcast(
            epoch: delta.epoch,
            rev: delta.rev,
            x: delta.x,
            y: delta.y,
            width: delta.width,
            height: delta.height,
            flags: delta.flags,
            payload: delta.payload,
          );
          ok.then((applied) {
            if (!applied) {
              _triggerCollabSync(serverKey);
            }
          });
        } catch (_) {}
      } else if (typeCode == MessageType.collabSyncRequired.code) {
        try {
          CollabSyncRequired.decode(payload);
        } catch (_) {}
        _triggerCollabSync(serverKey);
      } else if (typeCode == MessageType.collabSnapshotFromServer.code) {
        try {
          final snap = CollabSnapshotFromServer.decode(payload);
          final layerNotifier = ref.read(layerProvider.notifier);
          layerNotifier.applyCollabSnapshotFromServer(
            epoch: snap.epoch,
            rev: snap.rev,
            width: snap.width,
            height: snap.height,
            flags: snap.flags,
            rgbaZlib: snap.rgbaZlib,
          );
        } catch (_) {}
      } else if (typeCode == MessageType.collabLayerOpBroadcast.code) {
        // 多图层：图层操作广播
        try {
          final op = CollabLayerOpBroadcast.decode(payload);
          final layerNotifier = ref.read(layerProvider.notifier);
          final artworkNotifier = ref.read(artworkProvider.notifier);
          layerNotifier.applyCollabLayerOp(op.opType, op.payload);
          artworkNotifier.applyCollabLayerOp(op.opType, op.payload);
        } catch (_) {}
      } else if (typeCode == MessageType.collabLayerDeltaBroadcast.code) {
        // 多图层：带 layerId 的 delta 广播
        try {
          final delta = CollabLayerDeltaBroadcast.decode(payload);
          final myName = ref.read(authProvider).username;
          if (myName.isNotEmpty && delta.senderId == myName) {
            return;
          }
          final layerNotifier = ref.read(layerProvider.notifier);
          final ok = layerNotifier.applyCollabLayerDeltaBroadcast(
            layerId: delta.layerId,
            epoch: delta.epoch,
            rev: delta.rev,
            x: delta.x,
            y: delta.y,
            width: delta.width,
            height: delta.height,
            flags: delta.flags,
            payload: delta.payload,
          );
          ok.then((applied) {
            if (!applied) {
              _triggerCollabSync(serverKey);
            }
          });
        } catch (_) {}
      } else if (typeCode == MessageType.collabMultiLayerSnapshot.code) {
        // 多图层：完整快照（断线重连/首次同步）
        try {
          final snap = CollabMultiLayerSnapshot.decode(payload);
          final layerNotifier = ref.read(layerProvider.notifier);
          final artworkNotifier = ref.read(artworkProvider.notifier);
          layerNotifier.applyCollabMultiLayerSnapshot(snap);
          artworkNotifier.applyCollabMultiLayerSnapshot(snap);
        } catch (_) {}
      } else if (typeCode == MessageType.lexiconData.code) {
        // 接收词库数据广播
        final lexiconJson = utf8.decode(payload);
        state = state.copyWith(roomLexiconJson: lexiconJson);
      } else if (typeCode == MessageType.gameStartBroadcast.code) {
        // 接收游戏开始广播
        try {
          final jsonStr = utf8.decode(payload);
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final indices = (map['cardIndices'] as List<dynamic>).cast<int>();
          state = state.copyWith(
            isGameActive: true,
            gameCardIndices: indices,
            cardPicks: {},
          );
        } catch (_) {}
      } else if (typeCode == MessageType.cardPickBroadcast.code) {
        // 接收卡牌选择广播
        try {
          final pick = CardPickBroadcast.decode(payload);
          final newPicks = Map<int, CardPickBroadcast>.from(state.cardPicks);
          newPicks[pick.cardIndex] = pick;
          state = state.copyWith(cardPicks: newPicks);
        } catch (_) {}
      } else if (typeCode == MessageType.wordPickPhaseBroadcast.code) {
        // 接收词条翻牌阶段广播
        try {
          final broadcast = WordPickPhaseBroadcast.decode(payload);
          state = state.copyWith(
            isGameActive: true,
            gamePhase: GamePhase.wordPicking,
            currentRound: broadcast.round,
            totalRounds: broadcast.totalRounds,
            wordPickTime: broadcast.wordPickTime,
            wordCardCount: broadcast.cardCount,
            wordExcludeCardIndex: broadcast.excludeCardIndex,
            wordCardOwnerNames: broadcast.ownerNames,
            clearWordPick: true,
          );
        } catch (_) {}
      } else if (typeCode == MessageType.wordPickBroadcast.code) {
        // 接收词条翻牌选择广播
        try {
          final pick = CardPickBroadcast.decode(payload);
          final newPicks = Map<int, CardPickBroadcast>.from(
            state.wordCardPicks,
          );
          newPicks[pick.cardIndex] = pick;
          state = state.copyWith(wordCardPicks: newPicks);
        } catch (_) {}
      } else if (typeCode == MessageType.wordPickResult.code) {
        // 接收词条翻牌结果（我抽到的词条）
        try {
          final result = WordPickResult.decode(payload);
          state = state.copyWith(myPickedWord: result.word);
        } catch (_) {}
      } else if (typeCode == MessageType.drawingPhaseBroadcast.code) {
        // 接收作画阶段广播
        try {
          final broadcast = DrawingPhaseBroadcast.decode(payload);
          state = state.copyWith(
            isGameActive: true,
            gamePhase: GamePhase.drawing,
            currentRound: broadcast.round,
            totalRounds: broadcast.totalRounds,
            drawTime: broadcast.drawTime,
            drawingWord: broadcast.word,
            // 清空上一轮的猜测相关数据
            guessCards: [],
            cardPicks: {},
            clearDrawingImage: true,
            clearPickedCard: true,
            guessResultsMap: {},
          );
        } catch (_) {}
      } else if (typeCode == MessageType.guessPhaseBroadcast.code) {
        // 接收猜测阶段广播
        try {
          final broadcast = GuessPhaseBroadcast.decode(payload);
          state = state.copyWith(
            isGameActive: true,
            gamePhase: GamePhase.cardPicking,
            guessTime: broadcast.guessTime,
            cardPickTime: broadcast.cardPickTime,
            guessCards: broadcast.cards,
            cardPicks: {},
            clearDrawingImage: true,
            clearPickedCard: true,
            guessResultsMap: {},
          );
        } catch (_) {}
      } else if (typeCode == MessageType.drawingImageData.code) {
        // 接收绘画PNG数据
        try {
          final imgData = DrawingImageData.decode(payload);
          state = state.copyWith(
            receivedDrawingPng: imgData.pngData,
            receivedDrawingAuthor: imgData.username,
            receivedDrawingFp: imgData.fingerprintHex,
            isGameActive: true,
            gamePhase: GamePhase.guessing,
          );
        } catch (_) {}
      } else if (typeCode == MessageType.guessResultBroadcast.code) {
        // 接收猜测结果广播
        try {
          final result = GuessResultBroadcast.decode(payload);
          final newMap = Map<String, String>.from(state.guessResultsMap);
          newMap[result.fingerprintHex] = result.guess;
          state = state.copyWith(guessResultsMap: newMap);
        } catch (_) {}
      } else if (typeCode == MessageType.roundResultBroadcast.code) {
        // 接收回合结果广播
        try {
          final result = RoundResultBroadcast.decode(payload);
          state = state.copyWith(
            isGameActive: true,
            gamePhase: GamePhase.roundResult,
            roundResults: result.results,
          );
        } catch (_) {}
      } else if (typeCode == MessageType.replayFileBroadcast.code) {
        // 接收复盘文件广播
        try {
          final replay = ReplayFileBroadcast.decode(payload).replay;
          state = state.copyWith(replayData: replay);

          // 立即回执，告知服务端已收到复盘文件
          final serverKey = state.currentRoomServerKey;
          if (serverKey != null) {
            final service = _services[serverKey];
            final replayId = replay['replayId']?.toString() ?? '';
            if (service != null && replayId.isNotEmpty) {
              service.sendReplayAck(replayId);
            }
          }

          final tracksRaw = replay['tracks'];
          if (tracksRaw is List) {
            final tracks = tracksRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false);
            if (tracks.isNotEmpty) {
              final authNotifier = ref.read(authProvider.notifier);
              authNotifier.saveReplay(tracks);
            }
          }
        } catch (_) {}
      } else if (typeCode == MessageType.reviewPhaseBroadcast.code) {
        // 接收进入复盘阶段广播
        state = state.copyWith(
          isGameActive: true,
          gamePhase: GamePhase.reviewing,
          isVoting: false,
          voteBarrages: [],
          canPickFavorite: false,
          favoritePickerUsername: '',
          clearFavoriteChosenIndex: true,
          reviewPathIndex: 0,
          reviewStepIndex: 0,
        );
      } else if (typeCode == MessageType.reviewProgressBroadcast.code) {
        // 接收复盘进度广播（服务端驱动）
        try {
          final progress = ReviewProgressBroadcast.decode(payload);
          final pathChanged = progress.pathIndex != state.reviewPathIndex;
          state = state.copyWith(
            reviewPathIndex: progress.pathIndex,
            reviewStepIndex: progress.stepIndex,
            clearFavoriteChosenIndex: pathChanged,
          );
        } catch (_) {}
      } else if (typeCode == MessageType.voteStartBroadcast.code) {
        // 接收投票开始广播
        state = state.copyWith(isVoting: true, voteBarrages: []);
      } else if (typeCode == MessageType.voteResultBroadcast.code) {
        // 接收投票结果广播（弹幕）
        try {
          final result = VoteResultBroadcast.decode(payload);
          state = state.copyWith(
            voteBarrages: [
              ...state.voteBarrages,
              {'username': result.username, 'isUp': result.isUp},
            ],
          );
        } catch (_) {}
      } else if (typeCode == MessageType.favoriteSelectionStart.code) {
        // 接收最爱画作选择开始（全员同步，但只有picker可点）
        _favoriteCloseToken++;
        final token = _favoriteCloseToken;
        try {
          final start = FavoriteSelectionStartBroadcast.decode(payload);
          state = state.copyWith(
            isVoting: false,
            canPickFavorite: true,
            favoritePickerUsername: start.pickerUsername,
            clearFavoriteChosenIndex: true,
          );
        } catch (_) {
          state = state.copyWith(isVoting: false, canPickFavorite: true);
        }

        Future.delayed(const Duration(seconds: 16), () {
          if (!mounted) return;
          if (_favoriteCloseToken != token) return;
          if (!state.canPickFavorite) return;
          state = state.copyWith(canPickFavorite: false);
        });
      } else if (typeCode == MessageType.favoriteResultBroadcast.code) {
        // 接收最爱画作结果（用于描边展示几秒）
        try {
          final result = FavoriteResultBroadcast.decode(payload);
          _favoriteCloseToken++;
          if (result.drawingIndex == 255) {
            state = state.copyWith(
              canPickFavorite: false,
              clearFavoriteChosenIndex: true,
            );
          } else {
            state = state.copyWith(
              canPickFavorite: false,
              favoriteChosenIndex: result.drawingIndex,
            );
          }
        } catch (_) {}
      } else if (typeCode == MessageType.scoreUpdateBroadcast.code) {
        // 接收积分更新广播
        try {
          final update = ScoreUpdateBroadcast.decode(payload);
          state = state.copyWith(isVoting: false, memberScores: update.scores);
        } catch (_) {}
      } else if (typeCode == MessageType.gameEndBroadcast.code) {
        // 接收游戏结束广播
        try {
          final result = GameEndBroadcast.decode(payload);
          state = state.copyWith(
            gamePhase: GamePhase.ended,
            allGameResults: result.allResults,
            isGameActive: false,
          );
        } catch (e) {
          print('解析游戏结束广播失败: $e');
        }
      } else if (typeCode == MessageType.scorePodiumBroadcast.code) {
        try {
          final podium = ScorePodiumBroadcast.decode(payload);
          state = state.copyWith(
            showPodium: true,
            podiumEndAtMs: podium.endAtMs,
            podiumTop3: podium.top3,
          );
        } catch (_) {}
      } else if (typeCode == MessageType.gameResetBroadcast.code) {
        try {
          GameResetBroadcast.decode(payload);
        } catch (_) {}
        final clearedMembers = state.roomMembers
            .map(
              (m) => RoomMember(
                username: m.username,
                fingerprintHex: m.fingerprintHex,
                isReady: false,
              ),
            )
            .toList(growable: false);
        state = state.copyWith(
          clearGame: true,
          showPodium: false,
          podiumEndAtMs: 0,
          podiumTop3: const [],
          clearFavoriteChosenIndex: true,
          gamePhase: GamePhase.idle,
          reviewPathIndex: 0,
          reviewStepIndex: 0,
          roomMembers: clearedMembers,
        );
      }
    });
  }

  void sendCollabDeltaStep(UndoRegionDeltaStep step) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service == null) return;

    final layerNotifier = ref.read(layerProvider.notifier);
    final flags = step.isCompressed ? 0x01 : 0x00;
    service.sendCollabDelta(
      CollabDeltaRequest(
        epoch: layerNotifier.collabEpoch,
        baseRev: layerNotifier.collabRev,
        x: step.x,
        y: step.y,
        width: step.width,
        height: step.height,
        flags: flags,
        payload: Uint8List.fromList(step.delta),
      ),
    );
    layerNotifier.advanceCollabRevOnLocalDelta();
  }

  /// 协同多图层：发送图层操作请求（增删改重排）
  void sendCollabLayerOp(
    CollabLayerOpType opType,
    Map<String, dynamic> payload,
  ) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service == null) return;
    service.sendCollabLayerOp(
      CollabLayerOpRequest(opType: opType, payload: payload),
    );
  }

  /// 协同多图层：发送带 layerId 的增量 delta
  void sendCollabLayerDeltaStep(String layerId, UndoRegionDeltaStep step) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service == null) return;

    final layerNotifier = ref.read(layerProvider.notifier);
    final flags = step.isCompressed ? 0x01 : 0x00;
    final layerRev = layerNotifier.getLayerRevision(layerId);
    service.sendCollabLayerDelta(
      CollabLayerDeltaRequest(
        layerId: layerId,
        epoch: layerNotifier.collabEpoch,
        baseRev: layerRev,
        x: step.x,
        y: step.y,
        width: step.width,
        height: step.height,
        flags: flags,
        payload: Uint8List.fromList(step.delta),
      ),
    );
    layerNotifier.advanceLayerRevOnLocalDelta(layerId);
  }

  /// 协同模式撤回：本地 undoDelta 后把同一 delta 再发服务端（XOR 自逆）
  Future<void> collabUndoDelta() async {
    final layerNotifier = ref.read(layerProvider.notifier);
    final step = await layerNotifier.undoDelta();
    if (step == null) return;

    // 非协同房间则不需要通知服务端
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null || !state.isCollabRoom) return;
    final service = _services[serverKey];
    if (service == null) return;

    final layerId = step.layerId;
    if (layerId == null) return;

    // 原始 delta 再发一次 → 服务端 XOR 后像素还原
    final flags = step.isCompressed ? 0x01 : 0x00;
    final layerRev = layerNotifier.getLayerRevision(layerId);
    service.sendCollabLayerDelta(
      CollabLayerDeltaRequest(
        layerId: layerId,
        epoch: layerNotifier.collabEpoch,
        baseRev: layerRev,
        x: step.x,
        y: step.y,
        width: step.width,
        height: step.height,
        flags: flags,
        payload: Uint8List.fromList(step.delta),
      ),
    );
    layerNotifier.advanceLayerRevOnLocalDelta(layerId);
  }

  /// 协同模式重做：本地 redoDelta 后把同一 delta 再发服务端（XOR 自逆）
  Future<void> collabRedoDelta() async {
    final layerNotifier = ref.read(layerProvider.notifier);
    final step = await layerNotifier.redoDelta();
    if (step == null) return;

    final serverKey = state.currentRoomServerKey;
    if (serverKey == null || !state.isCollabRoom) return;
    final service = _services[serverKey];
    if (service == null) return;

    final layerId = step.layerId;
    if (layerId == null) return;

    final flags = step.isCompressed ? 0x01 : 0x00;
    final layerRev = layerNotifier.getLayerRevision(layerId);
    service.sendCollabLayerDelta(
      CollabLayerDeltaRequest(
        layerId: layerId,
        epoch: layerNotifier.collabEpoch,
        baseRev: layerRev,
        x: step.x,
        y: step.y,
        width: step.width,
        height: step.height,
        flags: flags,
        payload: Uint8List.fromList(step.delta),
      ),
    );
    layerNotifier.advanceLayerRevOnLocalDelta(layerId);
  }

  void _triggerCollabSync(String serverKey) {
    final service = _services[serverKey];
    if (service == null) return;
    final username = ref.read(authProvider).username;
    if (username.isEmpty) return;
    final layerNotifier = ref.read(layerProvider.notifier);
    service.sendCollabSyncRequest(
      requesterUsername: username,
      clientEpoch: layerNotifier.collabEpoch,
      clientRev: layerNotifier.collabRev,
    );
  }

  /// 上传绘画PNG数据
  void sendDrawingUpload(Uint8List pngData) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendDrawingUpload(pngData);
    }
  }

  /// 提交投票（勾/叉）
  void sendVoteSubmit(bool isUp) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendVoteSubmit(isUp);
      state = state.copyWith(isVoting: false);
    }
  }

  /// 提交最爱画作
  void sendFavoriteSubmit(int drawingIndex) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendFavoriteSubmit(drawingIndex);
      state = state.copyWith(canPickFavorite: false);
    }
  }

  /// 通知服务端绘画完成
  void sendDrawingComplete() {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendDrawingComplete();
    }
  }

  /// 提交猜测
  void sendGuessSubmit(int cardIndex, String guess) {
    final serverKey = state.currentRoomServerKey;
    if (serverKey == null) return;
    final service = _services[serverKey];
    if (service != null) {
      service.sendGuessSubmit(cardIndex, guess);
    }
  }

  /// 根据房间ID找到对应的服务器key
  String? findServerKeyForRoom(String roomId) {
    for (final entry in authenticatedServers) {
      if (_services.containsKey(entry.key)) return entry.key;
    }
    return null;
  }

  @override
  void dispose() {
    for (final sub in _memberSubscriptions.values) {
      sub.cancel();
    }
    _memberSubscriptions.clear();
    for (final t in _heartbeatTimers.values) {
      t.cancel();
    }
    _heartbeatTimers.clear();
    for (final s in _services.values) {
      s.dispose();
    }
    _services.clear();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionPoolState>(
      (ref) => ConnectionNotifier(ref),
    );
