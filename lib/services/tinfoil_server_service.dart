import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';

/// Serves a Tinfoil "shop": an index of the catalog's Switch games plus a
/// streaming proxy that injects source auth (IA S3 / bearer / cookie). Games
/// already in the console's download folder are served from disk instead.
class TinfoilEntry {
  final Game game;
  final Console console;
  final String fileName;

  /// The game's file in the download folder, when it is there.
  final String? localPath;
  const TinfoilEntry({required this.game, required this.console, required this.fileName, this.localPath});
}

class TinfoilServerService {
  static const _switchFormats = {'.nsp', '.nsz', '.xci', '.xcz'};

  static bool isSwitchConsole(Console c) => c.fileFormat?.any((f) => _switchFormats.contains(f.toLowerCase())) ?? false;

  // Switch title IDs are 16 hex digits starting with 01 (retail); catalog
  // titles omit them, but the download URL path usually carries one.
  static final _titleIdPattern = RegExp(r'01[0-9A-Fa-f]{14}');

  static String? titleIdFor(Game game) {
    final m = _titleIdPattern.firstMatch(game.title) ?? _titleIdPattern.firstMatch(game.url);
    return m?.group(0)?.toUpperCase();
  }

  /// Tinfoil lists a file under "New Games" with cover art only when it can
  /// read the title ID from the filename as `[0100..]`. Titles here lack it, so
  /// we inject the ID pulled from the URL before the extension.
  static String _fileName(Game game) {
    final raw = game.title.split('/').last;
    final safe = raw.split('').map((ch) => RegExp(r"[a-zA-Z0-9 .\-_()\[\]']").hasMatch(ch) ? ch : '_').join();
    final tid = titleIdFor(game);
    if (tid == null || safe.contains(tid)) return safe;
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    return '$base [$tid]$ext';
  }

