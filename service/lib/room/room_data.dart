import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/protocol_handler.dart';

/// 游戏阶段枚举
enum GamePhase {
  idle, // 未开始
  wordPicking, // 词条翻牌阶段
  drawing, // 作画阶段
  cardPicking, // 卡牌抽取阶段
  guessing, // 猜测阶段
  roundResult, // 回合结算中
  reviewing, // 复盘结算中
  ended, // 游戏结束
}

/// 复盘子阶段枚举
enum ReviewSubPhase {
  idle,
  showingSteps,
  voting,
  favoriteSelecting,
  advancing,
}

/// 协同图层信息（服务端权威）
class CollabLayerInfo {
  final String layerId;
  String name;
  final String ownerId;
  bool isVisible;
  bool isLocked;
  double opacity; // 0.0-1.0
  int blendMode; // BlendMode.index
  int rev; // 每层独立版本号
  Uint8List rgba; // 该层像素数据

  CollabLayerInfo({
    required this.layerId,
    required this.name,
    required this.ownerId,
    this.isVisible = true,
    this.isLocked = false,
    this.opacity = 1.0,
    this.blendMode = 0,
    this.rev = 0,
    required this.rgba,
  });
}

/// 房间数据
class RoomData {
  String roomId;
  String roomName;
  final RoomType roomType;
  int maxPlayers;
  int rounds = 5;
  int roundTime = 60;
  String lexiconKey = '';
  int canvasWidth = 1280;
  int canvasHeight = 720;
  int collabRev = 0;
  int collabEpoch = 0;
  Uint8List collabRgba = Uint8List(1280 * 720 * 4);

  // ===== 多图层协同状态 =====
  final List<CollabLayerInfo> collabLayers = [];
  int _layerIdCounter = 0;

  /// 服务端生成唯一 layerId
  String generateLayerId() {
    _layerIdCounter++;
    return 'cl_${roomId}_$_layerIdCounter';
  }

  final String creatorUsername;
  final String creatorFingerprintHex;
  String ownerUsername;
  String ownerFingerprintHex;
  String? lexiconJson; // 当前房间词库数据（JSON字符串）
  final List<Socket?> memberSockets = [];
  final List<RoomMember> members = [];

  // ===== 游戏状态 =====
  GamePhase gamePhase = GamePhase.idle;
  int currentRound = 0; // 当前回合（1-based）
  Timer? phaseTimer; // 当前阶段倒计时
  DateTime? phaseEndAt; // 当前阶段预计结束时间（用于管理后台展示剩余时间）

  // ===== 复盘结算状态机（用于避免Timer重叠） =====
  ReviewSubPhase reviewSubPhase = ReviewSubPhase.idle;
  int reviewFlowToken = 0;
  Timer? reviewStepTimer;
  Timer? reviewAdvanceTimer;

  // 每回合分配的绘画词: fingerprintHex -> 词条内容
  Map<String, String> memberDrawWords = {};
  // 每回合上传的绘画PNG: fingerprintHex -> PNG bytes
  Map<String, Uint8List> memberDrawings = {};
  // 已完成绘画的成员集合
  Set<String> drawingCompletedMembers = {};
  // 猜测阶段卡牌列表（打乱后）
  List<GuessCard> guessCards = [];
  // 卡牌选择: cardIndex -> 选择者fingerprintHex
  Map<int, String> guessCardPicks = {};
  // 猜测结果: 猜测者fingerprintHex -> {cardIndex, guess, targetFingerprintHex}
  Map<String, Map<String, dynamic>> guessResults = {};
  Map<String, List<Map<String, dynamic>>> guessSubmitHistory = {};
  // 成员积分: fingerprintHex -> score
  Map<String, int> memberScores = {};
  // 当前复盘的路径索引 (0 to members.length - 1)
  int currentReviewPathIndex = 0;
  // 当前复盘路径下的步骤索引 (0 to members.length - 1)
  int currentReviewStepIndex = 0;
  // 投票状态: fingerprintHex -> bool (true=勾, false=叉)
  Map<String, bool> reviewVotes = {};
  // 上一轮猜测文本（用于下一轮卡牌内容）: 被猜者/作画者FingerprintHex -> 猜测文本
  Map<String, String> lastRoundGuesses = {};
  // 上一轮猜测者（用于排除"抽到自己上一回合的猜测词"）: 被猜者/作画者FingerprintHex -> 猜测者FingerprintHex
  Map<String, String> lastRoundGuessers = {};
  // 所有回合结果（用于最终结算）
  List<Map<String, dynamic>> allRoundResults = [];
  // 词库顺序索引（每回合继续下去，不重复）
  int wordStartIndex = 0;
  // 词条翻牌阶段卡牌列表（打乱后的词条）
  List<String> wordCards = [];
  // 词条卡牌所属者: 与wordCards平行，记录每张卡对应的成员fingerprintHex（round1为空串）
  List<String> wordCardOwnerFps = [];
  // 词条卡牌猜测者: 与wordCards平行，记录该词条是谁在上一回合猜出来的（round1为空串）
  List<String> wordCardGuesserFps = [];
  // 词条翻牌选择: cardIndex -> 选择者fingerprintHex
  Map<int, String> wordCardPicks = {};

  final List<Map<String, dynamic>> roundHistory = [];

  // 最近一次生成的复盘文件（用于管理后台预览）
  Map<String, dynamic>? lastReplayFile;

  // ===== 复盘ACK门禁 =====
  Set<String> replayAckedFps = {};
  Timer? replayAckTimer;

  RoomData({
    required this.roomId,
    required this.roomName,
    required this.roomType,
    required this.maxPlayers,
    required this.creatorUsername,
    required this.creatorFingerprintHex,
    required this.ownerUsername,
    required this.ownerFingerprintHex,
  }) {
    canvasWidth = 1280;
    canvasHeight = 720;
    collabRgba = Uint8List(canvasWidth * canvasHeight * 4);

    // 协同房间初始化默认图层由 handleCreateRoom 负责（携带用户名）
  }

  int get onlineCount => memberSockets.where((s) => s != null).length;

  /// 重置游戏状态
  void resetGame() {
    phaseTimer?.cancel();
    reviewStepTimer?.cancel();
    reviewAdvanceTimer?.cancel();
    replayAckTimer?.cancel();
    phaseEndAt = null;
    gamePhase = GamePhase.idle;
    currentRound = 0;
    memberDrawWords.clear();
    memberDrawings.clear();
    drawingCompletedMembers.clear();
    guessCards.clear();
    guessCardPicks.clear();
    guessResults.clear();
    guessSubmitHistory.clear();
    lastRoundGuesses.clear();
    lastRoundGuessers.clear();
    allRoundResults.clear();
    wordStartIndex = 0;
    roundHistory.clear();
    memberScores.clear();
    currentReviewPathIndex = 0;
    currentReviewStepIndex = 0;
    reviewVotes.clear();
    reviewSubPhase = ReviewSubPhase.idle;
    reviewFlowToken = 0;
    replayAckedFps.clear();
  }

  /// 重置回合数据（进入新回合时调用）
  void resetRoundData() {
    memberDrawWords.clear();
    memberDrawings.clear();
    drawingCompletedMembers.clear();
    guessCards.clear();
    guessCardPicks.clear();
    guessResults.clear();
    guessSubmitHistory.clear();
    wordCards.clear();
    wordCardOwnerFps.clear();
    wordCardGuesserFps.clear();
    wordCardPicks.clear();
  }
}
