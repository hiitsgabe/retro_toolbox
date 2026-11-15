import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/rts_folder_model.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';

/// The hub's own library, forwarded to handhelds: its consoles, their game
/// lists, the credentials used to reach the source, and where downloads land.
class RtsLibrary {
  final Future<Map<String, Console>> Function() consoles;
  final Future<List<Game>> Function(Console) games;
  final Map<String, String> Function(Console) authHeaders;
  final String Function(Console) downloadDir;
  const RtsLibrary({
    required this.consoles,
    required this.games,
    required this.authHeaders,
    required this.downloadDir,
  });
}

/// Serves local folders as a catalog another app can consume via New Catalog
/// Source: a generated `consoles.json`, an HTML listing per folder (matching
/// [listingRegex]), and the files themselves (with HTTP Range for resume).
class RtsServerService {
  static Map<String, dynamic> consoleJson(RtsFolder f, int index, String hostPort) => {
        'name': f.name,
        'url': 'http://$hostPort/f/$index/',
        if (f.formats.isNotEmpty) 'file_format': f.formats,
        if (f.boxartsUrl != null && f.boxartsUrl!.isNotEmpty) 'boxarts': {'url': f.boxartsUrl},
        'roms_folder': f.romsSubfolder,
        'added': true,
      };

  static String buildConsolesJson(List<RtsFolder> folders, String hostPort) =>
      jsonEncode([for (var i = 0; i < folders.length; i++) consoleJson(folders[i], i, hostPort)]);

  /// A JSON listing the consumer auto-detects: [{name, size}, ...]. Download
  /// URLs are the folder URL + the encoded name.
  static String buildListingJson(List<({String name, int size})> files) =>
      jsonEncode([for (final f in files) {'name': f.name, 'size': f.size}]);

