import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/utils/title_match.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';

/// Serves an FPKGi "shop" for the PS4: an FPKGi-format JSON listing the
/// catalog's PS4 packages (title id, name, region, size, cover) plus streaming
/// proxies for the packages and covers. The PS4 cannot authenticate against
/// the Internet Archive (items are access-restricted), so every byte flows
/// through this server with the app's IA credentials injected.
class FpkgiEntry {
  final Game game;
  final Console console;
  final String titleId;
  final String region;
  final String version;
  final int size;

  /// The game's file in the download folder, when it is there.
  final String? localPath;
  const FpkgiEntry({
    required this.game,
    required this.console,
    required this.titleId,
    required this.region,
    required this.version,
    required this.size,
    this.localPath,
  });
}

class FpkgiServerService {
  static const iconItem = 'ps4-fpkg-collection-english-icons';

  /// "(...)"/"[...]" groups: region, language and version tags.
  static final _bracketGroups = RegExp(r'\s*[\[(][^\])]*[\])]');

  static bool isPs4Console(Console c) => c.resolvedPlatform == 'ps4';

  /// Catalog boxart mapping (name -> CUSA png url) parsed once; FPKGi needs
  /// the CUSA title id per game and the cover to show next to it.
  static Map<String, String> _boxarts = {};
  static Future<Map<String, String>> boxarts() async {
    if (_boxarts.isNotEmpty) return _boxarts;
    final raw = await rootBundle.loadString('assets/boxarts/playstation_4.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _boxarts = {
      for (final item in list)
        normalizeTitle((item['name'] as String?) ?? ''): (item['image'] as String?) ?? '',
    };
    return _boxarts;
  }

  static String? cusaFor(Game game) {
    if (_boxarts.isEmpty) return null;
    final match = matchBoxartUrls([p.basenameWithoutExtension(game.filename)], _boxarts).first;
    if (match == null) return null;
    final m = RegExp(r'((?:HP|PC|PP)SA\d{5}|CUSA\d{5})', caseSensitive: false).firstMatch(p.basename(match));
    return m?.group(1)?.toUpperCase();
  }

  /// FPKGi region ids, from the filename's region tag.
  static String regionFor(String filename) {
    final m = RegExp(r'\[(US|EU|AS|JP|KR|HK)\]', caseSensitive: false).firstMatch(filename);
    return switch (m?.group(1)?.toUpperCase()) {
      'US' => 'USA',
      'EU' => 'EUR',
      'AS' || 'HK' => 'ASIA',
      'JP' => 'JAP',
      'KR' => 'KOR',
      _ => 'ALL',
    };
  }

  static String? versionFor(String filename) {
    final m = RegExp(r'\[(\d+)\.(\d+)\]').firstMatch(filename);
    if (m == null) return null;
    return '${m.group(1)!.padLeft(2, '0')}.${m.group(2)!.padLeft(2, '0')}';
  }

