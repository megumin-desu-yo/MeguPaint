import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/protocol_handler.dart';
import 'room_data.dart';
import 'room_broadcaster.dart';

/// 日志回调类型
typedef LogCallback = void Function(
  String message, {
  String? room,
  String? username,
  String? fingerprintHex,
  String? ip,
  String? action,
  String? content,
});

/// 回调类型定义
typedef VoidCallback = void Function();
typedef RoomCallback = void Function(RoomData room);
typedef GenerateReplayCallback = void Function(RoomData room);

/// 接力游戏引擎
/// 负责游戏主流程：wordPicking → drawing → cardPicking → guessing → roundResult
class RelayGameEngine {
  final LogCallback _log;
  final Random _random = Random();

  /// 最小有效 1x1 白色 PNG（67字节）
  static final Uint8List emptyPng = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, // 8bit RGB
    0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
    0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, // compressed data
    0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, // white pixel
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk
    0xAE, 0x42, 0x60, 0x82,
  ]);

  RelayGameEngine({required LogCallback log}) : _log = log;

  /// 启动下一回合
  void startNextRound(RoomData room, RoomCallback startWordPickPhase) {
    room.currentRound++;
    room.resetRoundData();

    if (room.currentRound > room.rounds) {
      // 所有回合结束，进入结算 - 由外部处理
      return;
    }

    _log('开始第 ${room.currentRound}/${room.rounds} 回合',
        room: room.roomId, action: 'ROUND_START');

    startWordPickPhase(room);
  }

  /// 启动词条翻牌阶段
  void startWordPickPhase(RoomData room) {
    room.gamePhase = GamePhase.wordPicking;
    room.wordCards.clear();
    room.wordCardOwnerFps.clear();
    room.wordCardPicks.clear();

    // 构建词条卡牌 + 所属者列表
    final shuffledMembers = List.of(room.members);
    shuffledMembers.shuffle(_random);

    List<String> ownerFps =
        shuffledMembers.map((m) => m.fingerprintHex).toList();
    List<String> words = [];

    if (room.currentRound == 1) {
      // 第一回合：从词库随机抽取
      words = _buildFirstRoundWords(room, shuffledMembers);
    } else {
      // 后续回合：使用上一轮的猜测文本作为词条
      words = _buildSubsequentRoundWords(room, shuffledMembers);
    }

    room.wordCards = words;
    room.wordCardOwnerFps = ownerFps;
    room.wordCardGuesserFps = room.currentRound == 1
        ? List<String>.filled(room.wordCards.length, '', growable: true)
        : room.wordCardOwnerFps
            .map((ownerFp) => room.lastRoundGuessers[ownerFp] ?? '')
            .toList(growable: true);

    _broadcastWordPickPhase(room);
    _startWordPickTimer(room);
  }

  /// 构建第一回合词条
  List<String> _buildFirstRoundWords(
      RoomData room, List<RoomMember> shuffledMembers) {
    List<String> allWords = [];
    if (room.lexiconJson != null && room.lexiconJson!.isNotEmpty) {
      try {
        final map = jsonDecode(room.lexiconJson!) as Map<String, dynamic>;
        final items = (map['items'] as List<dynamic>?) ?? [];
        allWords = items
            .map((item) {
              if (item is Map<String, dynamic>) {
                return item['content']?.toString() ?? '';
              }
              return item.toString();
            })
            .where((w) => w.isNotEmpty)
            .toList();
      } catch (e) {
        _log('解析词库失败: $e', action: 'WORD_PICK_ERROR');
      }
    }
    if (allWords.isNotEmpty) {
      final shuffledWords = List<String>.from(allWords);
      shuffledWords.shuffle(_random);
      return List.generate(
        shuffledMembers.length,
        (i) => shuffledWords[i % shuffledWords.length],
      );
    }
    return List.filled(shuffledMembers.length, '默认词条');
  }

  /// 构建后续回合词条（使用上一轮猜测）
  List<String> _buildSubsequentRoundWords(
      RoomData room, List<RoomMember> shuffledMembers) {
    _log('lastRoundGuesses 内容:', room: room.roomId, action: 'WORD_PICK_DEBUG');
    for (final entry in room.lastRoundGuesses.entries) {
      _log('  ${entry.key}: "${entry.value}"',
          room: room.roomId, action: 'WORD_PICK_DEBUG');
    }
    return shuffledMembers
        .map((member) => room.lastRoundGuesses[member.fingerprintHex] ?? '未猜测')
        .toList();
  }

  /// 广播词条翻牌阶段
  void _broadcastWordPickPhase(RoomData room) {
    final fpToName = {
      for (final m in room.members) m.fingerprintHex: m.username
    };
    final ownerNames = room.wordCardOwnerFps
        .map((fp) => fpToName[fp] ?? '未知')
        .toList(growable: false);

    for (int i = 0; i < room.members.length; i++) {
      final member = room.members[i];
      final socket = room.memberSockets[i];
      if (socket == null) continue;

      final excludeIdx = room.currentRound == 1
          ? -1
          : (room.wordCardGuesserFps.indexOf(member.fingerprintHex) >= 0
              ? room.wordCardGuesserFps.indexOf(member.fingerprintHex)
              : room.wordCardOwnerFps.indexOf(member.fingerprintHex));

      final broadcast = WordPickPhaseBroadcast(
        round: room.currentRound,
        totalRounds: room.rounds,
        wordPickTime: 10,
        cardCount: room.wordCards.length,
        excludeCardIndex: excludeIdx,
        ownerNames: ownerNames,
      );
      try {
        socket.add(ProtocolHandler.encode(
            MessageType.wordPickPhaseBroadcast, broadcast.encode()));
      } catch (_) {}
    }
  }

  /// 启动词条翻牌计时器
  void _startWordPickTimer(RoomData room) {
    _log('词条翻牌阶段开始（${room.wordCards.length}张卡牌，10秒）',
        room: room.roomId, action: 'WORD_PICK_PHASE');

    room.phaseTimer?.cancel();
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 10));
    room.phaseTimer = Timer(const Duration(seconds: 10), () {
      onWordPickTimeEnd(room, delayTransition: true);
    });

    // 3人房自动分配
    if (room.members.length <= 3) {
      Timer(const Duration(milliseconds: 200), () {
        if (room.gamePhase != GamePhase.wordPicking) return;
        if (room.wordCardPicks.isNotEmpty) return;
        onWordPickTimeEnd(room, delayTransition: true);
      });
    }
  }

  /// 词条翻牌时间结束
  void onWordPickTimeEnd(RoomData room, {bool delayTransition = false}) {
    if (room.gamePhase != GamePhase.wordPicking) return;
    room.phaseTimer?.cancel();
    room.phaseEndAt = null;

    _autoAssignUnpickedWordCards(room);

    _log('词条翻牌结束，进入作画阶段', room: room.roomId, action: 'WORD_PICK_END');

    if (delayTransition) {
      room.phaseEndAt = DateTime.now().add(const Duration(seconds: 2));
      room.phaseTimer = Timer(const Duration(seconds: 2), () {
        room.phaseEndAt = null;
        startDrawingPhase(room);
      });
    } else {
      startDrawingPhase(room);
    }
  }

  /// 自动分配未选的词条卡牌
  void _autoAssignUnpickedWordCards(RoomData room) {
    final pickedMembers = room.wordCardPicks.values.toSet();
    final unpickedMembers = room.members
        .where((m) => !pickedMembers.contains(m.fingerprintHex))
        .toList();
    final unpickedCards = List.generate(room.wordCards.length, (i) => i)
        .where((i) => !room.wordCardPicks.containsKey(i))
        .toList();

    if (unpickedMembers.isEmpty || unpickedCards.isEmpty) return;

    List<int> getAvailableCards(String memberFp, List<int> cards) {
      return cards.where((idx) {
        if (idx < room.wordCardOwnerFps.length &&
            room.wordCardOwnerFps[idx] == memberFp) return false;
        if (idx < room.wordCardGuesserFps.length &&
            room.wordCardGuesserFps[idx] == memberFp) return false;
        return true;
      }).toList();
    }

    Map<int, String> assignments = {};
    Set<int> assignedCards = {};

    // 多次尝试随机分配
    bool success = false;
    for (int attempt = 0; attempt < 10 && !success; attempt++) {
      assignments.clear();
      assignedCards.clear();
      success = true;

      final shuffledMembers = List.of(unpickedMembers)..shuffle(_random);

      for (final member in shuffledMembers) {
        final available = getAvailableCards(
          member.fingerprintHex,
          unpickedCards.where((c) => !assignedCards.contains(c)).toList(),
        );
        if (available.isEmpty) {
          success = false;
          break;
        }
        final cardIndex = available[_random.nextInt(available.length)];
        assignments[cardIndex] = member.fingerprintHex;
        assignedCards.add(cardIndex);
      }
    }

    if (!success) {
      _log('词条翻牌自动分配：随机分配失败，使用 fallback',
          room: room.roomId, action: 'WORD_PICK_FALLBACK');
    }

    // Fallback: 贪心算法
    if (assignments.isEmpty) {
      final sortedMembers = List.of(unpickedMembers);
      sortedMembers.sort((a, b) {
        final aAvail = getAvailableCards(
          a.fingerprintHex,
          unpickedCards.where((c) => !assignedCards.contains(c)).toList(),
        ).length;
        final bAvail = getAvailableCards(
          b.fingerprintHex,
          unpickedCards.where((c) => !assignedCards.contains(c)).toList(),
        ).length;
        return aAvail.compareTo(bAvail);
      });

      for (final member in sortedMembers) {
        final available = getAvailableCards(
          member.fingerprintHex,
          unpickedCards.where((c) => !assignedCards.contains(c)).toList(),
        );
        int cardIndex;
        if (available.isNotEmpty) {
          cardIndex = available[_random.nextInt(available.length)];
        } else {
          cardIndex =
              unpickedCards.firstWhere((c) => !assignedCards.contains(c));
          _log('词条翻牌 fallback：成员 ${member.username} 被强制分配冲突卡牌 $cardIndex',
              room: room.roomId, action: 'WORD_PICK_FALLBACK');
        }
        assignments[cardIndex] = member.fingerprintHex;
        assignedCards.add(cardIndex);
      }
    }

    // 执行分配并通知
    for (final entry in assignments.entries) {
      final cardIndex = entry.key;
      final memberFp = entry.value;
      final member =
          room.members.firstWhere((m) => m.fingerprintHex == memberFp);

      room.wordCardPicks[cardIndex] = memberFp;
      final word = room.wordCards[cardIndex];
      room.memberDrawWords[memberFp] = word;

      // 私发词条
      final wordResult = WordPickResult(word: word);
      final resultMsg = ProtocolHandler.encode(
          MessageType.wordPickResult, wordResult.encode());
      final memberIdx =
          room.members.indexWhere((m) => m.fingerprintHex == memberFp);
      if (memberIdx >= 0 && memberIdx < room.memberSockets.length) {
        final s = room.memberSockets[memberIdx];
        if (s != null) {
          try {
            s.add(resultMsg);
          } catch (_) {}
        }
      }

      // 广播翻牌选择
      final pickBroadcast = CardPickBroadcast(
        cardIndex: cardIndex,
        username: member.username,
        fingerprintHex: memberFp,
      );
      RoomBroadcaster.broadcast(
        room,
        MessageType.wordPickBroadcast,
        pickBroadcast.encode(),
      );
    }
  }

  /// 处理词条卡牌选择
  /// 返回是否需要提前结束（全员选完）
  bool handleWordCardPick(
    RoomData room,
    String fingerprintHex,
    String username,
    int cardIndex,
  ) {
    if (room.gamePhase != GamePhase.wordPicking) return false;

    // 检查是否已选
    if (room.wordCardPicks.containsValue(fingerprintHex)) return false;

    // 检查卡牌是否可选
    if (room.wordCardPicks.containsKey(cardIndex)) return false;

    // 检查是否可选（排除自己的卡）
    if (cardIndex < room.wordCardOwnerFps.length &&
        room.wordCardOwnerFps[cardIndex] == fingerprintHex) return false;
    if (cardIndex < room.wordCardGuesserFps.length &&
        room.wordCardGuesserFps[cardIndex] == fingerprintHex) return false;

    room.wordCardPicks[cardIndex] = fingerprintHex;
    final word = room.wordCards[cardIndex];
    room.memberDrawWords[fingerprintHex] = word;

    // 私发词条
    final wordResult = WordPickResult(word: word);
    final memberIdx =
        room.members.indexWhere((m) => m.fingerprintHex == fingerprintHex);
    if (memberIdx >= 0 && memberIdx < room.memberSockets.length) {
      final s = room.memberSockets[memberIdx];
      if (s != null) {
        try {
          s.add(ProtocolHandler.encode(
              MessageType.wordPickResult, wordResult.encode()));
        } catch (_) {}
      }
    }

    // 广播翻牌选择
    final pickBroadcast = CardPickBroadcast(
      cardIndex: cardIndex,
      username: username,
      fingerprintHex: fingerprintHex,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.wordPickBroadcast,
      pickBroadcast.encode(),
    );

    // 检查剩余人数
    final remaining = room.members.length - room.wordCardPicks.length;
    if (remaining <= 0) return true; // 全员选完
    if (remaining <= 3) return true; // 提前自动分配
    return false;
  }

  /// 启动作画阶段
  void startDrawingPhase(RoomData room) {
    room.gamePhase = GamePhase.drawing;

    for (int i = 0; i < room.members.length; i++) {
      final member = room.members[i];
      final socket = room.memberSockets[i];
      if (socket == null) continue;
      final word = room.memberDrawWords[member.fingerprintHex] ?? '';

      final broadcast = DrawingPhaseBroadcast(
        round: room.currentRound,
        totalRounds: room.rounds,
        drawTime: room.roundTime,
        word: word,
        memberWords: room.memberDrawWords.map((k, v) =>
            MapEntry(k, room.members.indexWhere((m) => m.fingerprintHex == k))),
      );
      try {
        socket.add(ProtocolHandler.encode(
            MessageType.drawingPhaseBroadcast, broadcast.encode()));
      } catch (_) {}
    }

    _log('作画阶段开始，时限 ${room.roundTime}秒',
        room: room.roomId, action: 'DRAWING_PHASE');

    room.phaseTimer?.cancel();
    room.phaseEndAt = DateTime.now().add(Duration(seconds: room.roundTime));
    room.phaseTimer = Timer(Duration(seconds: room.roundTime), () {
      onDrawingPhaseEnd(room);
    });
  }

  /// 作画阶段结束
  void onDrawingPhaseEnd(RoomData room) {
    if (room.gamePhase != GamePhase.drawing) return;
    room.phaseTimer?.cancel();
    room.phaseEndAt = null;

    // 填充空白PNG
    for (final member in room.members) {
      if (!room.memberDrawings.containsKey(member.fingerprintHex)) {
        room.memberDrawings[member.fingerprintHex] = emptyPng;
        _log('成员未提交画作，已填入空白占位PNG',
            username: member.username,
            action: 'DRAWING_FALLBACK',
            room: room.roomId);
      }
    }

    _log('作画阶段结束', room: room.roomId, action: 'DRAWING_PHASE_END');

    startGuessPhase(room);
  }

  /// 处理绘画上传
  void handleDrawingUpload(
      RoomData room, String fingerprintHex, Uint8List payload) {
    room.memberDrawings[fingerprintHex] = payload;
    _log('绘画已上传 (${payload.length} bytes)',
        fingerprintHex: fingerprintHex,
        action: 'DRAWING_UPLOAD',
        room: room.roomId);
  }

  /// 处理绘画完成通知
  /// 返回是否全员完成
  bool handleDrawingComplete(RoomData room, String fingerprintHex) {
    if (room.gamePhase != GamePhase.drawing) return false;

    room.drawingCompletedMembers.add(fingerprintHex);

    _log('绘画完成 (${room.drawingCompletedMembers.length}/${room.members.length})',
        fingerprintHex: fingerprintHex,
        action: 'DRAWING_COMPLETE',
        room: room.roomId);

    return room.drawingCompletedMembers.length >= room.members.length;
  }

  /// 启动猜测阶段（卡牌抽取 + 猜测）
  void startGuessPhase(RoomData room) {
    room.gamePhase = GamePhase.cardPicking;

    final fpToMember = {for (var m in room.members) m.fingerprintHex: m};
    final cards = <GuessCard>[];

    if (room.wordCardOwnerFps.isNotEmpty) {
      for (final fp in room.wordCardOwnerFps) {
        final member = fpToMember[fp];
        if (member != null) {
          cards.add(GuessCard(
            label: member.username,
            fingerprintHex: member.fingerprintHex,
            username: member.username,
          ));
        }
      }
    }

    if (cards.length != room.members.length) {
      cards.clear();
      for (final member in room.members) {
        cards.add(GuessCard(
          label: member.username,
          fingerprintHex: member.fingerprintHex,
          username: member.username,
        ));
      }
      cards.shuffle(_random);
    }
    room.guessCards = cards;

    final broadcast = GuessPhaseBroadcast(
      round: room.currentRound,
      totalRounds: room.rounds,
      guessTime: 30,
      cardPickTime: 10,
      cards: cards,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.guessPhaseBroadcast,
      broadcast.encode(),
    );

    _log('猜测阶段开始（卡牌抽取 10秒 + 猜测 30秒）', room: room.roomId, action: 'GUESS_PHASE');

    room.phaseTimer?.cancel();
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 10));
    room.phaseTimer = Timer(const Duration(seconds: 10), () {
      onCardPickTimeEnd(room, delayTransition: true);
    });

    // 3人房自动分配
    if (room.members.length <= 3) {
      Timer(const Duration(milliseconds: 200), () {
        if (room.gamePhase != GamePhase.cardPicking) return;
        if (room.guessCardPicks.isNotEmpty) return;
        onCardPickTimeEnd(room, delayTransition: true);
      });
    }
  }

  /// 卡牌抽取时间结束
  void onCardPickTimeEnd(RoomData room, {bool delayTransition = false}) {
    if (room.gamePhase != GamePhase.cardPicking) return;
    room.phaseTimer?.cancel();
    room.phaseEndAt = null;

    _autoAssignUnpickedGuessCards(room);

    _log('卡牌抽取结束，进入猜测阶段', room: room.roomId, action: 'CARD_PICK_END');

    if (delayTransition) {
      room.phaseEndAt = DateTime.now().add(const Duration(seconds: 2));
      room.phaseTimer = Timer(const Duration(seconds: 2), () {
        room.phaseEndAt = null;
        transitionToGuessing(room);
      });
    } else {
      transitionToGuessing(room);
    }
  }

  /// 自动分配未选的猜测卡牌
  void _autoAssignUnpickedGuessCards(RoomData room) {
    final pickedMembers = room.guessCardPicks.values.toSet();
    final unpickedMembers = room.members
        .where((m) => !pickedMembers.contains(m.fingerprintHex))
        .toList();
    final unpickedCards = List.generate(room.guessCards.length, (i) => i)
        .where((i) => !room.guessCardPicks.containsKey(i))
        .toList();

    if (unpickedMembers.isEmpty || unpickedCards.isEmpty) return;

    // 打乱后顺序分配（排除自己的画作卡）
    unpickedMembers.shuffle(_random);
    unpickedCards.shuffle(_random);

    for (final member in unpickedMembers) {
      int? cardIndex;
      for (final idx in unpickedCards) {
        if (idx < room.guessCards.length &&
            room.guessCards[idx].fingerprintHex != member.fingerprintHex) {
          cardIndex = idx;
          break;
        }
      }
      if (cardIndex == null && unpickedCards.isNotEmpty) {
        cardIndex = unpickedCards.first;
      }
      if (cardIndex != null) {
        room.guessCardPicks[cardIndex] = member.fingerprintHex;
        unpickedCards.remove(cardIndex);

        final broadcast = CardPickBroadcast(
          cardIndex: cardIndex,
          username: member.username,
          fingerprintHex: member.fingerprintHex,
        );
        RoomBroadcaster.broadcast(
          room,
          MessageType.cardPickBroadcast,
          broadcast.encode(),
        );
      }
    }
  }

  /// 处理猜测卡牌选择
  /// 返回 (needAutoAssign, allDone)
  (bool, bool) handleGuessCardPick(
    RoomData room,
    String fingerprintHex,
    String username,
    int cardIndex,
  ) {
    if (room.gamePhase != GamePhase.cardPicking) return (false, false);

    // 检查是否已选
    if (room.guessCardPicks.containsValue(fingerprintHex))
      return (false, false);
    if (room.guessCardPicks.containsKey(cardIndex)) return (false, false);

    // 不能选自己的画作卡
    if (cardIndex < room.guessCards.length &&
        room.guessCards[cardIndex].fingerprintHex == fingerprintHex) {
      return (false, false);
    }

    room.guessCardPicks[cardIndex] = fingerprintHex;

    final broadcast = CardPickBroadcast(
      cardIndex: cardIndex,
      username: username,
      fingerprintHex: fingerprintHex,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.cardPickBroadcast,
      broadcast.encode(),
    );

    final remaining = room.members.length - room.guessCardPicks.length;
    if (remaining <= 0) return (false, true);
    if (remaining <= 3) return (true, false);
    return (false, false);
  }

  /// 进入猜测阶段（下发PNG + 启动计时器）
  void transitionToGuessing(RoomData room) {
    room.gamePhase = GamePhase.guessing;

    // 预填充默认猜测值
    for (final entry in room.guessCardPicks.entries) {
      final cardIndex = entry.key;
      if (cardIndex < room.guessCards.length) {
        final card = room.guessCards[cardIndex];
        room.guessResults[entry.value] = {
          'cardIndex': cardIndex,
          'guess': '未猜测',
          'targetFingerprintHex': card.fingerprintHex,
        };
      }
    }

    // 下发PNG图片
    for (int i = 0; i < room.members.length; i++) {
      final member = room.members[i];
      final socket = room.memberSockets[i];
      if (socket == null) continue;

      final cardIndex = room.guessCardPicks.entries
          .firstWhere((e) => e.value == member.fingerprintHex,
              orElse: () => MapEntry(-1, ''))
          .key;
      if (cardIndex < 0 || cardIndex >= room.guessCards.length) continue;

      final targetFp = room.guessCards[cardIndex].fingerprintHex;
      final pngBytes = room.memberDrawings[targetFp];
      if (pngBytes == null) continue;

      final imageData = DrawingImageData(
        fingerprintHex: targetFp,
        username: room.members
            .firstWhere((m) => m.fingerprintHex == targetFp,
                orElse: () => RoomMember(
                    username: '', fingerprintHex: '', isReady: false))
            .username,
        pngData: pngBytes,
      );
      try {
        socket.add(ProtocolHandler.encode(
            MessageType.drawingImageData, imageData.encode()));
      } catch (_) {}
    }

    _log('猜测阶段：下发PNG完成，启动30秒猜测计时',
        room: room.roomId, action: 'GUESS_TIMER_START');

    room.phaseTimer?.cancel();
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 30));
    room.phaseTimer = Timer(const Duration(seconds: 30), () {
      onGuessPhaseEnd(room);
    });
  }

  /// 处理猜测提交
  /// 返回是否全员提交完成
  bool handleGuessSubmit(
    RoomData room,
    String fingerprintHex,
    String username,
    int cardIndex,
    String guessText,
  ) {
    if (room.gamePhase != GamePhase.guessing) return false;

    final targetFp = cardIndex < room.guessCards.length
        ? room.guessCards[cardIndex].fingerprintHex
        : '';
    final targetUsername = room.members
        .firstWhere((m) => m.fingerprintHex == targetFp,
            orElse: () =>
                RoomMember(username: '', fingerprintHex: '', isReady: false))
        .username;

    room.guessResults[fingerprintHex] = {
      'cardIndex': cardIndex,
      'guess': guessText,
      'targetFingerprintHex': targetFp,
    };
    room.guessSubmitHistory
        .putIfAbsent(fingerprintHex, () => <Map<String, dynamic>>[])
        .add({
      'at': DateTime.now().toIso8601String(),
      'guess': guessText,
      'targetFingerprintHex': targetFp,
    });

    // 记录本轮猜测（供下一回合使用）
    room.lastRoundGuesses[fingerprintHex] = guessText;
    room.lastRoundGuessers[fingerprintHex] = targetFp;

    // 广播猜测结果
    final broadcast = GuessResultBroadcast(
      fingerprintHex: fingerprintHex,
      username: username,
      cardIndex: cardIndex,
      guess: guessText,
      targetFingerprintHex: targetFp,
      targetUsername: targetUsername,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.guessResultBroadcast,
      broadcast.encode(),
    );

    return room.guessSubmitHistory.length >= room.members.length;
  }

  /// 猜测阶段结束
  void onGuessPhaseEnd(RoomData room) {
    if (room.gamePhase != GamePhase.guessing) return;
    room.phaseTimer?.cancel();
    room.phaseEndAt = null;

    // 保存回合快照
    room.roundHistory.add({
      'round': room.currentRound,
      'wordCards': List<String>.from(room.wordCards),
      'wordCardOwnerFps': List<String>.from(room.wordCardOwnerFps),
      'wordCardPicks': Map<int, String>.from(room.wordCardPicks),
      'memberDrawWords': Map<String, String>.from(room.memberDrawWords),
      'memberDrawings': Map<String, Uint8List>.from(room.memberDrawings),
      'guessCards': room.guessCards.map((c) => c.toJson()).toList(),
      'guessCardPicks': Map<int, String>.from(room.guessCardPicks),
      'guessResults': Map<String, dynamic>.from(room.guessResults),
    });

    // 为未猜测成员填入默认值
    for (final member in room.members) {
      room.lastRoundGuesses.putIfAbsent(member.fingerprintHex, () => '未猜测');
      room.lastRoundGuessers.putIfAbsent(member.fingerprintHex, () => '');
    }

    _log('第 ${room.currentRound} 回合结束', room: room.roomId, action: 'ROUND_END');
  }
}
