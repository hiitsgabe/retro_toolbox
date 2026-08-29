import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/utils/network.dart';

/// Serves a Tinfoil "shop": an index of the catalog's Switch games plus a
/// streaming proxy that injects source auth (IA S3 / bearer / cookie).
class TinfoilEntry {
  final Game game;
  final Console console;
  final String fileName;
  const TinfoilEntry({required this.game, required this.console, required this.fileName});
}

class TinfoilServerService {
  static const _switchFormats = {'.nsp', '.nsz', '.xci', '.xcz'};

  static bool isSwitchConsole(Console c) => c.fileFormat?.any((f) => _switchFormats.contains(f.toLowerCase())) ?? false;

  static String _fileName(Game game) {
    final title = game.title.split('/').last;
    return title.split('').map((ch) => RegExp(r"[a-zA-Z0-9 .\-_()\[\]']").hasMatch(ch) ? ch : '_').join();
  }

  /// Builds the Tinfoil index JSON and the route map keyed `<consoleId>/<idx>`.
  /// [hostPort] is the address the Switch reached us on (its Host header).
  static (Map<String, dynamic>, Map<String, TinfoilEntry>) buildIndex(Map<Console, List<Game>> gamesByConsole, String hostPort) {
    final files = <Map<String, dynamic>>[];
    final routes = <String, TinfoilEntry>{};
    gamesByConsole.forEach((console, games) {
      for (var i = 0; i < games.length; i++) {
        final entry = TinfoilEntry(game: games[i], console: console, fileName: _fileName(games[i]));
        final key = '${console.id}/$i';
        routes[key] = entry;
        files.add({
          'url': 'http://$hostPort/dl/$key/${Uri.encodeComponent(entry.fileName)}',
          'size': games[i].size,
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
  final ValueNotifier<int> activeTransfers = ValueNotifier(0);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start({
    required int port,
    required Future<Map<Console, List<Game>>> Function() loadGames,
    required Map<String, String> Function(Console) authHeaders,
  }) async {
    await stop();
    _loadGames = loadGames;
    _authHeaders = authHeaders;
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

  /// The address the Switch reached us on — index URLs must use it back.
  String _hostPort(HttpRequest req) => req.headers.value(HttpHeaders.hostHeader) ?? 'localhost:$port';

  Future<void> _serveIndex(HttpRequest req) async {
    final games = await _loadGames!();
    final (index, routes) = buildIndex(games, _hostPort(req));
    _routes = routes;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(index));
    await req.response.close();
  }

  Future<void> _serveProxy(HttpRequest req, String key) async {
    if (_routes.isEmpty) {
      // Route map lives in memory; rebuild if the app restarted between the
      // Switch fetching the index and starting the download.
      final (_, routes) = buildIndex(await _loadGames!(), _hostPort(req));
      _routes = routes;
    }
    final entry = _routes[key];
    if (entry == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    final headers = _authHeaders!(entry.console);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    activeTransfers.value++;
    try {
      final upstreamUrl = await resolveRedirects(entry.game.url, headers);
      final upstreamReq = await client.getUrl(Uri.parse(upstreamUrl));
      headers.forEach(upstreamReq.headers.set);
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) upstreamReq.headers.set(HttpHeaders.rangeHeader, range);

      final upstreamRes = await upstreamReq.close();
      req.response.statusCode = upstreamRes.statusCode;
      for (final h in [
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.contentTypeHeader,
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
    final ips = [for (final i in interfaces) for (final a in i.addresses) a.address];
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
