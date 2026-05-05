import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tcp_server.dart';

class AdminHttpServer {
  final TcpServer server;
  final InternetAddress address;
  final int port;
  final String? adminToken;

  HttpServer? _http;

  AdminHttpServer({
    required this.server,
    InternetAddress? address,
    this.port = 9090,
    this.adminToken,
  }) : address = address ?? InternetAddress.loopbackIPv4;

  bool get isRunning => _http != null;

  Future<void> start() async {
    if (_http != null) return;
    final http = await HttpServer.bind(address, port);
    _http = http;

    unawaited(
      http.forEach((req) async {
        try {
          await _handle(req);
        } catch (_) {
          try {
            req.response.statusCode = HttpStatus.internalServerError;
            req.response.headers.contentType = ContentType.html;
            req.response.write('<h1>500 Internal Server Error</h1>');
            await req.response.close();
          } catch (_) {}
        }
      }),
    );
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    if (http != null) {
      await http.close(force: true);
    }
  }

  Future<void> _handle(HttpRequest req) async {
    // Token 验证
    if (adminToken != null && adminToken!.isNotEmpty) {
      final queryToken = req.uri.queryParameters['token'];
      final authHeader = req.headers.value(HttpHeaders.authorizationHeader);
      String? bearerToken;
      if (authHeader != null && authHeader.startsWith('Bearer ')) {
        bearerToken = authHeader.substring(7);
      }

      if (queryToken != adminToken && bearerToken != adminToken) {
        req.response.statusCode = HttpStatus.unauthorized;
        req.response.headers.contentType = ContentType.html;
        req.response
            .write('<h1>401 Unauthorized</h1><p>Missing or invalid token.</p>');
        await req.response.close();
        return;
      }
    }

    if (req.method != 'GET') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
      return;
    }

    final path = req.uri.path;
    if (path == '/' || path == '') {
      req.response.statusCode = HttpStatus.found;
      final location =
          adminToken != null ? '/rooms?token=$adminToken' : '/rooms';
      req.response.headers.set(HttpHeaders.locationHeader, location);
      await req.response.close();
      return;
    }

    if (path == '/rooms') {
      await _renderRooms(req);
      return;
    }

    if (path == '/clients') {
      await _renderClients(req);
      return;
    }

    if (path == '/api/rooms') {
      await _renderRoomsJson(req);
      return;
    }

    if (path == '/api/clients') {
      await _renderClientsJson(req);
      return;
    }

    if (path == '/memory') {
      await _renderMemory(req);
      return;
    }

    if (path == '/api/memory') {
      await _renderMemoryJson(req);
      return;
    }

    if (path == '/perf') {
      await _renderPerf(req);
      return;
    }

    if (path == '/api/perf') {
      await _renderPerfJson(req);
      return;
    }

    if (path.startsWith('/rooms/') &&
        path.contains('/collab/layer/') &&
        path.endsWith('.png')) {
      await _renderCollabLayerPng(req, path);
      return;
    }

    if (path.startsWith('/rooms/') && path.endsWith('/collab/composite.png')) {
      await _renderCollabCompositePng(req, path);
      return;
    }

    if (path.startsWith('/rooms/') && path.contains('/png/')) {
      await _renderRoomPng(req, path);
      return;
    }

    if (path.startsWith('/rooms/') && path.endsWith('/replay')) {
      final roomId = path
          .substring('/rooms/'.length, path.length - '/replay'.length)
          .trim();
      await _renderRoomReplay(req, Uri.decodeComponent(roomId));
      return;
    }

    if (path.startsWith('/rooms/')) {
      final roomId = path.substring('/rooms/'.length);
      await _renderRoom(req, Uri.decodeComponent(roomId));
      return;
    }

    if (path.startsWith('/api/rooms/') && path.endsWith('/replay')) {
      final roomId = path
          .substring('/api/rooms/'.length, path.length - '/replay'.length)
          .trim();
      await _renderRoomReplayJson(req, Uri.decodeComponent(roomId));
      return;
    }

    if (path.startsWith('/api/rooms/')) {
      final roomId = path.substring('/api/rooms/'.length);
      await _renderRoomJson(req, Uri.decodeComponent(roomId));
      return;
    }