  /// PS4 files in [dir] by name without extension (a download stays `.pkg`).
  static Map<String, String> localPs4Files(String? dir) {
    if (dir == null || dir.isEmpty) return const {};
    try {
      return {
        for (final f in Directory(dir).listSync().whereType<File>())
          if (p.extension(f.path).toLowerCase() == '.pkg') p.basenameWithoutExtension(f.path): f.path,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Builds the FPKGi `{"DATA": {pkgUrl: {...}}}` document and the route map
  /// keyed `<consoleId>/<idx>` for packages plus CUSA ids for covers.
  /// [hostPort] is the address the PS4 reached us on (its Host header).
  static (Map<String, dynamic>, Map<String, FpkgiEntry>, Set<String>) buildData(Map<Console, List<Game>> gamesByConsole, String hostPort, {Map<String, String> Function(Console)? localFiles}) {
    final data = <String, dynamic>{};
    final routes = <String, FpkgiEntry>{};
    final icons = <String>{};
    gamesByConsole.forEach((console, games) {
      final local = localFiles?.call(console) ?? const {};
      for (var i = 0; i < games.length; i++) {
        final game = games[i];
        final titleId = cusaFor(game) ?? '';
        if (titleId.isNotEmpty) icons.add(titleId);
        final localPath = local[p.basenameWithoutExtension(game.filename)];
        final entry = FpkgiEntry(
          game: game,
          console: console,
          titleId: titleId,
          region: regionFor(game.filename),
          version: versionFor(game.filename) ?? '01.00',
          size: localPath != null ? File(localPath).lengthSync() : game.size,
          localPath: localPath,
        );
        final key = '${console.id}/$i';
        routes[key] = entry;
        final name = p.basenameWithoutExtension(game.title).replaceAll(_bracketGroups, '').trim().replaceAll(RegExp(r'[-–]\s*$'), '').trim();
        data['http://$hostPort/fpkg/$key/${Uri.encodeComponent(p.setExtension(name, '.pkg'))}'] = {
          'title_id': titleId,
          'region': entry.region,
          'name': name,
          'version': entry.version,
          'size': entry.size,
          'min_fw': '9.00',
          'cover_url': titleId.isEmpty ? null : 'http://$hostPort/fpkg/icon/$titleId.png',
        };
      }
    });
    return ({'DATA': data}, routes, icons);
  }

  HttpServer? _server;
  Map<String, FpkgiEntry> _routes = {};
  Set<String> _icons = {};
  Future<Map<Console, List<Game>>> Function()? _loadGames;
  Map<String, String> Function(Console)? _authHeaders;
  String? Function(Console)? _downloadDir;

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
    _server!.listen(_handle, onError: (e) => debugPrint('fpkgi server error: $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _routes = {};
    _icons = {};
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final segments = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 3 && segments.first == 'fpkg') {
        if (segments[1] == 'icon') {
          await _serveIcon(req, _hostPort(req), p.basenameWithoutExtension(segments[2]));
        } else {
          await _servePackage(req, _hostPort(req), '${segments[1]}/${segments[2]}');
        }
      } else if (segments.isEmpty || segments.first.endsWith('.json')) {
        await _serveData(req);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (e) {
      debugPrint('fpkgi request failed: $e');
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// The address the PS4 reached us on — data URLs must use it back.
  String _hostPort(HttpRequest req) => req.headers.value(HttpHeaders.hostHeader) ?? 'localhost:$port';

  /// Rebuilds the in-memory route map (no response written); returns the data.
  Future<Map<String, dynamic>> _rebuild(String hostPort) async {
    await boxarts();
    final games = await _loadGames!();
    final (data, routes, icons) = buildData(games, hostPort, localFiles: (Console c) => localPs4Files(_downloadDir?.call(c)));
    _routes = routes;
    _icons = icons;
    return data;
  }

  Future<void> _serveData(HttpRequest req) async {
    final data = await _rebuild(_hostPort(req));
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(data));
    await req.response.close();
  }

  Future<void> _servePackage(HttpRequest req, String hostPort, String key) async {
    if (_routes.isEmpty) {
      // Route map lives in memory; rebuild if the app restarted between the
      // PS4 fetching the data and starting the download.
      await _rebuild(hostPort);
    }
    final entry = _routes[key];
    if (entry == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final local = entry.localPath;
    if (local != null && File(local).existsSync()) {
      await TinfoilServerService.serveFile(req, File(local));
      return;
    }
    await TinfoilServerService.proxyUpstream(req, url: entry.game.url, headers: _authHeaders!(entry.console));
  }

  /// Streams one cover from the FPKGi icons item (also access-restricted).
  Future<void> _serveIcon(HttpRequest req, String hostPort, String cusa) async {
    if (_routes.isEmpty) await _rebuild(hostPort);
    if (_icons.isNotEmpty && !_icons.contains(cusa)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final console = _routes.isEmpty ? null : _routes.values.first.console;
    final headers = console == null ? <String, String>{} : _authHeaders!(console);
    await TinfoilServerService.proxyUpstream(req, url: 'https://archive.org/download/$iconItem/$cusa.png', headers: headers);
  }
}