  /// Switch files in [dir] by name without extension (a download stays
  /// `.nsz`, or becomes `.nsp` once decompressed).
  static Map<String, String> localSwitchFiles(String? dir) {
    if (dir == null || dir.isEmpty) return const {};
    try {
      return {
        for (final f in Directory(dir).listSync().whereType<File>())
          if (_switchFormats.contains(p.extension(f.path).toLowerCase())) p.basenameWithoutExtension(f.path): f.path,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Builds the Tinfoil index JSON and the route map keyed `<consoleId>/<idx>`.
  /// [hostPort] is the address the Switch reached us on (its Host header).
  /// [localFiles] gives a console's [localSwitchFiles]: those games are listed
  /// with the local file's extension and size.
  static (Map<String, dynamic>, Map<String, TinfoilEntry>) buildIndex(Map<Console, List<Game>> gamesByConsole, String hostPort, {Map<String, String> Function(Console)? localFiles}) {
    final files = <Map<String, dynamic>>[];
    final routes = <String, TinfoilEntry>{};
    gamesByConsole.forEach((console, games) {
      final local = localFiles?.call(console) ?? const {};
      for (var i = 0; i < games.length; i++) {
        final game = games[i];
        final localPath = local[p.basenameWithoutExtension(game.filename)];
        var fileName = _fileName(game);
        var size = game.size;
        if (localPath != null) {
          fileName = p.setExtension(fileName, p.extension(localPath).toLowerCase());
          size = File(localPath).lengthSync();
        }
        final entry = TinfoilEntry(game: game, console: console, fileName: fileName, localPath: localPath);
        final key = '${console.id}/$i';
        routes[key] = entry;
        files.add({
          'url': 'http://$hostPort/dl/$key/${Uri.encodeComponent(entry.fileName)}',
          'size': size,
        });
      }
    });
    return (
      {'files': files, 'success': 'Retro Toolbox — ${files.length} games'},
      routes,
    );
  }

  HttpServer? _server;
  Map<String, TinfoilEntry> _routes = {};
  Future<Map<Console, List<Game>>> Function()? _loadGames;
  Map<String, String> Function(Console)? _authHeaders;
  String? Function(Console)? _downloadDir;
  final ValueNotifier<int> activeTransfers = ValueNotifier(0);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start({
    required int port,
    required Future<Map<Console, List<Game>>> Function() loadGames,
    required Map<String, String> Function(Console) authHeaders,
    String? Function(Console)? downloadDir,
  }) async {
    await stop();
    _loadGames = loadGames;
    _authHeaders = authHeaders;
    _downloadDir = downloadDir;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle, onError: (e) => debugPrint('tinfoil server error: $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _routes = {};
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final segments = req.uri.pathSegments;
      if (segments.isEmpty) {
        await _serveIndex(req);
      } else if (segments.first == 'dl' && segments.length >= 3) {
        await _serveProxy(req, '${segments[1]}/${segments[2]}');
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (e) {
      debugPrint('tinfoil request failed: $e');
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    }
  }

  Map<String, String> _localFiles(Console c) => localSwitchFiles(_downloadDir?.call(c));

  /// Streams [file], honouring a single `bytes=a-b` / `bytes=a-` Range.
  Future<void> _serveFile(HttpRequest req, File file) async {
    final length = await file.length();
    var start = 0, end = length - 1;
    final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
    final res = req.response;
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.contentType = ContentType.binary;
    if (m != null) {
      final a = m.group(1)!, b = m.group(2)!;
      if (a.isEmpty) {
        start = length - (int.tryParse(b) ?? 0); // suffix range: the last N bytes
      } else {
        start = int.parse(a);
        if (b.isNotEmpty) end = int.parse(b);
      }
      if (start < 0) start = 0;
      if (end >= length) end = length - 1;
      if (start > end) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await res.close();
        return;
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    }
    res.contentLength = end - start + 1;
    activeTransfers.value++;
    try {
      if (req.method == 'HEAD') {
        await res.close();
      } else {
        await file.openRead(start, end + 1).pipe(res);
      }
    } finally {
      activeTransfers.value--;
    }
  }

  /// The address the Switch reached us on — index URLs must use it back.
  String _hostPort(HttpRequest req) => req.headers.value(HttpHeaders.hostHeader) ?? 'localhost:$port';

  Future<void> _serveIndex(HttpRequest req) async {
    final games = await _loadGames!();
    final (index, routes) = buildIndex(games, _hostPort(req), localFiles: _localFiles);
    _routes = routes;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(index));
    await req.response.close();
  }

  Future<void> _serveProxy(HttpRequest req, String key) async {
    if (_routes.isEmpty) {
      // Route map lives in memory; rebuild if the app restarted between the
      // Switch fetching the index and starting the download.
      final (_, routes) = buildIndex(await _loadGames!(), _hostPort(req), localFiles: _localFiles);
      _routes = routes;
    }
    final entry = _routes[key];
    if (entry == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final local = entry.localPath;
    if (local != null && File(local).existsSync()) {
      await _serveFile(req, File(local));
      return;
    }

    final headers = _authHeaders!(entry.console);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    // A proxy must forward bytes verbatim: auto-decompressing while forwarding
    // the upstream (compressed) Content-Length corrupts the file so Tinfoil
    // reports "failed to open nsp".
    client.autoUncompress = false;
    activeTransfers.value++;
    try {
      // Follow redirects with the data request itself (auth on every hop),
      // never a separate probe: some storage hosts hand out links that break
      // after one use, or close a probe's connection before its body.
      final range = req.headers.value(HttpHeaders.rangeHeader);
      var url = Uri.parse(entry.game.url);
      HttpClientResponse upstreamRes;
      for (var hop = 0;; hop++) {
        final upstreamReq = await client.getUrl(url);
        upstreamReq.followRedirects = false;
        headers.forEach(upstreamReq.headers.set);
        if (range != null) upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
        upstreamRes = await upstreamReq.close();
        final location = upstreamRes.headers.value(HttpHeaders.locationHeader);
        if (!upstreamRes.isRedirect || location == null || hop >= 5) break;
        await upstreamRes.drain<void>().catchError((_) {});
        url = url.resolve(location);
      }
      // Never hand Tinfoil an auth/error page as if it were the game file.
      if (upstreamRes.statusCode >= 400) {
        await upstreamRes.drain<void>();
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
        return;
      }
      req.response.statusCode = upstreamRes.statusCode;
      for (final h in [
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentEncodingHeader,
      ]) {
        final v = upstreamRes.headers.value(h);
        if (v != null) req.response.headers.set(h, v);
      }
      await upstreamRes.pipe(req.response);
    } finally {
      activeTransfers.value--;
      client.close();
    }
  }

  /// Local IPv4 addresses, home-LAN ones first (192.168.x is where a Switch
  /// usually sits; Tailscale/CGNAT 100.64-127.x and docker nets are demoted).
  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final ips = [
      for (final i in interfaces)
        for (final a in i.addresses) a.address
    ];
    int rank(String ip) {
      if (ip.startsWith('192.168.')) return 0;
      if (ip.startsWith('172.')) return 1;
      if (ip.startsWith('10.') && !ip.startsWith('10.88.')) return 2;
      return 3; // Tailscale CGNAT, docker bridges, etc.
    }

    ips.sort((a, b) => rank(a).compareTo(rank(b)));
    return ips;
  }
}
