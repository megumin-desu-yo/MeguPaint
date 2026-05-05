import 'dart:convert';
import 'dart:typed_data';

import 'room_data.dart';

/// 复盘数据构建器
/// 负责从房间历史数据生成复盘文件结构
class ReplayBuilder {
  /// 生成复盘文件数据
  ///
  /// [room] 房间数据（包含 roundHistory 等历史记录）
  /// 返回复盘文件数据结构，可序列化为 JSON
  static Map<String, dynamic> build(RoomData room) {
    final createdAt = DateTime.now().toIso8601String();
    final replayId = '${room.roomId}_$createdAt';
    final memberNameMap = <String, String>{
      for (final m in room.members) m.fingerprintHex: m.username,
    };

    final tracks = <Map<String, dynamic>>[];
    if (room.roundHistory.isNotEmpty) {
      final firstRound = room.roundHistory.first;
      final originWords =
          (firstRound['wordCards'] as List<dynamic>?)?.cast<String>() ?? [];
      final originOwnerFps =
          (firstRound['wordCardOwnerFps'] as List<dynamic>?)?.cast<String>() ??
              [];

      final count = originWords.length < originOwnerFps.length
          ? originWords.length
          : originOwnerFps.length;

      for (int i = 0; i < count; i++) {
        final originWord = originWords[i];
        final originOwnerFp = originOwnerFps[i];
        String ownerFp = originOwnerFp;
        final steps = <Map<String, dynamic>>[];

        for (int r = 0; r < room.roundHistory.length; r++) {
          final roundSnap = room.roundHistory[r].cast<String, dynamic>();
          final roundNo = roundSnap['round'] as int? ?? 0;
          final memberDrawWords =
              (roundSnap['memberDrawWords'] as Map?)?.cast<String, String>() ??
                  <String, String>{};
          final memberDrawings = (roundSnap['memberDrawings'] as Map?)
                  ?.cast<String, Uint8List>() ??
              <String, Uint8List>{};
          final guessResults =
              (roundSnap['guessResults'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};

          final drawerFp = _drawerFpFromOwner(roundSnap, ownerFp);
          if (drawerFp.isEmpty) break;

          final drawerName = memberNameMap[drawerFp] ?? '';
          final word = memberDrawWords[drawerFp] ?? '';
          final pngBytes = memberDrawings[drawerFp];
          final pngBase64 = pngBytes != null ? base64Encode(pngBytes) : '';

          String guesserFp = '';
          String guesserName = '';
          String guessText = '';

          for (final entry in guessResults.entries) {
            final gfp = entry.key;
            final data = entry.value;
            if (data is Map) {
              final targetFp = data['targetFingerprintHex']?.toString() ?? '';
              if (targetFp == drawerFp) {
                guesserFp = gfp;
                guesserName = memberNameMap[gfp] ?? '';
                guessText = data['guess']?.toString() ?? '';
                break;
              }
            }
          }

          steps.add({
            'round': roundNo,
            'ownerFp': ownerFp,
            'ownerName': memberNameMap[ownerFp] ?? '',
            'drawerFp': drawerFp,
            'drawerName': drawerName,
            'word': word,
            'pngBase64': pngBase64,
            'guesserFp': guesserFp,
            'guesserName': guesserName,
            'guessText': guessText,
          });

          if (guesserFp.isEmpty) break;
          if (r >= room.roundHistory.length - 1) break;
          ownerFp = drawerFp;
        }

        tracks.add({
          'originWord': originWord,
          'originOwnerFp': originOwnerFp,
          'originOwnerName': memberNameMap[originOwnerFp] ?? '',
          'steps': steps,
        });
      }
    }

    return {
      'replayId': replayId,
      'roomId': room.roomId,
      'createdAt': createdAt,
      'rounds': room.rounds,
      'members': room.members
          .map((m) => {
                'fp': m.fingerprintHex,
                'username': m.username,
              })
          .toList(growable: false),
      'tracks': tracks,
    };
  }

  static Map<String, dynamic> buildFromSnapshot(
    Map<String, dynamic> roomSnap,
  ) {
    final createdAt = DateTime.now().toIso8601String();
    final roomId = roomSnap['roomId']?.toString() ?? '';
    final replayId = '${roomId}_$createdAt';
    final rounds = roomSnap['rounds'] as int? ?? 0;

    final membersRaw = roomSnap['members'];
    final members = (membersRaw is List) ? membersRaw : const [];
    final memberNameMap = <String, String>{};
    for (final m in members) {
      if (m is Map) {
        final fp = m['fp']?.toString() ?? '';
        final username = m['username']?.toString() ?? '';
        if (fp.isNotEmpty) memberNameMap[fp] = username;
      }
    }

    final tracks = <Map<String, dynamic>>[];
    final historyRaw = roomSnap['roundHistory'];
    final history = (historyRaw is List) ? historyRaw : const [];

    if (history.isNotEmpty) {
      final firstRound = history.first;
      final originWords = (firstRound is Map && firstRound['wordCards'] is List)
          ? (firstRound['wordCards'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final originOwnerFps =
          (firstRound is Map && firstRound['wordCardOwnerFps'] is List)
              ? (firstRound['wordCardOwnerFps'] as List)
                  .map((e) => e.toString())
                  .toList()
              : <String>[];

      final count = originWords.length < originOwnerFps.length
          ? originWords.length
          : originOwnerFps.length;

      for (int i = 0; i < count; i++) {
        final originWord = originWords[i];
        final originOwnerFp = originOwnerFps[i];
        String ownerFp = originOwnerFp;
        final steps = <Map<String, dynamic>>[];

        for (int r = 0; r < history.length; r++) {
          final roundSnapRaw = history[r];
          if (roundSnapRaw is! Map) break;
          final roundSnap = roundSnapRaw.cast<String, dynamic>();
          final roundNo = roundSnap['round'] as int? ?? 0;
          final memberDrawWords = (roundSnap['memberDrawWords'] is Map)
              ? (roundSnap['memberDrawWords'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v.toString()))
              : <String, String>{};
          final memberDrawings = (roundSnap['memberDrawings'] is Map)
              ? (roundSnap['memberDrawings'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          final guessResults = (roundSnap['guessResults'] is Map)
              ? (roundSnap['guessResults'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};

          final drawerFp = _drawerFpFromOwnerSnapshot(roundSnap, ownerFp);
          if (drawerFp.isEmpty) break;

          final drawerName = memberNameMap[drawerFp] ?? '';
          final word = memberDrawWords[drawerFp] ?? '';
          final pngBytes = memberDrawings[drawerFp];
          final pngBase64 = pngBytes is Uint8List ? base64Encode(pngBytes) : '';

          String guesserFp = '';
          String guesserName = '';
          String guessText = '';

          for (final entry in guessResults.entries) {
            final gfp = entry.key;
            final data = entry.value;
            if (data is Map) {
              final targetFp = data['targetFingerprintHex']?.toString() ?? '';
              if (targetFp == drawerFp) {
                guesserFp = gfp;
                guesserName = memberNameMap[gfp] ?? '';
                guessText = data['guess']?.toString() ?? '';
                break;
              }
            }
          }

          steps.add({
            'round': roundNo,
            'ownerFp': ownerFp,
            'ownerName': memberNameMap[ownerFp] ?? '',
            'drawerFp': drawerFp,
            'drawerName': drawerName,
            'word': word,
            'pngBase64': pngBase64,
            'guesserFp': guesserFp,
            'guesserName': guesserName,
            'guessText': guessText,
          });

          if (guesserFp.isEmpty) break;
          if (r >= history.length - 1) break;
          ownerFp = drawerFp;
        }

        tracks.add({
          'originWord': originWord,
          'originOwnerFp': originOwnerFp,
          'originOwnerName': memberNameMap[originOwnerFp] ?? '',
          'steps': steps,
        });
      }
    }

    return {
      'replayId': replayId,
      'roomId': roomId,
      'createdAt': createdAt,
      'rounds': rounds,
      'members': members
          .whereType<Map>()
          .map((m) => {
                'fp': m['fp']?.toString() ?? '',
                'username': m['username']?.toString() ?? '',
              })
          .toList(growable: false),
      'tracks': tracks,
    };
  }

  /// 从回合快照中查找指定 owner 对应的绘画者 fingerprint
  static String _drawerFpFromOwner(
      Map<String, dynamic> roundSnap, String ownerFp) {
    final ownerFps =
        (roundSnap['wordCardOwnerFps'] as List<dynamic>?)?.cast<String>() ??
            <String>[];
    final picks = (roundSnap['wordCardPicks'] as Map?)?.cast<int, String>() ??
        <int, String>{};

    final idx = ownerFps.indexOf(ownerFp);
    if (idx < 0) return '';
    return picks[idx] ?? '';
  }

  static String _drawerFpFromOwnerSnapshot(
    Map<String, dynamic> roundSnap,
    String ownerFp,
  ) {
    final ownerFpsRaw = roundSnap['wordCardOwnerFps'];
    final ownerFps = (ownerFpsRaw is List)
        ? ownerFpsRaw.map((e) => e.toString()).toList(growable: false)
        : <String>[];

    final picksRaw = roundSnap['wordCardPicks'];
    final picks = <int, String>{};
    if (picksRaw is Map) {
      for (final entry in picksRaw.entries) {
        final k = int.tryParse(entry.key.toString());
        if (k == null) continue;
        picks[k] = entry.value?.toString() ?? '';
      }
    }

    final idx = ownerFps.indexOf(ownerFp);
    if (idx < 0) return '';
    return picks[idx] ?? '';
  }
}
