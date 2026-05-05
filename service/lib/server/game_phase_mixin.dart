import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:io';

import '../protocol/protocol_handler.dart';
import '../room/room_data.dart';
import '../room/room_broadcaster.dart';
import '../room/replay_builder.dart';
import '../room/client_session.dart';
import 'tcp_server_base.dart';

/// 游戏阶段状态机 Mixin
/// 包含：词条翻牌、作画、卡牌抽取、猜测、复盘等完整游戏流程
mixin GamePhaseMixin on TcpServerBase {
  /// 最小有效 1x1 白色 PNG（67字节）
  static final Uint8List _emptyPng = Uint8List.fromList([
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

  /// 启动下一回合
  void startNextRound(RoomData room) => _startNextRound(room);

  void _startNextRound(RoomData room) {
    room.currentRound++;
    room.resetRoundData();

    if (room.currentRound > room.rounds) {
      // 所有回合结束，进入结算
      _endGame(room);
      return;
    }

    this.log('开始第 ${room.currentRound}/${room.rounds} 回合',
        room: room.roomId, action: 'ROUND_START');

    _startWordPickPhase(room);
  }

  /// 启动词条翻牌阶段
  void _startWordPickPhase(RoomData room) {
    room.gamePhase = GamePhase.wordPicking;
    room.wordCards.clear();
    room.wordCardOwnerFps.clear();
    room.wordCardPicks.clear();

    // 构建词条卡牌 + 所属者列表
    // 先打乱成员顺序，每张卡牌对应一个成员（画作翻牌阶段会复用此顺序）
    final shuffledMembers = List.of(room.members);
    final random = Random();
    shuffledMembers.shuffle(random);

    // ownerFps 始终与 shuffledMembers 一一对应，确保 excludeIdx 和画作翻牌顺序正确
    List<String> ownerFps =
        shuffledMembers.map((m) => m.fingerprintHex).toList();
    List<String> words = [];

    if (room.currentRound == 1) {
      // 第一回合：从词库随机抽取，每张卡对应一个成员
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
          this.log('解析词库失败: $e', action: 'WORD_PICK_ERROR');
        }
      }
      if (allWords.isNotEmpty) {
        final shuffledWords = List<String>.from(allWords);
        shuffledWords.shuffle(random);
        for (int i = 0; i < shuffledMembers.length; i++) {
          words.add(shuffledWords[i % shuffledWords.length]);
        }
      } else {
        // 词库为空时使用默认词条
        words = List.filled(shuffledMembers.length, '默认词条');
      }
    } else {
      // 后续回合：使用上一轮的猜测文本作为词条，所属者为猜测者
      this.log('lastRoundGuesses 内容:',
          room: room.roomId, action: 'WORD_PICK_DEBUG');
      for (final entry in room.lastRoundGuesses.entries) {
        this.log('  ${entry.key}: "${entry.value}"',
            room: room.roomId, action: 'WORD_PICK_DEBUG');
      }
      for (final member in shuffledMembers) {
        final word = room.lastRoundGuesses[member.fingerprintHex] ?? '未猜测';
        words.add(word);
        this.log(
            '  成员 ${member.username}(${member.fingerprintHex}) 的猜测词: "$word"',
            room: room.roomId,
            action: 'WORD_PICK_DEBUG');
      }
    }

    // 词条和所属者已按打乱后的成员顺序排列，直接赋值
    room.wordCards = words;
    room.wordCardOwnerFps = ownerFps;
    room.wordCardGuesserFps = room.currentRound == 1
        ? List<String>.filled(room.wordCards.length, '', growable: true)
        : room.wordCardOwnerFps
            .map((ownerFp) => room.lastRoundGuessers[ownerFp] ?? '')
            .toList(growable: true);

    final fpToName = {
      for (final m in room.members) m.fingerprintHex: m.username
    };
    final ownerNames = room.wordCardOwnerFps
        .map((fp) => fpToName[fp] ?? '未知')
        .toList(growable: false);

    // 调试日志：打印卡牌与所属者的对应关系
    this.log('词条卡牌与所属者对应关系:', room: room.roomId, action: 'WORD_PICK_DEBUG');
    for (int i = 0; i < room.wordCards.length; i++) {
      final ownerFp = room.wordCardOwnerFps[i];
      final owner = room.members.firstWhere(
        (m) => m.fingerprintHex == ownerFp,
        orElse: () =>
            RoomMember(username: '未知', fingerprintHex: ownerFp, isReady: false),
      );
      this.log(
          '  卡牌[$i]: "${room.wordCards[i]}" -> 所属者 ${owner.username}($ownerFp)',
          room: room.roomId,
          action: 'WORD_PICK_DEBUG');
    }

    this.log('词条卡牌所属者列表: ${room.wordCardOwnerFps}',
        room: room.roomId, action: 'WORD_PICK_DEBUG');
    this.log('词条卡牌猜测者列表: ${room.wordCardGuesserFps}',
        room: room.roomId, action: 'WORD_PICK_DEBUG');
    this.log('lastRoundGuessers 内容: ${room.lastRoundGuessers}',
        room: room.roomId, action: 'WORD_PICK_DEBUG');

    // 向每个成员分别发送广播（包含该成员需排除的卡牌索引）
    for (int i = 0; i < room.members.length; i++) {
      final member = room.members[i];
      final socket = room.memberSockets[i];
      if (socket == null) continue;
      // 找出该成员需排除的卡牌（自己的猜测/画作对应的词条卡）
      final excludeIdx = room.currentRound == 1
          ? -1
          : (room.wordCardGuesserFps.indexOf(member.fingerprintHex) >= 0
              ? room.wordCardGuesserFps.indexOf(member.fingerprintHex)
              : room.wordCardOwnerFps.indexOf(member.fingerprintHex));
      this.log(
          '成员 ${member.username}(${member.fingerprintHex}) excludeIdx=$excludeIdx',
          room: room.roomId,
          action: 'WORD_PICK_DEBUG');
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

    this.log('词条翻牌阶段开始（${words.length}张卡牌，10秒）',
        room: room.roomId, action: 'WORD_PICK_PHASE');

    // 启动10秒倒计时
    room.phaseTimer?.cancel();
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 10));
    room.phaseTimer = Timer(const Duration(seconds: 10), () {
      _onWordPickTimeEnd(room, delayTransition: true);
    });

    // 3人房（及以下）在阶段开始即自动分配：先确保客户端已收到阶段广播
    if (room.members.length <= 3) {
      Timer(const Duration(milliseconds: 200), () {
        if (room.gamePhase != GamePhase.wordPicking) return;
        if (room.wordCardPicks.isNotEmpty) return;
        _onWordPickTimeEnd(room, delayTransition: true);
      });
    }
  }

  /// 词条翻牌时间结束
  void _onWordPickTimeEnd(RoomData room, {bool delayTransition = false}) {
    if (room.gamePhase != GamePhase.wordPicking) return;
    room.phaseTimer?.cancel();
    room.phaseEndAt = null;

    // 自动为未选卡牌的成员分配
    final pickedMembers = room.wordCardPicks.values.toSet();
    final unpickedMembers = room.members
        .where((m) => !pickedMembers.contains(m.fingerprintHex))
        .toList();
    final unpickedCards = List.generate(room.wordCards.length, (i) => i)
        .where((i) => !room.wordCardPicks.containsKey(i))
        .toList();

    if (unpickedMembers.isNotEmpty && unpickedCards.isNotEmpty) {
      final random = Random();

      // 调试：打印所有卡牌的 owner 和 guesser
      this.log('词条翻牌自动分配调试：', room: room.roomId, action: 'WORD_PICK_DEBUG');
      for (int i = 0; i < room.wordCards.length; i++) {
        final owner =
            i < room.wordCardOwnerFps.length ? room.wordCardOwnerFps[i] : 'N/A';
        final guesser = i < room.wordCardGuesserFps.length
            ? room.wordCardGuesserFps[i]
            : 'N/A';
        this.log('  卡牌[$i]: owner=$owner, guesser=$guesser',
            room: room.roomId, action: 'WORD_PICK_DEBUG');
      }

      // 为每个成员计算可选卡牌（排除 owner==自己 和 guesser==自己）
      List<int> getAvailableCards(String memberFp, List<int> cards) {
        return cards.where((idx) {
          if (idx < room.wordCardOwnerFps.length &&
              room.wordCardOwnerFps[idx] == memberFp) return false;
          if (idx < room.wordCardGuesserFps.length &&
              room.wordCardGuesserFps[idx] == memberFp) return false;
          return true;
        }).toList();
      }

      // 直接尝试随机分配算法（不提前判断，让算法自己尝试）
      Map<int, String> assignments = {};
      Set<int> assignedCards = {};

      // 多次尝试随机分配
      bool success = false;
      for (int attempt = 0; attempt < 10 && !success; attempt++) {
        assignments.clear();
        assignedCards.clear();
        success = true;

        // 随机打乱成员顺序
        final shuffledMembers = List.of(unpickedMembers)..shuffle(random);

        for (final member in shuffledMembers) {
          final available = getAvailableCards(
            member.fingerprintHex,
            unpickedCards.where((c) => !assignedCards.contains(c)).toList(),
          );
          if (available.isEmpty) {
            success = false;
            break;
          }
          final cardIndex = available[random.nextInt(available.length)];
          assignments[cardIndex] = member.fingerprintHex;
          assignedCards.add(cardIndex);
        }
      }

      if (!success) {
        this.log('词条翻牌自动分配：随机分配失败，使用 fallback',
            room: room.roomId, action: 'WORD_PICK_FALLBACK');
      }

      // 如果无法无冲突分配，使用贪心算法最小化冲突数量
      // 策略：优先让可选卡牌少的成员先选，减少后续冲突
      if (assignments.isEmpty) {
        // 按可选卡牌数量升序排列成员
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
            cardIndex = available[random.nextInt(available.length)];
          } else {
            // 没有可选卡牌，强制分配最后一张
            cardIndex =
                unpickedCards.firstWhere((c) => !assignedCards.contains(c));
            this.log('词条翻牌 fallback：成员 ${member.username} 被强制分配冲突卡牌 $cardIndex',
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

        // 私发词条给该成员（离线玩家跳过）
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

    this.log('词条翻牌结束，进入作画阶段', room: room.roomId, action: 'WORD_PICK_END');

    // 进入作画阶段（可选延迟2秒让客户端展示自动分配的卡牌）
    if (delayTransition) {
      room.phaseEndAt = DateTime.now().add(const Duration(seconds: 2));
      room.phaseTimer = Timer(const Duration(seconds: 2), () {
        room.phaseEndAt = null;
        _startDrawingPhase(room);
      });
    } else {
      _startDrawingPhase(room);
    }
  }

  /// 启动作画阶段
  void _startDrawingPhase(RoomData room) {
    room.gamePhase = GamePhase.drawing;

    // 向每个成员分别发送各自的绘画词
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

    this.log('作画阶段开始，时限 ${room.roundTime}秒',
        room: room.roomId, action: 'DRAWING_PHASE');

    // 启动作画倒计时
    room.phaseTimer?.cancel();
    room.phaseEndAt = DateTime.now().add(Duration(seconds: room.roundTime));
    room.phaseTimer = Timer(Duration(seconds: room.roundTime), () {
      _onDrawingPhaseEnd(room);
    });
  }

  /// 作画阶段结束
  void onDrawingPhaseEnd(RoomData room) => _onDrawingPhaseEnd(room);

  void _onDrawingPhaseEnd(RoomData room) {
    if (room.gamePhase != GamePhase.drawing) return;
    room.phaseTimer?.cancel();
    room.phaseEndAt = null;

    // 为未上传画作的成员填入空白PNG占位，确保后续猜测阶段 pngData 不为 null
    for (final member in room.members) {
      if (!room.memberDrawings.containsKey(member.fingerprintHex)) {
        room.memberDrawings[member.fingerprintHex] = _emptyPng;
        this.log('成员未提交画作，已填入空白占位PNG',
            username: member.username,
            action: 'DRAWING_FALLBACK',
            room: room.roomId);
      }
    }

    this.log('作画阶段结束', room: room.roomId, action: 'DRAWING_PHASE_END');

    // 进入猜测阶段（卡牌抽取 + 猜测）
    _startGuessPhase(room);
  }

  /// 处理绘画上传
  void handleDrawingUpload(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null) return;

      // 存储绘画数据
      room.memberDrawings[session.fingerprintHex!] = payload;

      this.log('绘画已上传 (${payload.length} bytes)',
          username: session.username, action: 'DRAWING_UPLOAD', room: roomId);
    } catch (e) {
      this.log('处理绘画上传失败: $e',
          username: session.username, action: 'DRAWING_UPLOAD_ERROR');
    }
  }

  /// 处理绘画完成通知
  void handleDrawingComplete(
    Socket socket,
    ClientSession session,
  ) {
    try {
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null || room.gamePhase != GamePhase.drawing) return;

      room.drawingCompletedMembers.add(session.fingerprintHex!);

      this.log(
          '绘画完成 (${room.drawingCompletedMembers.length}/${room.members.length})',
          username: session.username,
          action: 'DRAWING_COMPLETE',
          room: roomId);

      // 如果所有成员都完成了，提前结束作画阶段
      if (room.drawingCompletedMembers.length >= room.members.length) {
        _onDrawingPhaseEnd(room);
      }
    } catch (e) {
      this.log('处理绘画完成失败: $e',
          username: session.username, action: 'DRAWING_COMPLETE_ERROR');
    }
  }

  /// 启动猜测阶段（卡牌抽取 + 猜测）
  void _startGuessPhase(RoomData room) {
    room.gamePhase = GamePhase.cardPicking;

    // 复用词条翻牌阶段的成员顺序（wordCardOwnerFps），使两个翻牌阶段卡牌位置一致
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
    // 兜底：如果wordCardOwnerFps为空或不匹配，回退到随机打乱
    if (cards.length != room.members.length) {
      cards.clear();
      for (final member in room.members) {
        cards.add(GuessCard(
          label: member.username,
          fingerprintHex: member.fingerprintHex,
          username: member.username,
        ));
      }
      cards.shuffle(Random());
    }
    room.guessCards = cards;

    this.log(
        '画作翻牌卡牌顺序: ${cards.map((c) => '${c.username}(${c.fingerprintHex})').toList()}',
        room: room.roomId,
        action: 'GUESS_PHASE_DEBUG');
    this.log('词条翻牌所属者顺序: ${room.wordCardOwnerFps}',
        room: room.roomId, action: 'GUESS_PHASE_DEBUG');

    // 广播猜测阶段开始
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

    this.log('猜测阶段开始（卡牌抽取 10秒 + 猜测 30秒）',
        room: room.roomId, action: 'GUESS_PHASE');

    // 启动卡牌抽取倒计时（10秒后自动翻开未选卡牌）
    room.phaseTimer?.cancel();
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 10));
    room.phaseTimer = Timer(const Duration(seconds: 10), () {
      _onCardPickTimeEnd(room, delayTransition: true);
    });

    // 3人房（及以下）在阶段开始即自动分配：先确保客户端已收到阶段广播
    if (room.members.length <= 3) {
      Timer(const Duration(milliseconds: 200), () {
        if (room.gamePhase != GamePhase.cardPicking) return;
        if (room.guessCardPicks.isNotEmpty) return;
        _onCardPickTimeEnd(room, delayTransition: true);
      });
    }
  }

  /// 处理卡牌选择（词条翻牌阶段 + 猜测阶段共用）
  void handleCardPick(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null) return;

      final pick = CardPickMessage.decode(payload);

      if (room.gamePhase == GamePhase.wordPicking) {
        // ===== 词条翻牌阶段 =====
        this.log('选择词条卡牌: ${pick.cardIndex}',
            username: session.username, action: 'WORD_PICK', room: roomId);

        // 检查卡牌是否已被选 & 用户是否已选过 & 不能选自己的卡 & 不能选上一回合自己提交的guessText对应卡牌
        if (room.wordCardPicks.containsKey(pick.cardIndex)) return;
        if (room.wordCardPicks.containsValue(session.fingerprintHex)) return;
        if (pick.cardIndex >= room.wordCards.length) return;
        if (pick.cardIndex < room.wordCardOwnerFps.length &&
            room.wordCardOwnerFps[pick.cardIndex] == session.fingerprintHex)
          return;

        if (pick.cardIndex < room.wordCardGuesserFps.length &&
            room.wordCardGuesserFps[pick.cardIndex] == session.fingerprintHex)
          return;

        room.wordCardPicks[pick.cardIndex] = session.fingerprintHex!;

        // 分配词条
        final word = room.wordCards[pick.cardIndex];
        room.memberDrawWords[session.fingerprintHex!] = word;

        // 私发词条给选择者
        final wordResult = WordPickResult(word: word);
        final resultMsg = ProtocolHandler.encode(
            MessageType.wordPickResult, wordResult.encode());
        try {
          socket.add(resultMsg);
        } catch (_) {}

        // 广播翻牌选择（不含词条内容）
        final broadcast = CardPickBroadcast(
          cardIndex: pick.cardIndex,
          username: session.username!,
          fingerprintHex: session.fingerprintHex!,
        );
        RoomBroadcaster.broadcast(
          room,
          MessageType.wordPickBroadcast,
          broadcast.encode(),
        );

        // 检查剩余未选人数：<=3时提前自动分配；所有人选完时延迟2秒转场
        final wordRemaining = room.members.length - room.wordCardPicks.length;
        if (wordRemaining > 0 && wordRemaining <= 3) {
          _onWordPickTimeEnd(room, delayTransition: true);
        } else if (wordRemaining <= 0) {
          // 所有人已手动选完，延迟2秒展示最后一张卡牌内容
          room.phaseTimer?.cancel();
          room.phaseEndAt = DateTime.now().add(const Duration(seconds: 2));
          room.phaseTimer = Timer(const Duration(seconds: 3), () {
            room.phaseEndAt = null;
            _onWordPickTimeEnd(room, delayTransition: true);
          });
        }
      } else if (room.gamePhase == GamePhase.cardPicking) {
        // ===== 猜测阶段卡牌选择 =====
        this.log('选择猜测卡牌: ${pick.cardIndex}',
            username: session.username, action: 'CARD_PICK', room: roomId);

        // 检查该卡牌是否已被选 & 不能选自己的画作卡
        if (!room.guessCardPicks.containsKey(pick.cardIndex)) {
          // 检查该用户是否已选过
          if (!room.guessCardPicks.containsValue(session.fingerprintHex)) {
            // 不能选自己的画作卡
            if (pick.cardIndex < room.guessCards.length &&
                room.guessCards[pick.cardIndex].fingerprintHex ==
                    session.fingerprintHex) {
              return;
            }
            room.guessCardPicks[pick.cardIndex] = session.fingerprintHex!;
          }
        }

        // 广播卡牌选择
        final broadcast = CardPickBroadcast(
          cardIndex: pick.cardIndex,
          username: session.username!,
          fingerprintHex: session.fingerprintHex!,
        );
        RoomBroadcaster.broadcast(
          room,
          MessageType.cardPickBroadcast,
          broadcast.encode(),
        );

        // 检查剩余未选人数：<=3时提前自动分配；所有人选完时延迟2秒转场
        final guessRemaining = room.members.length - room.guessCardPicks.length;
        if (guessRemaining > 0 && guessRemaining <= 3) {
          _onCardPickTimeEnd(room, delayTransition: true);
        } else if (guessRemaining <= 0) {
          // 所有人已手动选完，延迟2秒展示最后一张卡牌内容
          room.phaseTimer?.cancel();
          room.phaseEndAt = DateTime.now().add(const Duration(seconds: 2));
          room.phaseTimer = Timer(const Duration(seconds: 2), () {
            room.phaseEndAt = null;
            _onCardPickTimeEnd(room, delayTransition: true);
          });
        }
      }
    } catch (e) {
      this.log('处理卡牌选择失败: $e',
          username: session.username, action: 'CARD_PICK_ERROR');
    }
  }

  /// 卡牌抽取时间结束
  void _onCardPickTimeEnd(RoomData room, {bool delayTransition = false}) {
    if (room.gamePhase != GamePhase.cardPicking) return;
    room.phaseTimer?.cancel();
    room.phaseEndAt = null;

    // 自动为未选卡牌的成员分配卡牌
    final pickedMembers = room.guessCardPicks.values.toSet();
    final unpickedMembers = room.members
        .where((m) => !pickedMembers.contains(m.fingerprintHex))
        .toList();
    final unpickedCards = List.generate(room.guessCards.length, (i) => i)
        .where((i) => !room.guessCardPicks.containsKey(i))
        .toList();

    if (unpickedMembers.isNotEmpty && unpickedCards.isNotEmpty) {
      final random = Random();

      // 为每个成员计算可选卡牌（排除自己的画作）
      List<int> getAvailableCards(String memberFp, List<int> cards) {
        return cards.where((idx) {
          if (idx < room.guessCards.length &&
              room.guessCards[idx].fingerprintHex == memberFp) return false;
          return true;
        }).toList();
      }

      // 直接尝试随机分配算法（不提前判断，让算法自己尝试）
      Map<int, String> assignments = {};
      Set<int> assignedCards = {};

      // 多次尝试随机分配
      bool success = false;
      for (int attempt = 0; attempt < 10 && !success; attempt++) {
        assignments.clear();
        assignedCards.clear();
        success = true;

        // 随机打乱成员顺序
        final shuffledMembers = List.of(unpickedMembers)..shuffle(random);

        for (final member in shuffledMembers) {
          final available = getAvailableCards(
            member.fingerprintHex,
            unpickedCards.where((c) => !assignedCards.contains(c)).toList(),
          );
          if (available.isEmpty) {
            success = false;
            break;
          }
          final cardIndex = available[random.nextInt(available.length)];
          assignments[cardIndex] = member.fingerprintHex;
          assignedCards.add(cardIndex);
        }
      }

      if (!success) {
        this.log('画作翻牌自动分配：随机分配失败，使用 fallback',
            room: room.roomId, action: 'CARD_PICK_FALLBACK');
      }

      // 如果无法无冲突分配，使用贪心算法最小化冲突数量
      // 策略：优先让可选卡牌少的成员先选，减少后续冲突
      if (assignments.isEmpty) {
        // 按可选卡牌数量升序排列成员
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
            cardIndex = available[random.nextInt(available.length)];
          } else {
            // 没有可选卡牌，强制分配最后一张
            cardIndex =
                unpickedCards.firstWhere((c) => !assignedCards.contains(c));
            this.log(
                '画作翻牌 fallback：成员 ${member.username} 被强制分配自己的画作 $cardIndex',
                room: room.roomId,
                action: 'CARD_PICK_FALLBACK');
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

        room.guessCardPicks[cardIndex] = memberFp;

        // 广播自动分配的卡牌
        final broadcast = CardPickBroadcast(
          cardIndex: cardIndex,
          username: member.username,
          fingerprintHex: memberFp,
        );
        RoomBroadcaster.broadcast(
          room,
          MessageType.cardPickBroadcast,
          broadcast.encode(),
        );
      }
    }

    this.log('卡牌抽取结束，进入猜测阶段', room: room.roomId, action: 'CARD_PICK_END');

    // 延迟或立即进入猜测阶段
    if (delayTransition) {
      room.phaseEndAt = DateTime.now().add(const Duration(seconds: 2));
      room.phaseTimer = Timer(const Duration(seconds: 2), () {
        room.phaseEndAt = null;
        _transitionToGuessing(room);
      });
    } else {
      _transitionToGuessing(room);
    }
  }

  /// 卡牌抽取完成后进入猜测阶段（下发PNG + 启动计时器）
  void _transitionToGuessing(RoomData room) {
    room.gamePhase = GamePhase.guessing;

    // 为所有已分配卡牌的成员预填充"未猜测"作为默认猜测值
    for (final entry in room.guessCardPicks.entries) {
      final cardIndex = entry.key;
      final pickerFp = entry.value;
      if (cardIndex < room.guessCards.length) {
        final card = room.guessCards[cardIndex];
        room.guessResults[pickerFp] = {
          'cardIndex': cardIndex,
          'guess': '未猜测',
          'targetFingerprintHex': card.fingerprintHex,
          'targetUsername': card.username,
        };
      }
    }

    // 向每个选中了卡牌的成员下发对应绘画者的PNG图片
    for (final entry in room.guessCardPicks.entries) {
      final cardIndex = entry.key;
      final pickerFp = entry.value;
      if (cardIndex < room.guessCards.length) {
        final card = room.guessCards[cardIndex];
        final drawerFp = card.fingerprintHex;
        final pngData = room.memberDrawings[drawerFp];
        if (pngData != null) {
          // 找到选择者的socket
          final pickerIdx =
              room.members.indexWhere((m) => m.fingerprintHex == pickerFp);
          if (pickerIdx >= 0 && pickerIdx < room.memberSockets.length) {
            final s = room.memberSockets[pickerIdx];
            if (s != null) {
              final imgData = DrawingImageData(
                fingerprintHex: drawerFp,
                username: card.username,
                pngData: pngData,
              );
              try {
                s.add(ProtocolHandler.encode(
                    MessageType.drawingImageData, imgData.encode()));
              } catch (_) {}
            }
          }
        }
      }
    }

    // 启动猜测倒计时（30秒）
    room.phaseTimer?.cancel();
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 30));
    room.phaseTimer = Timer(const Duration(seconds: 30), () {
      _onGuessPhaseEnd(room);
    });
  }

  /// 处理猜测提交
  void handleGuessSubmit(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null || room.gamePhase != GamePhase.guessing) return;

      final guess = GuessSubmitMessage.decode(payload);

      // 记录猜测结果
      final cardIndex = guess.cardIndex;
      String targetFp = '';
      String targetUsername = '';
      if (cardIndex < room.guessCards.length) {
        targetFp = room.guessCards[cardIndex].fingerprintHex;
        targetUsername = room.guessCards[cardIndex].username;
      }

      room.guessResults[session.fingerprintHex!] = {
        'cardIndex': cardIndex,
        'guess': guess.guess,
        'targetFingerprintHex': targetFp,
        'targetUsername': targetUsername,
      };

      final fp = session.fingerprintHex!;
      room.guessSubmitHistory
          .putIfAbsent(fp, () => <Map<String, dynamic>>[])
          .add({
        'at': DateTime.now().toIso8601String(),
        'cardIndex': cardIndex,
        'guess': guess.guess,
        'targetFingerprintHex': targetFp,
        'targetUsername': targetUsername,
      });

      this.log(
          '猜测提交: "${guess.guess}" (${room.guessResults.length}/${room.members.length})',
          username: session.username,
          action: 'GUESS_SUBMIT',
          room: roomId);

      // 广播猜测结果
      final broadcast = GuessResultBroadcast(
        fingerprintHex: session.fingerprintHex!,
        username: session.username!,
        cardIndex: cardIndex,
        guess: guess.guess,
        targetFingerprintHex: targetFp,
        targetUsername: targetUsername,
      );
      RoomBroadcaster.broadcast(
        room,
        MessageType.guessResultBroadcast,
        broadcast.encode(),
      );

      // 检查是否所有人都实际提交了猜测（guessSubmitHistory记录了真实提交）
      if (room.guessSubmitHistory.length >= room.members.length) {
        _onGuessPhaseEnd(room);
      }
    } catch (e) {
      this.log('处理猜测提交失败: $e',
          username: session.username, action: 'GUESS_SUBMIT_ERROR');
    }
  }

  /// 猜测阶段结束
  void onGuessPhaseEnd(RoomData room) => _onGuessPhaseEnd(room);

  void _onGuessPhaseEnd(RoomData room) {
    if (room.gamePhase != GamePhase.guessing) return;
    room.phaseTimer?.cancel();
    room.gamePhase = GamePhase.roundResult;

    final archivedDrawings = <String, Uint8List>{};
    for (final e in room.memberDrawings.entries) {
      archivedDrawings[e.key] = Uint8List.fromList(e.value);
    }
    final archived = <String, dynamic>{
      'round': room.currentRound,
      'archivedAt': DateTime.now().toIso8601String(),
      'members': room.members
          .map((m) => {
                'username': m.username,
                'fingerprintHex': m.fingerprintHex,
              })
          .toList(growable: false),
      'wordCards': List<String>.from(room.wordCards),
      'wordCardOwnerFps': List<String>.from(room.wordCardOwnerFps),
      'wordCardPicks': Map<int, String>.from(room.wordCardPicks),
      'memberDrawWords': Map<String, String>.from(room.memberDrawWords),
      'memberDrawings': archivedDrawings,
      'guessCards': room.guessCards
          .map((c) => {
                'username': c.username,
                'fingerprintHex': c.fingerprintHex,
              })
          .toList(growable: false),
      'guessCardPicks': Map<int, String>.from(room.guessCardPicks),
      'guessResults': room.guessResults
          .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v))),
      'guessSubmitHistory': room.guessSubmitHistory.map(
        (fp, list) => MapEntry(
          fp,
          list.map((e) => Map<String, dynamic>.from(e)).toList(growable: false),
        ),
      ),
    };
    room.roundHistory.add(archived);
    while (room.roundHistory.length > 20) {
      room.roundHistory.removeAt(0);
    }

    // 收集本回合结果
    final results = <Map<String, dynamic>>[];
    for (final member in room.members) {
      final drawWord = room.memberDrawWords[member.fingerprintHex] ?? '';
      final guessData = room.guessResults[member.fingerprintHex];
      results.add({
        'username': member.username,
        'fingerprintHex': member.fingerprintHex,
        'drawWord': drawWord,
        'guess': guessData?['guess'] ?? '未猜测',
        'targetUsername': guessData?['targetUsername'] ?? '',
        'targetFingerprintHex': guessData?['targetFingerprintHex'] ?? '',
      });
    }
    room.allRoundResults.add({
      'round': room.currentRound,
      'results': results,
    });

    // 保存本轮猜测文本供下一轮使用
    // 关键：以被猜者/作画者的指纹为key，猜测文本为value
    room.lastRoundGuesses.clear();
    room.lastRoundGuessers.clear();
    for (final entry in room.guessResults.entries) {
      final guesserFp = entry.key;
      final data = entry.value;
      final guess = data['guess'] as String;
      final targetFp = (data['targetFingerprintHex'] as String?) ?? '';
      if (targetFp.isNotEmpty) {
        room.lastRoundGuesses[targetFp] = guess;
        room.lastRoundGuessers[targetFp] = guesserFp;
      }
    }
    // 为没有被猜到的成员设置"未猜测"
    for (final member in room.members) {
      room.lastRoundGuesses.putIfAbsent(member.fingerprintHex, () => '未猜测');
      room.lastRoundGuessers.putIfAbsent(member.fingerprintHex, () => '');
    }

    this.log('第 ${room.currentRound} 回合结束',
        room: room.roomId, action: 'ROUND_END');

    // 检查是否已经是最后一回合
    if (room.currentRound >= room.rounds) {
      unawaited(_generateReplayAndStartReview(room));
    } else {
      _startNextRound(room);
    }
  }

  /// 生成复盘文件并开始复盘流程
  Future<void> _generateReplayAndStartReview(RoomData room) async {
    this.log('所有回合结束，准备生成复盘数据', room: room.roomId, action: 'REVIEW_PREPARE');

    final ok = await _doGenerateReplay(room);
    if (!ok) {
      this.log('复盘数据生成失败，直接开始复盘',
          room: room.roomId, action: 'REPLAY_BUILD_FAILED');
      _startReviewPhase(room);
      return;
    }

    // 广播复盘数据
    if (room.lastReplayFile != null) {
      final replayBroadcast = ReplayFileBroadcast(replay: room.lastReplayFile!);
      RoomBroadcaster.broadcast(
        room,
        MessageType.replayFileBroadcast,
        replayBroadcast.encode(),
      );
    }

    // 等待客户端确认收到复盘文件后再进入复盘阶段（避免结算界面时间错位）
    _waitReplayAckAndStartReview(room);
  }

  void _waitReplayAckAndStartReview(RoomData room) {
    room.replayAckTimer?.cancel();
    room.replayAckedFps.clear();
    final replayId = room.lastReplayFile?['replayId']?.toString() ?? '';

    this.log('等待复盘ACK: replayId=$replayId',
        room: room.roomId, action: 'REPLAY_ACK_WAIT');

    // 最长等待3秒，超时视为已收到（避免卡死）
    room.replayAckTimer = Timer(const Duration(seconds: 3), () {
      this.log('复盘ACK等待超时，强制开始复盘',
          room: room.roomId, action: 'REPLAY_ACK_TIMEOUT');
      _startReviewPhase(room);
    });

    // 如果房间内没人，直接开始
    if (room.members.isEmpty) {
      room.replayAckTimer?.cancel();
      _startReviewPhase(room);
    }
  }

  void handleReplayAck(
      Socket socket, ClientSession session, Uint8List payload) {
    final roomId = session.currentRoomId;
    if (roomId == null) return;
    final room = rooms[roomId];
    if (room == null) return;
    if (!session.isAuthenticated || session.fingerprintHex == null) return;

    // 仅在"已生成复盘但尚未进入reviewing"阶段接收ACK
    if (room.lastReplayFile == null) return;
    if (room.gamePhase == GamePhase.reviewing) return;

    try {
      final ack = ReplayAck.decode(payload);
      final currentReplayId =
          room.lastReplayFile?['replayId']?.toString() ?? '';
      if (ack.replayId.isNotEmpty &&
          currentReplayId.isNotEmpty &&
          ack.replayId != currentReplayId) {
        return;
      }

      final fp = session.fingerprintHex!;
      room.replayAckedFps.add(fp);

      if (room.replayAckedFps.length >= room.members.length) {
        room.replayAckTimer?.cancel();
        this.log('复盘ACK已收齐，开始复盘', room: room.roomId, action: 'REPLAY_ACK_ALL');
        _startReviewPhase(room);
      }
    } catch (_) {
      // ignore
    }
  }

  /// 纯粹的复盘生成逻辑
  Future<bool> _doGenerateReplay(RoomData room) async {
    try {
      final roomSnap = <String, dynamic>{
        'roomId': room.roomId,
        'rounds': room.rounds,
        'members': room.members
            .map((m) => {
                  'fp': m.fingerprintHex,
                  'username': m.username,
                })
            .toList(growable: false),
        'roundHistory': room.roundHistory,
      };

      room.lastReplayFile = await Isolate.run(() {
        return ReplayBuilder.buildFromSnapshot(roomSnap);
      });
      return room.lastReplayFile != null;
    } catch (_) {
      room.lastReplayFile = null;
      return false;
    }
  }

  /// 进入复盘阶段
  void startReviewPhase(RoomData room) => _startReviewPhase(room);

  void _startReviewPhase(RoomData room) {
    room.gamePhase = GamePhase.reviewing;
    room.currentReviewPathIndex = 0;
    room.currentReviewStepIndex = 0;
    room.reviewVotes.clear();
    room.reviewSubPhase = ReviewSubPhase.showingSteps;
    room.reviewFlowToken++;
    final token = room.reviewFlowToken;
    room.phaseTimer?.cancel();
    room.reviewStepTimer?.cancel();
    room.reviewAdvanceTimer?.cancel();

    // 广播进入复盘阶段
    RoomBroadcaster.broadcast(
      room,
      MessageType.reviewPhaseBroadcast,
      Uint8List(0),
    );

    this.log('进入复盘阶段', room: room.roomId, action: 'REVIEW_START');

    _broadcastReviewProgress(room);

    // 延迟一秒开始第一条路径的展示，给客户端切换界面的时间
    room.reviewStepTimer = Timer(const Duration(seconds: 1), () {
      if (room.reviewFlowToken != token) return;
      _showNextReviewStep(room, token);
    });
  }

  void _broadcastReviewProgress(RoomData room) {
    if (room.gamePhase != GamePhase.reviewing) return;
    final progress = ReviewProgressBroadcast(
      pathIndex: room.currentReviewPathIndex,
      stepIndex: room.currentReviewStepIndex,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.reviewProgressBroadcast,
      progress.encode(),
    );
  }

  /// 展示下一个复盘步骤
  void _showNextReviewStep(RoomData room, int token) {
    if (room.gamePhase != GamePhase.reviewing) return;
    if (room.reviewFlowToken != token) return;
    if (room.reviewSubPhase != ReviewSubPhase.showingSteps) return;

    final replay = room.lastReplayFile;
    if (replay == null) return;

    final tracks = replay['tracks'] as List<dynamic>;
    if (room.currentReviewPathIndex >= tracks.length) {
      room.reviewSubPhase = ReviewSubPhase.idle;
      _endGame(room);
      return;
    }

    final currentTrack = tracks[room.currentReviewPathIndex];
    final steps = currentTrack['steps'] as List<dynamic>;

    if (room.currentReviewStepIndex < steps.length) {
      // 步骤展示停留3秒，然后展示下一位
      room.currentReviewStepIndex++;

      _broadcastReviewProgress(room);

      room.reviewStepTimer?.cancel();
      room.reviewStepTimer = Timer(const Duration(seconds: 3), () {
        if (room.reviewFlowToken != token) return;
        _showNextReviewStep(room, token);
      });
    } else {
      // 当前路径所有步骤展示完毕，开始评分环节
      _startVoting(room, token);
    }
  }

  /// 开始评分环节（勾/叉）
  void _startVoting(RoomData room, int token) {
    if (room.gamePhase != GamePhase.reviewing) return;
    if (room.reviewFlowToken != token) return;
    if (room.reviewSubPhase == ReviewSubPhase.voting) return;

    room.reviewSubPhase = ReviewSubPhase.voting;
    room.reviewVotes.clear();
    room.phaseTimer?.cancel();
    room.reviewStepTimer?.cancel();
    room.reviewAdvanceTimer?.cancel();

    // 广播投票开始
    RoomBroadcaster.broadcast(
      room,
      MessageType.voteStartBroadcast,
      Uint8List(0),
    );

    this.log('开始路径评分', room: room.roomId, action: 'VOTE_START');

    // 10秒投票时间
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 10));
    room.phaseTimer = Timer(const Duration(seconds: 10), () {
      _onVotingEnd(room, token);
    });
  }

  /// 处理投票提交
  void handleVoteSubmit(
      Socket socket, ClientSession session, Uint8List payload) {
    final roomId = session.currentRoomId;
    if (roomId == null) return;
    final room = rooms[roomId];
    if (room == null || room.gamePhase != GamePhase.reviewing) return;

    try {
      final vote = VoteSubmit.decode(payload);
      room.reviewVotes[session.fingerprintHex!] = vote.isUp;

      // 广播投票结果（弹幕）
      final resultBroadcast =
          VoteResultBroadcast(username: session.username!, isUp: vote.isUp);
      RoomBroadcaster.broadcast(
        room,
        MessageType.voteResultBroadcast,
        resultBroadcast.encode(),
      );

      // 如果全员投票完成，提前结束
      if (room.reviewVotes.length >= room.members.length) {
        _onVotingEnd(room, room.reviewFlowToken);
      }
    } catch (e) {
      this.log('处理投票提交失败: $e');
    }
  }

  /// 投票结束
  void _onVotingEnd(RoomData room, int token) {
    if (room.gamePhase != GamePhase.reviewing) return;
    if (room.reviewFlowToken != token) return;
    if (room.reviewSubPhase != ReviewSubPhase.voting) return;

    // 结束投票只允许执行一次
    room.reviewSubPhase = ReviewSubPhase.favoriteSelecting;
    room.phaseTimer?.cancel();

    // 未投票成员自动视为叉，并广播弹幕（保证客户端能看到"自动提交"效果）
    if (room.reviewVotes.length < room.members.length) {
      for (final member in room.members) {
        final fp = member.fingerprintHex;
        if (room.reviewVotes.containsKey(fp)) continue;
        room.reviewVotes[fp] = false;
        final resultBroadcast =
            VoteResultBroadcast(username: member.username, isUp: false);
        RoomBroadcaster.broadcast(
          room,
          MessageType.voteResultBroadcast,
          resultBroadcast.encode(),
        );
      }
    }

    // 计算得分：每一勾加一分给第一棒
    final replay = room.lastReplayFile;
    if (replay == null) return;
    final tracks = replay['tracks'] as List<dynamic>;
    final currentTrack = tracks[room.currentReviewPathIndex];
    final originOwnerFp = currentTrack['originOwnerFp'] as String;

    int upVotes = 0;
    for (final vote in room.reviewVotes.values) {
      if (vote) upVotes++;
    }
    // 默认打叉逻辑：未投者视为叉，已经在reviewVotes记录中体现

    room.memberScores[originOwnerFp] =
        (room.memberScores[originOwnerFp] ?? 0) + upVotes;

    // 广播积分更新
    _broadcastScores(room);

    this.log('评分结束，第一棒 ${currentTrack['originOwnerName']} 获得 $upVotes 分',
        room: room.roomId, action: 'VOTE_END');

    // 进入展示所有画作让第一棒挑选最爱的环节
    _startFavoriteSelection(room, token);
  }

  /// 开始"最爱画作"选择
  void _startFavoriteSelection(RoomData room, int token) {
    if (room.gamePhase != GamePhase.reviewing) return;
    if (room.reviewFlowToken != token) return;
    if (room.reviewSubPhase != ReviewSubPhase.favoriteSelecting) return;

    room.phaseTimer?.cancel();
    room.reviewStepTimer?.cancel();
    room.reviewAdvanceTimer?.cancel();

    final replay = room.lastReplayFile;
    if (replay == null) return;
    final tracks = replay['tracks'] as List<dynamic>;
    final currentTrack = tracks[room.currentReviewPathIndex];
    final originOwnerName = (currentTrack['originOwnerName'] ?? '').toString();

    // 最爱选择：全员同步进入预览界面，但只有第一棒可以点击选择
    final start =
        FavoriteSelectionStartBroadcast(pickerUsername: originOwnerName);
    RoomBroadcaster.broadcast(
      room,
      MessageType.favoriteSelectionStart,
      start.encode(),
    );

    this.log('等待第一棒 ${currentTrack['originOwnerName']} 选择最爱画作',
        room: room.roomId, action: 'FAVORITE_START');

    // 15秒选择时间，超时自动跳过
    room.phaseTimer = Timer(const Duration(seconds: 15), () {
      // 超时：广播一个"无选择"结果，用于客户端立即关闭选择界面
      final result = FavoriteResultBroadcast(drawingIndex: 255);
      RoomBroadcaster.broadcast(
        room,
        MessageType.favoriteResultBroadcast,
        result.encode(),
      );
      _finishReviewPath(room, token);
    });
  }

  /// 处理最爱画作提交
  void handleFavoriteSubmit(
      Socket socket, ClientSession session, Uint8List payload) {
    final roomId = session.currentRoomId;
    if (roomId == null) return;
    final room = rooms[roomId];
    if (room == null || room.gamePhase != GamePhase.reviewing) return;
    if (room.reviewSubPhase != ReviewSubPhase.favoriteSelecting) return;

    final replay = room.lastReplayFile;
    if (replay == null) return;
    final tracks = replay['tracks'] as List<dynamic>;
    final currentTrack = tracks[room.currentReviewPathIndex];
    final originOwnerFp = currentTrack['originOwnerFp'] as String;

    // 校验权限：必须是当前路径的第一棒
    if (session.fingerprintHex != originOwnerFp) return;

    try {
      final submit = FavoriteSubmit.decode(payload);
      final steps = currentTrack['steps'] as List<dynamic>;
      if (submit.drawingIndex >= 0 && submit.drawingIndex < steps.length) {
        // 广播选择结果（用于客户端描边展示几秒）
        final result =
            FavoriteResultBroadcast(drawingIndex: submit.drawingIndex);
        RoomBroadcaster.broadcast(
          room,
          MessageType.favoriteResultBroadcast,
          result.encode(),
        );

        final chosenStep = steps[submit.drawingIndex];
        final drawerFp = chosenStep['drawerFp'] as String;

        // 被选中者加5分
        room.memberScores[drawerFp] = (room.memberScores[drawerFp] ?? 0) + 5;
        _broadcastScores(room);

        this.log('第一棒选择了 ${chosenStep['drawerName']} 的画作为最爱，加5分',
            room: room.roomId, action: 'FAVORITE_SUBMIT');
      }

      _finishReviewPath(room, room.reviewFlowToken);
    } catch (e) {
      this.log('处理最爱画作提交失败: $e');
    }
  }

  /// 完成当前路径的复盘，准备进入下一条或结束
  void finishReviewPath(RoomData room, int token) =>
      _finishReviewPath(room, token);

  void _finishReviewPath(RoomData room, int token) {
    if (room.gamePhase != GamePhase.reviewing) return;
    if (room.reviewFlowToken != token) return;
    if (room.reviewSubPhase == ReviewSubPhase.advancing) return;

    room.reviewSubPhase = ReviewSubPhase.advancing;
    room.phaseTimer?.cancel();
    room.reviewStepTimer?.cancel();
    room.reviewAdvanceTimer?.cancel();

    // 停留3秒展示选中结果
    room.reviewAdvanceTimer = Timer(const Duration(seconds: 3), () {
      if (room.reviewFlowToken != token) return;
      room.currentReviewPathIndex++;
      room.currentReviewStepIndex = 0;
      room.reviewSubPhase = ReviewSubPhase.showingSteps;

      _broadcastReviewProgress(room);

      _showNextReviewStep(room, token);
    });
  }

  /// 广播当前积分
  void _broadcastScores(RoomData room) {
    final scoreUpdate = ScoreUpdateBroadcast(scores: room.memberScores);
    RoomBroadcaster.broadcast(
      room,
      MessageType.scoreUpdateBroadcast,
      scoreUpdate.encode(),
    );
  }

  /// 游戏结束（最终结算后回到空闲）
  void _endGame(RoomData room) {
    room.gamePhase = GamePhase.ended;
    room.phaseTimer?.cancel();

    this.log('复盘结束，游戏进入最终状态', room: room.roomId, action: 'GAME_END');

    // 广播游戏结束（原逻辑，包含结果统计）
    final broadcast = GameEndBroadcast(
      message: '游戏已复盘结束',
      allResults: room.allRoundResults,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.gameEndBroadcast,
      broadcast.encode(),
    );

    final fpToName = {
      for (final m in room.members) m.fingerprintHex: m.username
    };
    final top3 = room.memberScores.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3List = top3
        .take(3)
        .map((e) => {
              'fingerprintHex': e.key,
              'username': fpToName[e.key] ?? '',
              'score': e.value,
            })
        .toList(growable: false);

    final endAtMs =
        DateTime.now().add(const Duration(seconds: 5)).millisecondsSinceEpoch;
    final podium = ScorePodiumBroadcast(
      roomId: room.roomId,
      endAtMs: endAtMs,
      top3: top3List,
    );
    RoomBroadcaster.broadcast(
      room,
      MessageType.scorePodiumBroadcast,
      podium.encode(),
    );

    Timer(const Duration(seconds: 5), () {
      if (!rooms.containsKey(room.roomId)) return;
      final current = rooms[room.roomId];
      if (current == null) return;

      final reset = GameResetBroadcast(roomId: current.roomId);
      RoomBroadcaster.broadcast(
        current,
        MessageType.gameResetBroadcast,
        reset.encode(),
      );

      current.resetGame();
      for (final member in current.members) {
        member.isReady = false;
      }
      broadcastRoomMembers(current.roomId);
    });
  }
}
