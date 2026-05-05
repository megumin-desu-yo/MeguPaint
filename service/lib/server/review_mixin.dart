import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/protocol_handler.dart';
import '../room/room_data.dart';
import '../room/room_broadcaster.dart';
import '../room/client_session.dart';
import '../room/review_engine.dart';
import 'tcp_server_base.dart';

/// 复盘流程功能 Mixin
/// 包含：复盘确认、投票、最爱画作选择
mixin ReviewMixin on TcpServerBase {
  /// 复盘引擎实例（延迟初始化）
  ReviewEngine? _reviewEngine;

  ReviewEngine get reviewEngine {
    return _reviewEngine ??= ReviewEngine(log: log);
  }

  /// 处理复盘确认
  void handleReplayAck(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
    final roomId = session.currentRoomId;
    if (roomId == null) return;
    final room = rooms[roomId];
    if (room == null) return;
    if (!session.isAuthenticated || session.fingerprintHex == null) return;

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
        log('复盘ACK已收齐，开始复盘', room: room.roomId, action: 'REPLAY_ACK_ALL');
        startReviewPhase(room);
      }
    } catch (_) {
      // ignore
    }
  }

  /// 处理投票提交
  void handleVoteSubmit(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
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
        onVotingEnd(room, room.reviewFlowToken);
      }
    } catch (e) {
      log('处理投票提交失败: $e');
    }
  }

  /// 投票结束
  void onVotingEnd(RoomData room, int token) {
    if (room.gamePhase != GamePhase.reviewing) return;
    if (room.reviewFlowToken != token) return;
    if (room.reviewSubPhase != ReviewSubPhase.voting) return;

    room.reviewSubPhase = ReviewSubPhase.favoriteSelecting;
    room.phaseTimer?.cancel();

    // 未投票成员自动视为叉
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

    // 计算得分
    final replay = room.lastReplayFile;
    if (replay == null) return;
    final tracks = replay['tracks'] as List<dynamic>;
    final currentTrack = tracks[room.currentReviewPathIndex];
    final originOwnerFp = currentTrack['originOwnerFp'] as String;

    int upVotes = 0;
    for (final vote in room.reviewVotes.values) {
      if (vote) upVotes++;
    }

    room.memberScores[originOwnerFp] =
        (room.memberScores[originOwnerFp] ?? 0) + upVotes;

    broadcastScores(room);

    log('评分结束，第一棒 ${currentTrack['originOwnerName']} 获得 $upVotes 分',
        room: room.roomId, action: 'VOTE_END');

    // 进入最爱画作选择阶段
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 5));
    room.phaseTimer = Timer(const Duration(seconds: 5), () {
      if (room.reviewFlowToken != token) return;
      finishReviewPath(room, token);
    });
  }

  /// 处理最爱画作提交
  void handleFavoriteSubmit(
    Socket socket,
    ClientSession session,
    Uint8List payload,
  ) {
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
        // 广播选择结果
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
        broadcastScores(room);

        log('第一棒选择了 ${chosenStep['drawerName']} 的画作为最爱，加5分',
            room: room.roomId, action: 'FAVORITE_SUBMIT');
      }

      finishReviewPath(room, room.reviewFlowToken);
    } catch (e) {
      log('处理最爱画作提交失败: $e');
    }
  }

  /// 广播当前积分
  void broadcastScores(RoomData room) {
    final scoreUpdate = ScoreUpdateBroadcast(scores: room.memberScores);
    RoomBroadcaster.broadcast(
      room,
      MessageType.scoreUpdateBroadcast,
      scoreUpdate.encode(),
    );
  }

  /// 进入复盘阶段（子类实现）
  void startReviewPhase(RoomData room);

  /// 完成当前路径的复盘（子类实现）
  void finishReviewPath(RoomData room, int token);
}