  /// Files in [folder] matching [formats] (all, if empty), as (name, size).
  static List<({String name, int size})> listFiles(Directory folder, List<String> formats) {
    if (!folder.existsSync()) return [];
    final exts = formats.map((e) => e.toLowerCase()).toSet();
    final out = <({String name, int size})>[];
    for (final e in folder.listSync(followLinks: false).whereType<File>()) {
      final name = p.basename(e.path);
      if (exts.isNotEmpty && !exts.contains(p.extension(name).toLowerCase())) continue;
      out.add((name: name, size: e.statSync().size));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// The hub's console as a handhelds sees it: pointed at this server, with the
  /// hub's credentials and source-specific listing settings stripped.
  static Map<String, dynamic> forwardedConsoleJson(Console c, String hostPort) {
    final j = c.toJson();
    for (final k in ['id', 'auth', 'download_url', 'list_url', 'list_systems', 'regex', 'list_json_file_location', 'list_item_id']) {
      j.remove(k);
    }
    return j
      ..['url'] = 'http://$hostPort/lib/${Uri.encodeComponent(c.id)}/'
      // The listing may announce an unpacked file whose extension isn't in
      // original_format; the consumer already skips re-unpacking it.
      ..['ignore_extension_filtering'] = true
      ..['added'] = true;
  }

  /// Each game's copy in [dir] (none if null), keyed by its filename: the
  /// exact file, else the only file sharing its stem (the unpacked form of a
  /// zip) whose extension is in [formats] (any, if empty). One listing of [dir].
  // ponytail: two files with the same stem (cue/bin) count as not local, so
  // multi-file unpacks are re-fetched from the source.
  static Map<String, String> localFiles(List<Game> games, String? dir, List<String> formats) {
    if (dir == null || !Directory(dir).existsSync()) return const {};
    final exts = formats.map((e) => e.toLowerCase()).toSet();
    final names = <String>{};
    final byStem = <String, List<String>>{};
    for (final f in Directory(dir).listSync(followLinks: false).whereType<File>()) {
      final n = p.basename(f.path);
      names.add(n);
      if (exts.isEmpty || exts.contains(p.extension(n).toLowerCase())) (byStem[p.basenameWithoutExtension(n)] ??= []).add(n);
    }
    return {
      for (final g in games)
        if (names.contains(g.filename))
          g.filename: p.join(dir, g.filename)
        else if (byStem[p.basenameWithoutExtension(g.filename)] case [final only])
          g.filename: p.join(dir, only),
    };
  }

  /// The catalog, announcing a game's [local] copy (from [localFiles]) instead.
  static List<({String name, int size})> forwardedListing(List<Game> games, Map<String, String> local) => [
        for (final g in games)
          if (local[g.filename] case final l?)
            (name: p.basename(l), size: File(l).lengthSync())
          else
            (name: g.filename, size: g.size),
      ];

  static Future<List<String>> localAddresses() => TinfoilServerService.localAddresses();

  HttpServer? _server;
  List<RtsFolder> _folders = const [];
  RtsLibrary? _library;
  final activeTransfers = ValueNotifier<int>(0);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  void setFolders(List<RtsFolder> folders) => _folders = folders;

  Future<void> start({required int port, required List<RtsFolder> folders, RtsLibrary? library}) async {
    _folders = folders;
    _library = library;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle, onError: (e) => debugPrint('rts server error: $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final segs = req.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      // Dart parses the port out of the Host header, so append our listen port —
      // the client reached us on it, so it's the right one to advertise.
      final hostName = req.headers.host ?? (await localAddresses()).firstOrNull ?? '127.0.0.1';
      final hostPort = '$hostName:$port';

      if (segs.length == 1 && segs[0] == 'consoles.json') {
        final lib = _library;
        final entries = [
          for (var i = 0; i < _folders.length; i++) consoleJson(_folders[i], i, hostPort),
          if (lib != null) for (final c in (await lib.consoles()).values) forwardedConsoleJson(c, hostPort),
        ];
        _send(req, jsonEncode(entries), ContentType('application', 'json', charset: 'utf-8'));
        return;
      }
      if (segs.length >= 2 && segs[0] == 'lib') {
        await _handleLibrary(req, segs);
        return;
      }
      if (segs.isNotEmpty && segs[0] == 'f' && segs.length >= 2) {
        final idx = int.tryParse(segs[1]);
        if (idx == null || idx < 0 || idx >= _folders.length) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        final folder = _folders[idx];
        if (segs.length == 2) {
          final files = listFiles(Directory(folder.path), folder.formats);
          _send(req, buildListingJson(files), ContentType('application', 'json', charset: 'utf-8'));
          return;
        }
        // /f/<idx>/<filename>
        await _serveFile(req, folder, segs.sublist(2).join('/'));
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (e) {
      debugPrint('rts handle error: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleLibrary(HttpRequest req, List<String> segs) async {
    final lib = _library;
    final c = lib == null ? null : (await lib.consoles())[segs[1]];
    if (lib == null || c == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final raw = lib.downloadDir(c);
    // An unset folder would resolve to the working directory (`/` on Android):
    // then nothing is served from or saved to disk.
    final dir = raw.isEmpty ? null : Directory(raw).absolute.path;
    final games = await lib.games(c);
    final local = localFiles(games, dir, c.gameFilesFormat ?? const []);
    if (segs.length == 2) {
      _send(req, buildListingJson(forwardedListing(games, local)), ContentType('application', 'json', charset: 'utf-8'));
      return;
    }
    final name = segs.sublist(2).join('/');
    // Only a catalog game, under the name the listing announced: never any
    // other file in the folder.
    final copy = local.values.where((l) => p.basename(l) == name).firstOrNull;
    if (copy != null) {
      activeTransfers.value++;
      try {
        await TinfoilServerService.serveFile(req, File(copy));
      } finally {
        activeTransfers.value--;
      }
      return;
    }
    final game = games.where((g) => g.filename == name).firstOrNull;
    if (game == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    File? saveTo;
    if (dir != null) {
      try {
        Directory(dir).createSync(recursive: true);
        // Game.filename is sanitized (no separators), so this stays in dir.
        saveTo = File(p.join(dir, name));
      } on FileSystemException {
        // unwritable: stream without a copy
      }
    }
    activeTransfers.value++;
    try {
      await TinfoilServerService.proxyUpstream(req, url: game.url, headers: lib.authHeaders(c), saveTo: saveTo);
    } finally {
      activeTransfers.value--;
    }
  }

  void _send(HttpRequest req, String body, ContentType type) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = type
      ..write(body);
    req.response.close();
  }

  /// Streams a file, honouring a single-range `Range: bytes=start-end` request
  /// so the downloader can resume. Guards against path escapes.
  Future<void> _serveFile(HttpRequest req, RtsFolder folder, String filename) async {
    final base = Directory(folder.path).absolute.path;
    final file = File(p.normalize(p.join(base, filename)));
    if (!p.isWithin(base, file.path) || !file.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final total = file.lengthSync();
    final range = req.headers.value(HttpHeaders.rangeHeader);
    int start = 0, end = total - 1;
    if (range != null && range.startsWith('bytes=')) {
      final parts = range.substring(6).split('-');
      start = int.tryParse(parts[0]) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty) end = int.tryParse(parts[1]) ?? end;
      if (start > end || start >= total) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
    }
    req.response.headers
      ..contentType = ContentType.binary
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..contentLength = end - start + 1;
    activeTransfers.value++;
    try {
      await req.response.addStream(file.openRead(start, end + 1));
    } finally {
      activeTransfers.value--;
      await req.response.close();
    }
  }
}
