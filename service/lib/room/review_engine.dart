import 'dart:async';
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

/// 复盘引擎
/// 负责复盘阶段的状态机流程：步骤展示 → 投票 → 最爱选择 → 下一路径
class ReviewEngine {
  final LogCallback _log;

  ReviewEngine({required LogCallback log}) : _log = log;

  /// 进入复盘阶段
  void startReviewPhase(RoomData room) {
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

    _log('进入复盘阶段', room: room.roomId, action: 'REVIEW_START');

    broadcastReviewProgress(room);

    // 延迟一秒开始第一条路径的展示，给客户端切换界面的时间
    room.reviewStepTimer = Timer(const Duration(seconds: 1), () {
      if (room.reviewFlowToken != token) return;
      showNextReviewStep(room, token, null);
    });
  }

  /// 广播复盘进度
  void broadcastReviewProgress(RoomData room) {
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
  /// [onEndGame] 当所有路径展示完成时的回调，如果为 null 则不执行任何操作
  void showNextReviewStep(
      RoomData room, int token, void Function(RoomData)? onEndGame) {
    if (room.gamePhase != GamePhase.reviewing) return;
    if (room.reviewFlowToken != token) return;
    if (room.reviewSubPhase != ReviewSubPhase.showingSteps) return;

    final replay = room.lastReplayFile;
    if (replay == null) return;

    final tracks = replay['tracks'] as List<dynamic>;
    if (room.currentReviewPathIndex >= tracks.length) {
      room.reviewSubPhase = ReviewSubPhase.idle;
      if (onEndGame != null) onEndGame(room);
      return;
    }

    final currentTrack = tracks[room.currentReviewPathIndex];
    final steps = currentTrack['steps'] as List<dynamic>;

    if (room.currentReviewStepIndex < steps.length) {
      // 步骤展示停留3秒，然后展示下一位
      room.currentReviewStepIndex++;

      broadcastReviewProgress(room);

      room.reviewStepTimer?.cancel();
      room.reviewStepTimer = Timer(const Duration(seconds: 3), () {
        if (room.reviewFlowToken != token) return;
        showNextReviewStep(room, token, onEndGame);
      });
    } else {
      // 当前路径所有步骤展示完毕，开始评分环节
      startVoting(room, token);
    }
  }

  /// 开始评分环节（勾/叉）
  void startVoting(RoomData room, int token) {
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

    _log('开始路径评分', room: room.roomId, action: 'VOTE_START');

    // 10秒投票时间
    room.phaseEndAt = DateTime.now().add(const Duration(seconds: 10));
    room.phaseTimer = Timer(const Duration(seconds: 10), () {
      onVotingEnd(room, token);
    });
  }

  /// 处理投票提交
  ///
  /// [room] 房间数据
  /// [fingerprintHex] 投票者指纹
  /// [username] 投票者用户名
  /// [isUp] 是否勾（true=勾，false=叉）
  /// 返回是否全员投票完成
  bool handleVoteSubmit(
    RoomData room,
    String fingerprintHex,
    String username,
    bool isUp,
  ) {
    if (room.gamePhase != GamePhase.reviewing) return false;

    room.reviewVotes[fingerprintHex] = isUp;

    // 广播投票结果（弹幕）
    final resultBroadcast = VoteResultBroadcast(username: username, isUp: isUp);
    RoomBroadcaster.broadcast(
      room,
      MessageType.voteResultBroadcast,
      resultBroadcast.encode(),
    );

    // 如果全员投票完成，提前结束
    return room.reviewVotes.length >= room.members.length;
  }

  /// 投票结束
  void onVotingEnd(RoomData room, int token) {
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

    room.memberScores[originOwnerFp] =
        (room.memberScores[originOwnerFp] ?? 0) + upVotes;

    // 广播积分更新
    broadcastScores(room);

    _log('评分结束，第一棒 ${currentTrack['originOwnerName']} 获得 $upVotes 分',
        room: room.roomId, action: 'VOTE_END');

    // 进入展示所有画作让第一棒挑选最爱的环节
    startFavoriteSelection(room, token);
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

  /// 开始"最爱画作"选择
  void startFavoriteSelection(RoomData room, int token) {
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

    _log('等待第一棒 ${currentTrack['originOwnerName']} 选择最爱画作',
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
      finishReviewPath(room, token);
    });
  }

  /// 处理最爱画作提交
  ///
  /// [room] 房间数据
  /// [fingerprintHex] 提交者指纹
  /// [drawingIndex] 选择的画作索引
  /// 返回是否成功处理（权限验证通过且索引有效）
  bool handleFavoriteSubmit(
    RoomData room,
    String fingerprintHex,
    int drawingIndex,
  ) {
    if (room.gamePhase != GamePhase.reviewing) return false;
    if (room.reviewSubPhase != ReviewSubPhase.favoriteSelecting) return false;

    final replay = room.lastReplayFile;
    if (replay == null) return false;
    final tracks = replay['tracks'] as List<dynamic>;
    final currentTrack = tracks[room.currentReviewPathIndex];
    final originOwnerFp = currentTrack['originOwnerFp'] as String;

    // 校验权限：必须是当前路径的第一棒
    if (fingerprintHex != originOwnerFp) return false;

    final steps = currentTrack['steps'] as List<dynamic>;
    if (drawingIndex >= 0 && drawingIndex < steps.length) {
      // 广播选择结果（用于客户端描边展示几秒）
      final result = FavoriteResultBroadcast(drawingIndex: drawingIndex);
      RoomBroadcaster.broadcast(
        room,
        MessageType.favoriteResultBroadcast,
        result.encode(),
      );

      final chosenStep = steps[drawingIndex];
      final drawerFp = chosenStep['drawerFp'] as String;

      // 被选中者加5分
      room.memberScores[drawerFp] = (room.memberScores[drawerFp] ?? 0) + 5;
      broadcastScores(room);

      _log('第一棒选择了 ${chosenStep['drawerName']} 的画作为最爱，加5分',
          room: room.roomId, action: 'FAVORITE_SUBMIT');
      return true;
    }
    return false;
  }

  /// 完成当前路径的复盘，准备进入下一条或结束
  void finishReviewPath(RoomData room, int token) {
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

      broadcastReviewProgress(room);

      showNextReviewStep(room, token, null);
    });
  }
}