    req.response.statusCode = HttpStatus.notFound;
    req.response.headers.contentType = ContentType.html;
    req.response.write('<h1>404 Not Found</h1>');
    await req.response.close();
  }

  Future<void> _renderPerf(HttpRequest req) async {
    final snap = server.getPerfSnapshot();
    final tokenSuffix = adminToken != null ? '?token=$adminToken' : '';
    final sb = StringBuffer();
    sb.write('<!doctype html><html><head>');
    sb.write('<meta charset="utf-8">');
    sb.write('<meta http-equiv="refresh" content="2">');
    sb.write('<title>Perf</title>');
    sb.write('<style>');
    sb.write('body{font-family:Arial,Helvetica,sans-serif;margin:16px;}');
    sb.write('table{border-collapse:collapse;width:100%;margin-bottom:16px;}');
    sb.write('th,td{border:1px solid #ddd;padding:6px 10px;}');
    sb.write('th{background:#f6f6f6;text-align:left;}');
    sb.write('a{text-decoration:none;}');
    sb.write(
        '.kpi{display:inline-block;background:#f0f7ff;border:1px solid #cde;border-radius:8px;padding:10px 16px;margin:4px 6px 4px 0;text-align:center;min-width:90px;}');
    sb.write('.kpi .val{font-size:20px;font-weight:bold;}');
    sb.write('.kpi .lbl{font-size:11px;color:#666;}');
    sb.write('.warn{background:#fff3cd;} .crit{background:#fde8e8;}');
    sb.write('</style></head><body>');
    sb.write(
        '<div style="margin-bottom:8px;"><a href="/rooms$tokenSuffix">Rooms</a> | <a href="/memory$tokenSuffix">Memory</a> | <a href="/clients$tokenSuffix">Clients</a></div>');
    sb.write('<h2>Performance Dashboard</h2>');
    sb.write(
        '<div style="color:#999;font-size:12px;margin-bottom:12px;">snapshot: ${_esc('${snap['snapshotAt'] ?? ''}')}</div>');

    // ===== Event Loop Drift =====
    final drift = snap['eventLoopDrift'] as Map? ?? {};
    final driftP99 = drift['p99_us'] as int? ?? 0;
    final driftP50 = drift['p50_us'] as int? ?? 0;
    final driftMax = drift['max_us'] as int? ?? 0;
    final driftCount = drift['count'] as int? ?? 0;
    final driftCritClass =
        driftP99 > 200000 ? ' crit' : (driftP99 > 50000 ? ' warn' : '');
    sb.write('<h3>Event Loop Drift (last 60s)</h3>');
    sb.write('<div>');
    sb.write(
        '<div class="kpi$driftCritClass"><div class="val">${_fmtUs(driftP50)}</div><div class="lbl">p50</div></div>');
    sb.write(
        '<div class="kpi$driftCritClass"><div class="val">${_fmtUs(driftP99)}</div><div class="lbl">p99</div></div>');
    sb.write(
        '<div class="kpi$driftCritClass"><div class="val">${_fmtUs(driftMax)}</div><div class="lbl">max</div></div>');
    sb.write(
        '<div class="kpi"><div class="val">$driftCount</div><div class="lbl">samples</div></div>');
    sb.write('</div>');
    if (driftP99 > 200000) {
      sb.write(
          '<div style="color:#c00;font-weight:bold;margin:6px 0;">⚠️ p99 drift &gt; 200ms — event loop is blocking!</div>');
    } else if (driftP99 > 50000) {
      sb.write(
          '<div style="color:#b8860b;margin:6px 0;">⚠️ p99 drift &gt; 50ms — possible intermittent blocking</div>');
    } else {
      sb.write(
          '<div style="color:green;margin:6px 0;">✓ event loop healthy</div>');
    }

    // ===== Collab Delta Pipeline =====
    sb.write('<h3>Collab Delta Pipeline (last 60s, in microseconds)</h3>');
    sb.write('<table>');
    sb.write(
        '<tr><th>Stage</th><th>count</th><th>p50 (us)</th><th>p90 (us)</th><th>p99 (us)</th><th>max (us)</th><th>mean (us)</th><th>rate/s (1s)</th><th>rate/s (10s)</th></tr>');

    void _writeStageRow(String label, Map snap2, Map rateSnap) {
      final count = snap2['count'] as int? ?? 0;
      final p50 = snap2['p50_us'] as int? ?? 0;
      final p90 = snap2['p90_us'] as int? ?? 0;
      final p99 = snap2['p99_us'] as int? ?? 0;
      final maxV = snap2['max_us'] as int? ?? 0;
      final mean = snap2['mean_us'] as int? ?? 0;
      final r1 = rateSnap['rate_per_sec_1s'] as int? ?? 0;
      final r10 = rateSnap['rate_per_sec_10s'] as int? ?? 0;
      final rowClass =
          p99 > 50000 ? ' class="crit"' : (p99 > 10000 ? ' class="warn"' : '');
      sb.write(
          '<tr$rowClass><td><b>$label</b></td><td>$count</td><td>$p50</td><td>$p90</td><td>$p99</td><td>$maxV</td><td>$mean</td><td>$r1</td><td>$r10</td></tr>');
    }

    final decomp = snap['collabDecompress'] as Map? ?? {};
    final apply = snap['collabApply'] as Map? ?? {};
    final bcast = snap['collabBroadcast'] as Map? ?? {};
    final full = snap['collabFullPipeline'] as Map? ?? {};
    _writeStageRow('Decompress', decomp, decomp['rate'] as Map? ?? {});
    _writeStageRow('Apply (XOR)', apply, apply['rate'] as Map? ?? {});
    _writeStageRow('Broadcast', bcast, bcast['rate'] as Map? ?? {});
    _writeStageRow(
        'Full Pipeline', full, {'rate_per_sec_1s': 0, 'rate_per_sec_10s': 0});
    sb.write('</table>');

    // ===== Throughput details =====
    final decompBytes = decomp['bytesRate'] as Map? ?? {};
    final bcastBytes = bcast['bytesRate'] as Map? ?? {};
    final applyPx = apply['pixelsRate'] as Map? ?? {};
    sb.write('<h4>Throughput Details</h4>');
    sb.write(
        '<table><tr><th>Metric</th><th>last 1s</th><th>last 10s total</th><th>last 60s total</th></tr>');
    sb.write(
        '<tr><td>Decompress input bytes</td><td>${_fmtBytes(decompBytes['last1s'])}</td><td>${_fmtBytes(decompBytes['last10s'])}</td><td>${_fmtBytes(decompBytes['last60s'])}</td></tr>');
    sb.write(
        '<tr><td>Broadcast output bytes</td><td>${_fmtBytes(bcastBytes['last1s'])}</td><td>${_fmtBytes(bcastBytes['last10s'])}</td><td>${_fmtBytes(bcastBytes['last60s'])}</td></tr>');
    sb.write(
        '<tr><td>Apply pixels</td><td>${applyPx['last1s'] ?? 0}</td><td>${applyPx['last10s'] ?? 0}</td><td>${applyPx['last60s'] ?? 0}</td></tr>');
    sb.write('</table>');

    // ===== Sync Required =====
    final syncReq = snap['syncRequired'] as Map? ?? {};
    sb.write('<h3>SyncRequired (forced full sync)</h3>');
    sb.write(
        '<table><tr><th>last 1s</th><th>last 10s</th><th>last 60s</th></tr>');
    final syncCritClass =
        (syncReq['last10s'] as int? ?? 0) > 20 ? ' class="crit"' : '';
    sb.write(
        '<tr$syncCritClass><td>${syncReq['last1s'] ?? 0}</td><td>${syncReq['last10s'] ?? 0}</td><td>${syncReq['last60s'] ?? 0}</td></tr>');
    sb.write('</table>');

    // ===== Hot Rooms =====
    final hotRooms = snap['hotRooms'] as List? ?? [];
    sb.write('<h3>Hot Rooms (delta rate, last 10s)</h3>');
    sb.write(
        '<table><tr><th>roomId</th><th>deltas/s (1s)</th><th>deltas (10s)</th><th>deltas (60s)</th></tr>');
    if (hotRooms.isEmpty) {
      sb.write('<tr><td colspan="4">(none)</td></tr>');
    } else {
      for (final r in hotRooms) {
        final rm = r as Map;
        sb.write(
            '<tr><td>${_esc('${rm['roomId'] ?? ''}')}</td><td>${rm['last1s'] ?? 0}</td><td>${rm['last10s'] ?? 0}</td><td>${rm['last60s'] ?? 0}</td></tr>');
      }
    }
    sb.write('</table>');

    // ===== Message Rates =====
    final msgRates = snap['messageRates'] as List? ?? [];
    sb.write('<h3>Message Rates (last 10s, sorted by volume)</h3>');
    sb.write(
        '<table><tr><th>type</th><th>/s (1s)</th><th>/s (10s)</th><th>total (10s)</th><th>total (60s)</th></tr>');
    for (final m in msgRates) {
      final mm = m as Map;
      final t10 = mm['last10s'] as int? ?? 0;
      if (t10 == 0) continue;
      sb.write(
          '<tr><td><code>${_esc('${mm['type'] ?? ''}')}</code></td><td>${mm['rate_per_sec_1s'] ?? 0}</td><td>${mm['rate_per_sec_10s'] ?? 0}</td><td>$t10</td><td>${mm['last60s'] ?? 0}</td></tr>');
    }
    if (msgRates.isEmpty) sb.write('<tr><td colspan="5">(none)</td></tr>');
    sb.write('</table>');

    sb.write('</body></html>');
    req.response.headers.contentType = ContentType.html;
    req.response.write(sb.toString());
    await req.response.close();
  }

  Future<void> _renderPerfJson(HttpRequest req) async {
    final snap = server.getPerfSnapshot();
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(snap));
    await req.response.close();
  }

  String _fmtUs(int us) {
    if (us < 1000) return '${us}µs';
    if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)}ms';
    return '${(us / 1000000).toStringAsFixed(2)}s';
  }

  Future<void> _renderRooms(HttpRequest req) async {
    final rooms = server.getRoomsAdminSnapshot();
    final tokenSuffix = adminToken != null ? '?token=$adminToken' : '';

    final sb = StringBuffer();
    sb.write('<!doctype html>');
    sb.write('<html><head>');
    sb.write('<meta charset="utf-8">');
    sb.write('<meta http-equiv="refresh" content="1">');
    sb.write('<title>Rooms</title>');
    sb.write(
        '<style>body{font-family:Arial,Helvetica,sans-serif;margin:16px;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ddd;padding:8px;}th{background:#f6f6f6;text-align:left;}a{text-decoration:none;}</style>');
    sb.write('</head><body>');

    sb.write('<h2>Rooms</h2>');
    sb.write(
        '<div style="margin:6px 0 10px;"><a href="/clients$tokenSuffix">Clients</a> | <a href="/memory$tokenSuffix">Memory</a></div>');
    sb.write(
        '<div>connections: ${server.connectionCount} / rooms: ${server.roomCount}</div>');

    sb.write('<table>');
    sb.write(
        '<tr><th>roomId</th><th>name</th><th>phase</th><th>round</th><th>players</th><th>creator</th><th>owner</th><th>lexicon</th><th>timeLeft</th><th>history</th><th>pngMB</th></tr>');

    for (final r in rooms) {
      final roomId = _esc('${r['roomId'] ?? ''}');
      final roomIdUrl = Uri.encodeComponent('${r['roomId'] ?? ''}');
      final name = _esc('${r['roomName'] ?? ''}');
      final phase = _esc('${r['gamePhase'] ?? ''}');
      final round = _esc('${r['currentRound'] ?? ''}/${r['rounds'] ?? ''}');
      final players =
          _esc('${r['playerCount'] ?? ''}/${r['maxPlayers'] ?? ''}');
      final creator = _esc('${r['creatorUsername'] ?? ''}');
      final owner = _esc('${r['ownerUsername'] ?? ''}');
      final lexiconKey = _esc('${r['lexiconKey'] ?? ''}');
      final timeLeft = _esc('${r['phaseTimeLeftSec'] ?? ''}');
      final historyCount = _esc('${r['roundHistoryCount'] ?? ''}');
      final pngBytesRaw = r['roundHistoryPngBytes'];
      double pngMB = 0;
      if (pngBytesRaw is int) {
        pngMB = pngBytesRaw / 1024 / 1024;
      } else {
        final parsed = int.tryParse('${pngBytesRaw ?? ''}');
        if (parsed != null) pngMB = parsed / 1024 / 1024;
      }

      sb.write('<tr>');
      sb.write(
          '<td><a href="/rooms/$roomIdUrl$tokenSuffix">$roomId</a></td><td>$name</td><td>$phase</td><td>$round</td><td>$players</td><td>$creator</td><td>$owner</td><td>$lexiconKey</td><td>$timeLeft</td><td>$historyCount</td><td>${pngMB.toStringAsFixed(2)}</td>');
      sb.write('</tr>');
    }

    sb.write('</table>');

    sb.write('</body></html>');

    req.response.headers.contentType = ContentType.html;
    req.response.write(sb.toString());
    await req.response.close();
  }

  Future<void> _renderClients(HttpRequest req) async {
    final clients = server.getClientsAdminSnapshot();
    final tokenSuffix = adminToken != null ? '?token=$adminToken' : '';
    final idleTimeoutSec = server.authenticatedIdleTimeoutSeconds;
    final warnSec = (idleTimeoutSec * 0.8).floor();

    final sb = StringBuffer();
    sb.write('<!doctype html>');
    sb.write('<html><head>');
    sb.write('<meta charset="utf-8">');
    sb.write('<meta http-equiv="refresh" content="1">');
    sb.write('<title>Clients</title>');
    sb.write(
        '<style>body{font-family:Arial,Helvetica,sans-serif;margin:16px;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ddd;padding:8px;}th{background:#f6f6f6;text-align:left;}a{text-decoration:none;}code{background:#f6f6f6;padding:2px 4px;border:1px solid #eee;}</style>');
    sb.write('</head><body>');

    sb.write(
        '<div style="margin-bottom:8px;"><a href="/rooms$tokenSuffix">Rooms</a> | <a href="/memory$tokenSuffix">Memory</a></div>');
    sb.write('<h2>Clients</h2>');
    sb.write('<div>connections: ${server.connectionCount}</div>');

    sb.write('<table>');
    sb.write(
        '<tr><th>ip</th><th>port</th><th>auth</th><th>username</th><th>fingerprint</th><th>bufferBytes</th><th>idleSec</th><th>serverIdleTimeoutSec</th><th>lastActiveAt</th><th>connectedAt</th><th>room</th></tr>');

    for (final c in clients) {
      final ip = _esc('${c['ip'] ?? ''}');
      final port = _esc('${c['remotePort'] ?? ''}');
      final auth = c['isAuthenticated'] == true ? 'yes' : 'no';
      final username = _esc('${c['username'] ?? ''}');
      final fp = _esc('${c['fingerprintHex'] ?? ''}');
      final idle = _esc('${c['idleSeconds'] ?? ''}');
      final lastActiveAt = _esc('${c['lastActiveAt'] ?? ''}');
      final connectedAt = _esc('${c['connectedAt'] ?? ''}');
      final roomId = _esc('${c['roomId'] ?? ''}');
      final roomName = _esc('${c['roomName'] ?? ''}');
      final room = roomId.isEmpty ? '' : '$roomName ($roomId)';

      final idleSec = int.tryParse('${c['idleSeconds'] ?? ''}') ?? 0;
      final needWarn = idleTimeoutSec > 0 && idleSec >= warnSec;
      final rowStyle = needWarn ? ' style="background:#fff1f0"' : '';

      sb.write('<tr$rowStyle>');
      sb.write(
          '<td>$ip</td><td>$port</td><td>$auth</td><td>$username</td><td><code>$fp</code></td><td>${_esc('${c['bufferBytes'] ?? '0'}')}</td><td>$idle</td><td>$idleTimeoutSec</td><td><code>$lastActiveAt</code></td><td><code>$connectedAt</code></td><td>${_esc(room)}</td>');
      sb.write('</tr>');
    }
    if (clients.isEmpty) {
      sb.write('<tr><td colspan="11">(empty)</td></tr>');
    }
    sb.write('</table>');

    sb.write('</body></html>');

    req.response.headers.contentType = ContentType.html;
    req.response.write(sb.toString());
    await req.response.close();
  }

  Future<void> _renderRoom(HttpRequest req, String roomIdRaw) async {
    final roomId = roomIdRaw.trim();
    final snap = server.getRoomAdminSnapshot(roomId);

    if (snap == null) {
      req.response.statusCode = HttpStatus.notFound;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<h1>404 Not Found</h1>');
      await req.response.close();
      return;
    }

    final tokenSuffix = adminToken != null ? '?token=$adminToken' : '';
    final roomIdUrl = Uri.encodeComponent(roomId);

    final sb = StringBuffer();
    sb.write('<!doctype html>');
    sb.write('<html><head>');
    sb.write('<meta charset="utf-8">');
    sb.write('<meta http-equiv="refresh" content="1">');
    sb.write('<title>Room ${_esc(roomId)}</title>');
    sb.write(
        '<style>body{font-family:Arial,Helvetica,sans-serif;margin:16px;}a{text-decoration:none;}h2{margin:8px 0 16px;}h3{margin:18px 0 8px;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ddd;padding:8px;}th{background:#f6f6f6;text-align:left;}code{background:#f6f6f6;padding:2px 4px;border:1px solid #eee;}pre{background:#f6f6f6;padding:12px;border:1px solid #ddd;overflow:auto;}</style>');
    sb.write('</head><body>');

    sb.write('<div><a href="/rooms$tokenSuffix">Back</a></div>');
    sb.write('<h2>Room ${_esc(roomId)}</h2>');

    sb.write('<div style="margin:8px 0 12px;">');
    final replayId = _esc('${snap['replayId'] ?? ''}');
    final replayTrackCount = _esc('${snap['replayTrackCount'] ?? ''}');
    if (replayId.isNotEmpty) {
      final replayUrl = adminToken != null
          ? '/rooms/$roomIdUrl/replay?token=$adminToken'
          : '/rooms/$roomIdUrl/replay';
      sb.write(
          '<a href="$replayUrl"><b>Replay</b></a> <span style="color:#666">($replayTrackCount tracks)</span>');
    } else {
      sb.write('<span style="color:#666"><i>(No replay generated)</i></span>');
    }
    sb.write('</div>');

    final roomName = _esc('${snap['roomName'] ?? ''}');
    final phase = _esc('${snap['gamePhase'] ?? ''}');
    final round = _esc('${snap['currentRound'] ?? ''}/${snap['rounds'] ?? ''}');
    final timeLeft = _esc('${snap['phaseTimeLeftSec'] ?? ''}');
    final owner = _esc('${snap['ownerUsername'] ?? ''}');
    final creator = _esc('${snap['creatorUsername'] ?? ''}');
    final lexiconKey = _esc('${snap['lexiconKey'] ?? ''}');
    final lexiconLoaded = snap['lexiconLoaded'] == true ? 'yes' : 'no';
    final historyCount = _esc('${snap['roundHistoryCount'] ?? ''}');
    final pngMB = _esc('${snap['roundHistoryPngMB'] ?? ''}');

    sb.write('<h3>Room Info</h3>');
    sb.write('<table>');
    sb.write('<tr><th>name</th><td>$roomName</td></tr>');
    sb.write('<tr><th>phase</th><td><code>$phase</code></td></tr>');
    sb.write('<tr><th>round</th><td>$round</td></tr>');
    sb.write('<tr><th>timeLeftSec</th><td>$timeLeft</td></tr>');
    sb.write('<tr><th>creator</th><td>$creator</td></tr>');
    sb.write('<tr><th>owner</th><td>$owner</td></tr>');
    sb.write(
        '<tr><th>lexicon</th><td><code>$lexiconKey</code> (loaded: $lexiconLoaded)</td></tr>');
    sb.write('</table>');

    // 协同房间额外部分
    final roomTypeCode = snap['roomTypeCode'];
    if (roomTypeCode == 0x02) {
      final cw = snap['canvasWidth'] ?? 0;
      final ch = snap['canvasHeight'] ?? 0;
      final epoch = snap['collabEpoch'] ?? 0;
      final compositeUrl = snap['collabCompositeUrl'];
      final collabLayers = (snap['collabLayers'] is List)
          ? (snap['collabLayers'] as List)
          : const [];

      sb.write('<h3>Collab Canvas</h3>');
      sb.write('<table>');
      sb.write('<tr><th>canvas</th><td>${_esc('${cw}x$ch')}</td></tr>');
      sb.write('<tr><th>epoch</th><td>$epoch</td></tr>');
      sb.write('<tr><th>layers</th><td>${collabLayers.length}</td></tr>');
      if (compositeUrl != null) {
        final compositeUrlFull = adminToken != null
            ? '${_esc(compositeUrl.toString())}?token=$adminToken'
            : _esc(compositeUrl.toString());
        sb.write(
            '<tr><th>composite</th><td><a href="$compositeUrlFull" target="_blank"><img src="$compositeUrlFull" style="max-width:480px;max-height:270px;border:1px solid #ddd;background:#eee" /></a></td></tr>');
      }
      sb.write('</table>');

      if (collabLayers.isNotEmpty) {
        sb.write('<h3>Layers</h3>');
        sb.write('<table>');
        sb.write(
            '<tr><th>#</th><th>name</th><th>owner</th><th>vis</th><th>lock</th><th>opacity</th><th>rev</th><th>rgba</th><th>preview</th></tr>');
        for (int li = 0; li < collabLayers.length; li++) {
          final l = collabLayers[li];
          if (l is! Map) continue;
          final lname = _esc('${l['name'] ?? ''}');
          final owner = _esc('${l['ownerId'] ?? ''}');
          final vis = l['isVisible'] == true ? 'yes' : 'no';
          final lock = l['isLocked'] == true ? 'yes' : 'no';
          final opacity = l['opacity']?.toString() ?? '1.0';
          final rev = l['rev']?.toString() ?? '0';
          final rgbaKb =
              ((l['rgbaBytes'] as int? ?? 0) / 1024).toStringAsFixed(0);
          final previewPath = l['previewUrl']?.toString() ?? '';
          final previewUrl = previewPath.isEmpty
              ? ''
              : adminToken != null
                  ? '$previewPath?token=$adminToken'
                  : previewPath;
          final ownerLabel =
              owner.isEmpty ? '<i style="color:#999">public</i>' : owner;
          sb.write('<tr>');
          sb.write('<td>${li + 1}</td>');
          sb.write('<td>$lname</td>');
          sb.write('<td>$ownerLabel</td>');
          sb.write('<td>$vis</td>');
          sb.write('<td>$lock</td>');
          sb.write('<td>$opacity</td>');
          sb.write('<td>$rev</td>');
          sb.write('<td>${rgbaKb}KB</td>');
          sb.write(previewUrl.isEmpty
              ? '<td><i style="color:#999">(empty)</i></td>'
              : '<td><a href="${_esc(previewUrl)}" target="_blank"><img src="${_esc(previewUrl)}" style="max-width:160px;max-height:90px;border:1px solid #ddd;background:#eee" /></a></td>');
          sb.write('</tr>');
        }
        sb.write('</table>');
      }
    }

    sb.write('<h3>Counts</h3>');
    sb.write('<table>');
    sb.write(
        '<tr><th>members</th><td>${_esc('${snap['memberCount'] ?? ''}')}/${_esc('${snap['maxPlayers'] ?? ''}')}</td></tr>');
    sb.write(
        '<tr><th>wordCards</th><td>${_esc('${snap['wordCardsCount'] ?? ''}')}</td></tr>');
    sb.write(
        '<tr><th>guessCards</th><td>${_esc('${snap['guessCardsCount'] ?? ''}')}</td></tr>');
    sb.write(
        '<tr><th>drawingUploaded</th><td>${_esc('${snap['drawingUploadedCount'] ?? ''}')}</td></tr>');
    sb.write(
        '<tr><th>drawingCompleted</th><td>${_esc('${snap['drawingCompletedCount'] ?? ''}')}</td></tr>');
    sb.write(
        '<tr><th>guessResults</th><td>${_esc('${snap['guessResultsCount'] ?? ''}')}</td></tr>');
    sb.write(
        '<tr><th>lastRoundGuesses</th><td>${_esc('${snap['lastRoundGuessesCount'] ?? ''}')}</td></tr>');
    sb.write(
        '<tr><th>allRoundResults</th><td>${_esc('${snap['allRoundResultsCount'] ?? ''}')}</td></tr>');
    sb.write('<tr><th>roundHistory</th><td>$historyCount</td></tr>');
    sb.write('<tr><th>roundHistoryPngMB</th><td>$pngMB</td></tr>');
    sb.write('</table>');

    sb.write('<h3>Members</h3>');
    sb.write('<table>');
    sb.write(
        '<tr><th>#</th><th>username</th><th>fingerprint</th><th>ready</th></tr>');
    final members =
        (snap['members'] is List) ? (snap['members'] as List) : const [];
    for (int i = 0; i < members.length; i++) {
      final m = members[i];
      if (m is Map) {
        final username = _esc('${m['username'] ?? ''}');
        final fp = _esc('${m['fingerprintHex'] ?? ''}');
        final ready = m['isReady'] == true ? 'yes' : 'no';
        sb.write(
            '<tr><td>${i + 1}</td><td>$username</td><td><code>$fp</code></td><td>$ready</td></tr>');
      }
    }
    if (members.isEmpty) {
      sb.write('<tr><td colspan="4">(empty)</td></tr>');
    }
    sb.write('</table>');

    sb.write('<h3>Word Picks</h3>');
    sb.write('<table>');
    sb.write('<tr><th>cardIndex</th><th>pickerFingerprint</th></tr>');
    final wordPicks = (snap['wordCardPicks'] is Map)
        ? (snap['wordCardPicks'] as Map)
        : const {};
    if (wordPicks.isEmpty) {
      sb.write('<tr><td colspan="2">(empty)</td></tr>');
    } else {
      final keys = wordPicks.keys.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      for (final k in keys) {
        sb.write(
            '<tr><td>${_esc(k.toString())}</td><td><code>${_esc('${wordPicks[k] ?? ''}')}</code></td></tr>');
      }
    }
    sb.write('</table>');

    sb.write('<h3>Guess Card Picks</h3>');
    sb.write('<table>');
    sb.write('<tr><th>cardIndex</th><th>pickerFingerprint</th></tr>');
    final guessPicks = (snap['guessCardPicks'] is Map)
        ? (snap['guessCardPicks'] as Map)
        : const {};
    if (guessPicks.isEmpty) {
      sb.write('<tr><td colspan="2">(empty)</td></tr>');
    } else {
      final keys = guessPicks.keys.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
      for (final k in keys) {
        sb.write(
            '<tr><td>${_esc(k.toString())}</td><td><code>${_esc('${guessPicks[k] ?? ''}')}</code></td></tr>');
      }
    }
    sb.write('</table>');

    sb.write('<h3>Round History (last 20)</h3>');
    final history = (snap['roundHistory'] is List)
        ? (snap['roundHistory'] as List)
        : const [];
    if (history.isEmpty) {
      sb.write('<p><i>(empty)</i></p>');
    } else {
      for (final h in history) {
        if (h is! Map) continue;
        final r = _esc('${h['round'] ?? ''}');
        final archivedAt = _esc('${h['archivedAt'] ?? ''}');
        sb.write(
            '<h4>Round $r <span style="color:#666;font-weight:normal">$archivedAt</span></h4>');

        final submitHistory = (h['guessSubmitHistory'] is List)
            ? (h['guessSubmitHistory'] as List)
            : const [];
        if (submitHistory.isNotEmpty) {
          sb.write('<h5>Guess Submit History</h5>');
          sb.write('<table>');
          sb.write(
              '<tr><th>player</th><th>fingerprint</th><th>count</th><th>submits</th></tr>');
          for (final sh in submitHistory) {
            if (sh is! Map) continue;
            final username = _esc('${sh['username'] ?? ''}');
            final fp = _esc('${sh['fingerprintHex'] ?? ''}');
            final count = _esc('${sh['submitCount'] ?? ''}');
            final submits =
                (sh['submits'] is List) ? (sh['submits'] as List) : const [];
            final sb2 = StringBuffer();
            for (final s in submits) {
              if (s is! Map) continue;
              final at = _esc('${s['at'] ?? ''}');
              final guess = _esc('${s['guess'] ?? ''}');
              final cardIndex = _esc('${s['cardIndex'] ?? ''}');
              final targetUser = _esc('${s['targetUsername'] ?? ''}');
              sb2.write(
                  '<div><code>$at</code> #$cardIndex → <b>$guess</b> <span style="color:#666">($targetUser)</span></div>');
            }
            sb.write('<tr>');
            sb.write('<td>$username</td>');
            sb.write('<td><code>$fp</code></td>');
            sb.write('<td>$count</td>');
            sb.write('<td>${sb2.toString()}</td>');
            sb.write('</tr>');
          }
          sb.write('</table>');
        }

        final drawings =
            (h['drawings'] is List) ? (h['drawings'] as List) : const [];
        if (drawings.isEmpty) {
          sb.write('<div>(no drawings)</div>');
        } else {
          sb.write('<table>');
          sb.write(
              '<tr><th>player</th><th>fingerprint</th><th>pngBytes</th><th>preview</th></tr>');
          for (final d in drawings) {
            if (d is! Map) continue;
            final username = _esc('${d['username'] ?? ''}');
            final fp = _esc('${d['fingerprintHex'] ?? ''}');
            final bytes = _esc('${d['pngBytes'] ?? ''}');
            final path = '${d['pngUrlPath'] ?? ''}';
            final url = adminToken != null ? '$path?token=$adminToken' : path;
            sb.write('<tr>');
            sb.write('<td>$username</td>');
            sb.write('<td><code>$fp</code></td>');
            sb.write('<td>$bytes</td>');
            sb.write(
                '<td><a href="${_esc(url)}" target="_blank"><img src="${_esc(url)}" style="max-width:160px;max-height:90px;border:1px solid #ddd" /></a></td>');
            sb.write('</tr>');
          }
          sb.write('</table>');
        }
      }
    }

    sb.write('<h3>Lexicon Content</h3>');
    final lexiconJson = snap['lexiconJson'];
    if (lexiconJson != null && lexiconJson.toString().isNotEmpty) {
      String displayedLexicon = lexiconJson.toString();
      try {
        final List<dynamic> words = jsonDecode(displayedLexicon);
        displayedLexicon = words.join(',\n');
      } catch (_) {
        // 如果不是 JSON 数组，尝试简单的字符串替换作为退路
        displayedLexicon = displayedLexicon.replaceAll(',', ',\n');
      }
      sb.write('<pre>${_esc(displayedLexicon)}</pre>');
    } else {
      sb.write('<p><i>(No lexicon uploaded)</i></p>');
    }

    sb.write('<h3>Raw Snapshot</h3>');
    final pretty = const JsonEncoder.withIndent('  ').convert(snap);
    sb.write('<pre>${_esc(pretty)}</pre>');

    sb.write('</body></html>');

    req.response.headers.contentType = ContentType.html;
    req.response.write(sb.toString());
    await req.response.close();
  }

  String _fmtBytes(dynamic v) {
    final bytes = (v is int) ? v : 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  Future<void> _renderMemory(HttpRequest req) async {
    final snap = server.getMemoryAdminSnapshot();
    final tokenSuffix = adminToken != null ? '?token=$adminToken' : '';
    final sb = StringBuffer();
    sb.write('<!doctype html>');
    sb.write('<html><head>');
    sb.write('<meta charset="utf-8">');
    sb.write('<meta http-equiv="refresh" content="3">');
    sb.write('<title>Memory</title>');
    sb.write(
        '<style>body{font-family:Arial,Helvetica,sans-serif;margin:16px;}table{border-collapse:collapse;width:100%;margin-bottom:20px;}th,td{border:1px solid #ddd;padding:8px;}th{background:#f6f6f6;text-align:left;}a{text-decoration:none;}.kpi{display:inline-block;background:#f0f7ff;border:1px solid #cde;border-radius:8px;padding:12px 20px;margin:6px 8px 6px 0;text-align:center;}.kpi .val{font-size:24px;font-weight:bold;}.kpi .lbl{font-size:12px;color:#666;}</style>');
    sb.write('</head><body>');

    sb.write(
        '<div style="margin-bottom:8px;"><a href="/rooms$tokenSuffix">Rooms</a> | <a href="/clients$tokenSuffix">Clients</a></div>');
    sb.write('<h2>Memory Overview</h2>');

    // KPI cards
    final rss = snap['processRssMB'] ?? '?';
    final clientBuf = _fmtBytes(snap['clients']?['totalBufferBytes']);
    final roomsTotal = snap['roomsTotal'] as Map<String, dynamic>? ?? {};
    final drawPng = _fmtBytes(roomsTotal['memberDrawingsBytes']);
    final histPng = _fmtBytes(roomsTotal['roundHistoryPngBytes']);
    final replayJson = _fmtBytes(roomsTotal['replayJsonBytes']);
    final collabRgba = _fmtBytes(roomsTotal['collabLayersRgbaBytes']);
    final roomTotal = _fmtBytes(roomsTotal['totalBytes']);

    sb.write('<div>');
    sb.write(
        '<div class="kpi"><div class="val">$rss MB</div><div class="lbl">Process RSS</div></div>');
    sb.write(
        '<div class="kpi"><div class="val">$clientBuf</div><div class="lbl">Client Buffers</div></div>');
    sb.write(
        '<div class="kpi"><div class="val">$drawPng</div><div class="lbl">Current Drawings</div></div>');
    sb.write(
        '<div class="kpi"><div class="val">$histPng</div><div class="lbl">History PNGs</div></div>');
    sb.write(
        '<div class="kpi"><div class="val">$replayJson</div><div class="lbl">Replay JSONs</div></div>');
    sb.write(
        '<div class="kpi"><div class="val">$collabRgba</div><div class="lbl">Collab RGBA</div></div>');
    sb.write(
        '<div class="kpi"><div class="val">$roomTotal</div><div class="lbl">Rooms Total</div></div>');
    sb.write('</div>');

    // Connections summary
    final clientsSnap = snap['clients'] as Map<String, dynamic>? ?? {};
    sb.write(
        '<div style="margin:10px 0;">Connections: ${snap['connections']} (auth: ${clientsSnap['authenticatedCount']}, pre-auth: ${clientsSnap['preAuthCount']})</div>');

    // Room memory breakdown
    sb.write('<h3>Room Memory Breakdown</h3>');
    sb.write('<table>');
    sb.write(
        '<tr><th>roomId</th><th>name</th><th>phase</th><th>players</th><th>drawings</th><th>history PNG</th><th>replay JSON</th><th>collab RGBA</th><th>total</th></tr>');
    final roomBreakdown = (snap['roomBreakdown'] as List<dynamic>?) ?? [];
    for (final r in roomBreakdown) {
      final rm = r as Map<String, dynamic>;
      sb.write('<tr>');
      sb.write('<td>${_esc('${rm['roomId']}')}</td>');
      sb.write('<td>${_esc('${rm['roomName']}')}</td>');
      sb.write('<td>${_esc('${rm['gamePhase']}')}</td>');
      sb.write('<td>${rm['playerCount']}</td>');
      sb.write('<td>${_fmtBytes(rm['memberDrawingsBytes'])}</td>');
      sb.write('<td>${_fmtBytes(rm['roundHistoryPngBytes'])}</td>');
      sb.write('<td>${_fmtBytes(rm['replayJsonBytes'])}</td>');
      sb.write('<td>${_fmtBytes(rm['collabLayersRgbaBytes'])}</td>');
      sb.write('<td>${_fmtBytes(rm['totalBytes'])}</td>');
      sb.write('</tr>');

      final layers = (rm['collabLayers'] is List)
          ? (rm['collabLayers'] as List)
          : const [];
      if (layers.isNotEmpty) {
        sb.write('<tr><td colspan="9">');
        sb.write(
            '<div style="margin:6px 0 0;color:#666;font-size:12px;">Collab Layers</div>');
        sb.write('<table style="margin-top:6px;">');
        sb.write(
            '<tr><th>#</th><th>layerId</th><th>name</th><th>owner</th><th>rgbaBytes</th></tr>');
        for (int i = 0; i < layers.length; i++) {
          final l = layers[i];
          if (l is! Map) continue;
          final layerId = _esc('${l['layerId'] ?? ''}');
          final name = _esc('${l['name'] ?? ''}');
          final owner = _esc('${l['ownerId'] ?? ''}');
          final rgbaBytes = l['rgbaBytes'];
          sb.write('<tr>');
          sb.write('<td>${i + 1}</td>');
          sb.write('<td><code>$layerId</code></td>');
          sb.write('<td>$name</td>');
          sb.write(owner.isEmpty
              ? '<td><i style="color:#999">public</i></td>'
              : '<td>$owner</td>');
          sb.write('<td>${_fmtBytes(rgbaBytes)}</td>');
          sb.write('</tr>');
        }
        sb.write('</table>');
        sb.write('</td></tr>');
      }
    }
    if (roomBreakdown.isEmpty) {
      sb.write('<tr><td colspan="9">(no rooms)</td></tr>');
    }
    sb.write('</table>');

    // Client buffer TopN
    sb.write('<h3>Client Buffer Top 20</h3>');
    sb.write('<table>');
    sb.write(
        '<tr><th>ip</th><th>username</th><th>fingerprint</th><th>auth</th><th>bufferBytes</th></tr>');
    final bufferTop = (clientsSnap['bufferTop'] as List<dynamic>?) ?? [];
    for (final c in bufferTop) {
      final cm = c as Map<String, dynamic>;
      sb.write('<tr>');
      sb.write('<td>${_esc('${cm['ip'] ?? ''}')}</td>');
      sb.write('<td>${_esc('${cm['username'] ?? ''}')}</td>');
      sb.write('<td>${_esc('${cm['fingerprintHex'] ?? ''}')}</td>');
      sb.write('<td>${cm['isAuthenticated'] == true ? 'yes' : 'no'}</td>');
      sb.write('<td>${_fmtBytes(cm['bufferBytes'])}</td>');
      sb.write('</tr>');
    }
    if (bufferTop.isEmpty) {
      sb.write('<tr><td colspan="5">(no clients)</td></tr>');
    }
    sb.write('</table>');

    sb.write(
        '<div style="color:#999;font-size:12px;">snapshot: ${snap['now']}</div>');
    sb.write('</body></html>');

    req.response.headers.contentType = ContentType.html;
    req.response.write(sb.toString());
    await req.response.close();
  }

  Future<void> _renderMemoryJson(HttpRequest req) async {
    final snap = server.getMemoryAdminSnapshot();
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(snap));
    await req.response.close();
  }

  Future<void> _renderRoomsJson(HttpRequest req) async {
    final rooms = server.getRoomsAdminSnapshot();
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(rooms));
    await req.response.close();
  }

  Future<void> _renderClientsJson(HttpRequest req) async {
    final clients = server.getClientsAdminSnapshot();
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(clients));
    await req.response.close();
  }

  Future<void> _renderRoomJson(HttpRequest req, String roomId) async {
    final snap = server.getRoomAdminSnapshot(roomId.trim());
    if (snap == null) {
      req.response.statusCode = HttpStatus.notFound;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': 'room not found'}));
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(snap));
    await req.response.close();
  }

  Future<void> _renderRoomReplayJson(HttpRequest req, String roomId) async {
    final snap = server.getRoomAdminSnapshot(roomId.trim());
    if (snap == null) {
      req.response.statusCode = HttpStatus.notFound;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': 'room not found'}));
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(snap['lastReplayFile']));
    await req.response.close();
  }

  Future<void> _renderRoomReplay(HttpRequest req, String roomIdRaw) async {
    final roomId = roomIdRaw.trim();
    final snap = server.getRoomAdminSnapshot(roomId);

    if (snap == null) {
      req.response.statusCode = HttpStatus.notFound;
      req.response.headers.contentType = ContentType.html;
      req.response.write('<h1>404 Not Found</h1>');
      await req.response.close();
      return;
    }

    final tokenSuffix = adminToken != null ? '?token=$adminToken' : '';
    final roomIdUrl = Uri.encodeComponent(roomId);
    final sb = StringBuffer();
    sb.write('<!doctype html>');
    sb.write('<html><head>');
    sb.write('<meta charset="utf-8">');
    sb.write('<meta http-equiv="refresh" content="1">');
    sb.write('<title>Replay ${_esc(roomId)}</title>');
    sb.write(
        '<style>body{font-family:Arial,Helvetica,sans-serif;margin:16px;}a{text-decoration:none;}h2{margin:8px 0 16px;}h3{margin:18px 0 8px;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ddd;padding:8px;vertical-align:top;}th{background:#f6f6f6;text-align:left;}code{background:#f6f6f6;padding:2px 4px;border:1px solid #eee;}img{border:1px solid #ddd;max-width:420px;height:auto;}</style>');
    sb.write('</head><body>');
    sb.write('<div><a href="/rooms/$roomIdUrl$tokenSuffix">Back</a></div>');
    sb.write('<h2>Replay Preview - Room ${_esc(roomId)}</h2>');

    final replay = snap['lastReplayFile'];
    if (replay is! Map) {
      sb.write('<p style="color:#666"><i>(No replay data)</i></p>');
      sb.write('</body></html>');
      req.response.headers.contentType = ContentType.html;
      req.response.write(sb.toString());
      await req.response.close();
      return;
    }

    final replayId = _esc('${replay['replayId'] ?? ''}');
    final createdAt = _esc('${replay['createdAt'] ?? ''}');
    final tracks =
        (replay['tracks'] is List) ? (replay['tracks'] as List) : const [];
    sb.write('<div><b>replayId</b>: <code>$replayId</code></div>');
    sb.write('<div><b>createdAt</b>: <code>$createdAt</code></div>');
    sb.write('<div><b>tracks</b>: ${tracks.length}</div>');

    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      if (t is! Map) continue;
      final originWord = _esc('${t['originWord'] ?? ''}');
      final originOwnerName = _esc('${t['originOwnerName'] ?? ''}');
      sb.write(
          '<h3>#${i + 1} $originWord <span style="color:#666">$originOwnerName</span></h3>');

      final steps = (t['steps'] is List) ? (t['steps'] as List) : const [];
      if (steps.isEmpty) {
        sb.write('<div style="color:#666"><i>(empty)</i></div>');
        continue;
      }
      sb.write('<table>');
      sb.write(
          '<tr><th>round</th><th>drawer</th><th>word</th><th>guess</th><th>png</th></tr>');
      for (final s in steps) {
        if (s is! Map) continue;
        final round = _esc('${s['round'] ?? ''}');
        final drawerName = _esc('${s['drawerName'] ?? ''}');
        final word = _esc('${s['word'] ?? ''}');
        final guesserName = _esc('${s['guesserName'] ?? ''}');
        final guessText = _esc('${s['guessText'] ?? ''}');
        final pngBase64 = '${s['pngBase64'] ?? ''}';
        final pngHtml = pngBase64.isNotEmpty
            ? '<img src="data:image/png;base64,$pngBase64" />'
            : '<span style="color:#999">(none)</span>';
        final guessHtml = guesserName.isNotEmpty
            ? '${_esc(guesserName)} : ${_esc(guessText)}'
            : '<span style="color:#999">(no guess)</span>';
        sb.write('<tr>');
        sb.write('<td>$round</td>');
        sb.write('<td>$drawerName</td>');
        sb.write('<td>$word</td>');
        sb.write('<td>$guessHtml</td>');
        sb.write('<td>$pngHtml</td>');
        sb.write('</tr>');
      }
      sb.write('</table>');
    }

    sb.write('</body></html>');
    req.response.headers.contentType = ContentType.html;
    req.response.write(sb.toString());
    await req.response.close();
  }

  String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

  Future<void> _renderRoomPng(HttpRequest req, String path) async {
    // /rooms/<roomId>/png/<round>/<fingerprintHex>
    final seg = path.split('/');
    final pngIdx = seg.indexOf('png');
    if (seg.length < 6 || pngIdx < 0 || pngIdx + 2 >= seg.length) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final roomId = Uri.decodeComponent(seg[2]);
    final round = int.tryParse(seg[pngIdx + 1]) ?? 0;
    final fp = seg[pngIdx + 2];

    final bytes = server.getRoomHistoryPng(roomId, round, fp);
    if (bytes == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType('image', 'png');
    req.response.add(bytes);
    await req.response.close();
  }

  // /rooms/<roomId>/collab/layer/<layerId>.png
  Future<void> _renderCollabLayerPng(HttpRequest req, String path) async {
    final seg = path.split('/');
    // seg: ['', 'rooms', '<roomId>', 'collab', 'layer', '<layerId>.png']
    if (seg.length < 6) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final roomId = Uri.decodeComponent(seg[2]);
    var layerId = Uri.decodeComponent(seg[5]);
    if (layerId.endsWith('.png'))
      layerId = layerId.substring(0, layerId.length - 4);

    final data = server.getCollabLayerRgba(roomId, layerId);
    if (data == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final rgba = data['rgba'] as Uint8List;
    final w = data['width'] as int;
    final h = data['height'] as int;
    final scaled = _scaleRgba(rgba, w, h, 960);
    final scaledW = w > 960 ? 960 : w;
    final scaledH = w > 960 ? (h * 960 / w).round().clamp(1, h) : h;
    final pngBytes = _encodePng(scaled, scaledW, scaledH);
    req.response.headers.contentType = ContentType('image', 'png');
    req.response.headers.set('Cache-Control', 'no-store');
    req.response.add(pngBytes);
    await req.response.close();
  }

  // /rooms/<roomId>/collab/composite.png
  Future<void> _renderCollabCompositePng(HttpRequest req, String path) async {
    final seg = path.split('/');
    if (seg.length < 5) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final roomId = Uri.decodeComponent(seg[2]);

    final data = server.getCollabCompositeRgba(roomId);
    if (data == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final rgba = data['rgba'] as Uint8List;
    final w = data['width'] as int;
    final h = data['height'] as int;
    final scaled = _scaleRgba(rgba, w, h, 960);
    final scaledW = w > 960 ? 960 : w;
    final scaledH = w > 960 ? (h * 960 / w).round().clamp(1, h) : h;
    final pngBytes = _encodePng(scaled, scaledW, scaledH);
    req.response.headers.contentType = ContentType('image', 'png');
    req.response.headers.set('Cache-Control', 'no-store');
    req.response.add(pngBytes);
    await req.response.close();
  }

  // ===== 纯 Dart PNG 编码工具 =====

  static final List<int> _crc32Table = () {
    final t = List<int>.filled(256, 0);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      t[n] = c;
    }
    return t;
  }();

  static int _crc32ForChunk(List<int> type, List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final b in type) {
      crc = (crc >>> 8) ^ _crc32Table[(crc ^ b) & 0xFF];
    }
    for (final b in data) {
      crc = (crc >>> 8) ^ _crc32Table[(crc ^ b) & 0xFF];
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static void _writePngChunk(BytesBuilder out, String type, List<int> data) {
    final typeBytes = type.codeUnits;
    final lenBuf = ByteData(4)..setUint32(0, data.length);
    out.add(lenBuf.buffer.asUint8List());
    out.add(typeBytes);
    if (data.isNotEmpty) {
      out.add(data is Uint8List ? data : Uint8List.fromList(data));
    }
    final crc = _crc32ForChunk(typeBytes, data);
    final crcBuf = ByteData(4)..setUint32(0, crc);
    out.add(crcBuf.buffer.asUint8List());
  }

  static Uint8List _encodePng(Uint8List rgba, int w, int h) {
    // 每行: 1字节过滤器(0) + w*4字节RGBA
    final raw = Uint8List(h * (1 + w * 4));
    for (int y = 0; y < h; y++) {
      final rowStart = y * (1 + w * 4);
      raw[rowStart] = 0; // filter None
      final srcStart = y * w * 4;
      raw.setRange(rowStart + 1, rowStart + 1 + w * 4, rgba, srcStart);
    }
    final compressed = Uint8List.fromList(zlib.encode(raw));

    final ihdrData = Uint8List(13);
    final bd = ByteData.sublistView(ihdrData);
    bd.setUint32(0, w);
    bd.setUint32(4, h);
    ihdrData[8] = 8; // 位深8
    ihdrData[9] = 6; // RGBA
    ihdrData[10] = 0;
    ihdrData[11] = 0;
    ihdrData[12] = 0;

    final out = BytesBuilder(copy: false);
    out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    _writePngChunk(out, 'IHDR', ihdrData);
    _writePngChunk(out, 'IDAT', compressed);
    _writePngChunk(out, 'IEND', const []);
    return out.toBytes();
  }

  /// 最近邻降采样到 maxW（宽度超出时才执行）
  static Uint8List _scaleRgba(Uint8List rgba, int srcW, int srcH, int maxW) {
    if (srcW <= maxW) return rgba;
    final dstW = maxW;
    final dstH = (srcH * maxW / srcW).round().clamp(1, srcH);
    final result = Uint8List(dstW * dstH * 4);
    for (int y = 0; y < dstH; y++) {
      final srcY = (y * srcH / dstH).floor().clamp(0, srcH - 1);
      for (int x = 0; x < dstW; x++) {
        final srcX = (x * srcW / dstW).floor().clamp(0, srcW - 1);
        final s = (srcY * srcW + srcX) * 4;
        final d = (y * dstW + x) * 4;
        result[d] = rgba[s];
        result[d + 1] = rgba[s + 1];
        result[d + 2] = rgba[s + 2];
        result[d + 3] = rgba[s + 3];
      }
    }
    return result;
  }
}
