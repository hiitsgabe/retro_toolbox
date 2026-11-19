import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/link_download.dart';

/// Serves a Tinfoil "shop": an index of the catalog's Switch games, their
/// updates and DLC, plus a streaming proxy that injects source auth (IA S3 /
/// bearer / cookie). Files already on the device are served from disk instead.
class TinfoilEntry {
  /// The game, or the addon as a Game (GameAddon.toGame).
  final Game game;
  final Console console;
  final String fileName;

  /// The file on the device (download or updates folder), when it is there.
  final String? localPath;
  const TinfoilEntry({required this.game, required this.console, required this.fileName, this.localPath});
}

class TinfoilServerService {
  static const _switchFormats = {'.nsp', '.nsz', '.xci', '.xcz'};

  static bool isSwitchConsole(Console c) => c.resolvedPlatform == 'switch';

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
    final safe = _safe(game.title.split('/').last);
    final tid = titleIdFor(game);
    if (tid == null || safe.contains(tid)) return safe;
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    return '$base [$tid]$ext';
  }

  /// [name] with anything but letters, digits and plain punctuation as `_`.
  static String _safe(String name) => name.split('').map((ch) => RegExp(r"[a-zA-Z0-9 .\-_()\[\]']").hasMatch(ch) ? ch : '_').join();

  /// [update] of [game] as Tinfoil names it: the update's title id is the
  /// base id with its last 3 digits set to 800. Null without a base id.
  static String? _updateFileName(Game game, GameAddon update) {
    final tid = titleIdFor(game);
    if (tid == null) return null;
    final safe = _safe(game.title.split('/').last);
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    return _safe('$base [${tid.substring(0, 13)}800][${update.label}]${p.extension(update.fileName)}');
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

  /// Extra shop paths: games already on the device, and every game. Tinfoil
  /// merges an index's `directories` into one shop instead of showing them as
  /// folders; the root index's `locations` adds Fast install to the console's
  /// File Browser as its own entry instead.
  static const fastInstallFolder = 'Fast install';
  static const allGamesFolder = 'All games';

  /// Builds the Tinfoil index JSON and the route map keyed `<consoleId>/<idx>`,
  /// with a game's updates and DLC after it as `<consoleId>/<idx>u<n>` and
  /// `<consoleId>/<idx>d<n>`. [hostPort] is the address the Switch reached us
  /// on (its Host header). [localFiles] gives a console's [localSwitchFiles]
  /// for games, [addonFiles] the same for addons: those are listed with the
  /// local file's extension and size. [folder] picks a sub-shop
  /// ([fastInstallFolder] lists just the local files); null is the full shop.
  static (Map<String, dynamic>, Map<String, TinfoilEntry>) buildIndex(Map<Console, List<Game>> gamesByConsole, String hostPort,
      {Map<String, String> Function(Console)? localFiles, Map<String, String> Function(Console)? addonFiles, String? folder}) {
    final files = <Map<String, dynamic>>[];
    final localOnly = <Map<String, dynamic>>[];
    final routes = <String, TinfoilEntry>{};
    var games = 0, updates = 0, dlcs = 0;
    gamesByConsole.forEach((console, consoleGames) {
      final local = localFiles?.call(console) ?? const {};
      final localAddons = addonFiles?.call(console) ?? const {};
      void add(String key, Game game, String fileName, Map<String, String> onDisk) {
        final localPath = onDisk[p.basenameWithoutExtension(game.filename)];
        var size = game.size;
        if (localPath != null) {
          fileName = p.setExtension(fileName, p.extension(localPath).toLowerCase());
          size = File(localPath).lengthSync();
        }
        routes[key] = TinfoilEntry(game: game, console: console, fileName: fileName, localPath: localPath);
        final file = {
          'url': 'http://$hostPort/dl/$key/${Uri.encodeComponent(fileName)}',
          'size': size,
        };
        files.add(file);
        if (localPath != null) localOnly.add(file);
      }

      for (var i = 0; i < consoleGames.length; i++) {
        final game = consoleGames[i];
        add('${console.id}/$i', game, _fileName(game), local);
        games++;
        for (final (j, update) in game.updates.indexed) {
          final name = _updateFileName(game, update);
          if (name == null) continue;
          add('${console.id}/${i}u$j', update.toGame(game), name, localAddons);
          updates++;
        }
        for (final (j, dlc) in game.dlcs.indexed) {
          add('${console.id}/${i}d$j', dlc.toGame(game), _safe(dlc.fileName), localAddons);
          dlcs++;
        }
      }
    });
    return (
      switch (folder) {
        fastInstallFolder => {'files': localOnly, 'success': 'Retro Toolbox: ${localOnly.length} ready for fast install'},
        allGamesFolder => {'files': files, 'success': 'Retro Toolbox: $games games, $updates updates, $dlcs DLC'},
        _ => {
            'files': files,
            'locations': [
              {'url': 'http://$hostPort/${Uri.encodeComponent(fastInstallFolder)}/', 'title': fastInstallFolder, 'action': 'add'},
            ],
            'success': 'Retro Toolbox: $games games, $updates updates, $dlcs DLC, ${localOnly.length} ready for fast install',
          },
      },
      routes,
    );
  }

  HttpServer? _server;
  Map<String, TinfoilEntry> _routes = {};
  Future<Map<Console, List<Game>>> Function()? _loadGames;
  Map<String, String> Function(Console)? _authHeaders;
  String? Function(Console)? _downloadDir;
  String? Function(Console)? _updatesDir;
  static final ValueNotifier<int> activeTransfers = ValueNotifier(0);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start({
    required int port,
    required Future<Map<Console, List<Game>>> Function() loadGames,
    required Map<String, String> Function(Console) authHeaders,
    String? Function(Console)? downloadDir,
    String? Function(Console)? updatesDir,
  }) async {
    await stop();
    _loadGames = loadGames;
    _authHeaders = authHeaders;
    _downloadDir = downloadDir;
    _updatesDir = updatesDir;
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
      // Folder URLs end in '/': drop the empty last segment.
      final segments = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        await _serveIndex(req);
      } else if (segments.length == 1 && (segments.first == fastInstallFolder || segments.first == allGamesFolder)) {
        await _serveIndex(req, folder: segments.first);
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
  Map<String, String> _addonFiles(Console c) => localSwitchFiles(_updatesDir?.call(c));

  /// Streams [file], honouring a single `bytes=a-b` / `bytes=a-` Range.
  static Future<void> serveFile(HttpRequest req, File file) async {
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

  Future<void> _serveIndex(HttpRequest req, {String? folder}) async {
    final games = await _loadGames!();
    final (index, routes) = buildIndex(games, _hostPort(req), localFiles: _localFiles, addonFiles: _addonFiles, folder: folder);
    _routes = routes;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(index));
    await req.response.close();
  }

  Future<void> _serveProxy(HttpRequest req, String key) async {
    if (_routes.isEmpty) {
      // Route map lives in memory; rebuild if the app restarted between the
      // Switch fetching the index and starting the download.
      final (_, routes) = buildIndex(await _loadGames!(), _hostPort(req), localFiles: _localFiles, addonFiles: _addonFiles);
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
      await serveFile(req, File(local));
      return;
    }

    final headers = _authHeaders!(entry.console);
    await proxyUpstream(req, url: entry.game.url, headers: headers);
  }

  /// Streams [url] to [req] through the storage host's redirects, injecting
  /// [headers] (auth) on every hop and forwarding Range. Never hands a
  /// client an auth/error page as if it were the game file.
  ///
  /// With [saveTo], a full (status 200) download is also written to
  /// `<saveTo>.part` and renamed into place only if the whole body arrived;
  /// any failure deletes the part. A compressed body or an HTML page is never
  /// copied, and while one transfer writes a part, others just proxy.
  static Future<void> proxyUpstream(HttpRequest req,
      {required String url, required Map<String, String> headers, File? saveTo}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    // A proxy must forward bytes verbatim: auto-decompressing while forwarding
    // the upstream (compressed) Content-Length corrupts the file so Tinfoil
    // reports "failed to open nsp".
    client.autoUncompress = false;
    activeTransfers.value++;
    String? claimed;
    try {
      // Follow redirects with the data request itself (auth on every hop),
      // never a separate probe: some storage hosts hand out links that break
      // after one use, or close a probe's connection before its body.
      final range = req.headers.value(HttpHeaders.rangeHeader);
      var target = Uri.parse(url);
      HttpClientResponse upstreamRes;
      for (var hop = 0;; hop++) {
        final upstreamReq = await client.getUrl(target);
        upstreamReq.followRedirects = false;
        headers.forEach(upstreamReq.headers.set);
        if (range != null) upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
        upstreamRes = await upstreamReq.close();
        final location = upstreamRes.headers.value(HttpHeaders.locationHeader);
        if (!upstreamRes.isRedirect || location == null || hop >= 5) break;
        await upstreamRes.drain<void>().catchError((_) {});
        target = target.resolve(location);
      }
      // Never hand Tinfoil an auth/error page as if it were the game file.
      if (upstreamRes.statusCode >= 400) {
        debugPrint('proxy upstream $target -> ${upstreamRes.statusCode}');
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
      final part = saveTo == null ? null : File('${saveTo.path}.part');
      final encoding = upstreamRes.headers.value(HttpHeaders.contentEncodingHeader);
      final type = upstreamRes.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (part != null &&
          upstreamRes.statusCode == HttpStatus.ok &&
          // The client decodes a compressed body; the copy would stay encoded.
          (encoding == null || encoding == 'identity') &&
          // A sign-in or interstitial page, not the game.
          !type.toLowerCase().startsWith('text/html') &&
          // A link download resuming this very part.
          !downloadPathReserved(saveTo!.path) &&
          // Claim in-process (no await between check and add): two simultaneous
          // downloads must not share one .part. A part left by a killed run
          // is not in the set, so it is truncated and reused.
          _partsInFlight.add(part.absolute.path)) {
        try {
          part.createSync(); // no folder -> plain proxying
          claimed = part.absolute.path;
        } on FileSystemException {
          _partsInFlight.remove(part.absolute.path);
        }
      }
      if (claimed == null) {
        await upstreamRes.pipe(req.response);
        return;
      }
      final sink = part!.openWrite(); // FileMode.write: truncates a stale part
      sink.done.catchError((_) {}); // disk errors surface from close() below
      var written = 0;
      var upstreamDone = false;
      try {
        await req.response.addStream(upstreamRes.transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (c, out) {
            sink.add(c);
            written += c.length;
            out.add(c);
          },
          handleDone: (out) {
            upstreamDone = true;
            out.close();
          },
        )));
        // Serve the client first: a local disk failure must not hang it.
        await req.response.close();
      } catch (_) {
        await sink.close().catchError((_) {});
        await part.delete().catchError((_) => part);
        rethrow;
      }
      try {
        await sink.close();
        final expected = upstreamRes.contentLength;
        // addStream returns quietly (dropping the upstream) when the client
        // has gone, so an unfinished upstream means an incomplete copy.
        if (!upstreamDone || (expected >= 0 && written != expected)) {
          await part.delete();
        } else {
          await part.rename(saveTo!.path);
        }
      } catch (_) {
        // The client already has its bytes; just drop the copy.
        await part.delete().catchError((_) => part);
      }
    } finally {
      if (claimed != null) _partsInFlight.remove(claimed);
      activeTransfers.value--;
      client.close();
    }
  }

  /// `.part` files a [proxyUpstream] in this isolate is writing, across all servers.
  // ponytail: in-process claim; another process writing the same folder isn't
  // seen. A lock file would cover that if two app instances ever share one.
  static final _partsInFlight = <String>{};

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
