import 'dart:io';
import 'dart:typed_data';

import '../protocol/protocol_handler.dart';
import '../room/room_data.dart';
import '../room/room_broadcaster.dart';
import '../room/client_session.dart';
import '../room/relay_game_engine.dart';
import 'tcp_server_base.dart';

/// 游戏流程功能 Mixin
/// 包含：游戏开始、卡牌选择、绘画上传、猜测提交
mixin GameMixin on TcpServerBase {
  /// 游戏引擎实例（延迟初始化）
  RelayGameEngine? _gameEngine;

  RelayGameEngine get gameEngine {
    return _gameEngine ??= RelayGameEngine(log: log);
  }

  /// 处理游戏开始请求
  void handleGameStart(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    try {
      final roomId = session.currentRoomId;
      if (roomId == null) return;
      final room = rooms[roomId];
      if (room == null) return;

      if (session.fingerprintHex != room.ownerFingerprintHex) {
        log('非房主尝试发起游戏',
            username: session.username, action: 'GAME_START_DENIED');
        return;
      }

      if (room.gamePhase != GamePhase.idle) {
        log('游戏已在进行中', username: session.username, action: 'GAME_START_DENIED');
        return;
      }

      log('游戏开始',
          username: session.username, action: 'GAME_START', room: roomId);

      RoomBroadcaster.broadcast(room, MessageType.gameStartBroadcast, payload);

      room.lastReplayFile = null;
      room.resetGame();
      startNextRound(room);
    } catch (e) {
      log('处理游戏开始失败: $e',
          username: session.username, action: 'GAME_START_ERROR');
    }
  }

  /// 启动下一回合（子类实现具体逻辑）
  void startNextRound(RoomData room);

  /// 进入复盘阶段（子类实现具体逻辑）
  void startReviewPhase(RoomData room);

  /// 处理卡牌选择（词条翻牌 + 猜测阶段共用）
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
        gameEngine.handleWordCardPick(
            room, session.fingerprintHex!, session.username!, pick.cardIndex);
      } else if (room.gamePhase == GamePhase.cardPicking) {
        gameEngine.handleGuessCardPick(
            room, session.fingerprintHex!, session.username!, pick.cardIndex);
      }
    } catch (e) {
      log('处理卡牌选择失败: $e',
          username: session.username, action: 'CARD_PICK_ERROR');
    }
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

      room.memberDrawings[session.fingerprintHex!] = payload;
      log('绘画已上传 (${payload.length} bytes)',
          username: session.username, action: 'DRAWING_UPLOAD', room: roomId);
    } catch (e) {
      log('处理绘画上传失败: $e',
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

      log('绘画完成 (${room.drawingCompletedMembers.length}/${room.members.length})',
          username: session.username, action: 'DRAWING_COMPLETE', room: roomId);

      if (room.drawingCompletedMembers.length >= room.members.length) {
        onDrawingPhaseEnd(room);
      }
    } catch (e) {
      log('处理绘画完成失败: $e',
          username: session.username, action: 'DRAWING_COMPLETE_ERROR');
    }
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

      final allSubmitted = gameEngine.handleGuessSubmit(
        room,
        session.fingerprintHex!,
        session.username!,
        guess.cardIndex,
        guess.guess,
      );

      log('猜测提交: ${guess.guess}',
          username: session.username, action: 'GUESS_SUBMIT', room: roomId);

      if (allSubmitted) {
        onGuessPhaseEnd(room);
      }
    } catch (e) {
      log('处理猜测提交失败: $e',
          username: session.username, action: 'GUESS_SUBMIT_ERROR');
    }
  }

  /// 作画阶段结束（子类实现）
  void onDrawingPhaseEnd(RoomData room);

  /// 猜测阶段结束（子类实现）
  void onGuessPhaseEnd(RoomData room);
}
