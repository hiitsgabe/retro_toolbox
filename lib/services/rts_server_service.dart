import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/rts_folder_model.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';

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

  static Future<List<String>> localAddresses() => TinfoilServerService.localAddresses();

  HttpServer? _server;
  List<RtsFolder> _folders = const [];
  final activeTransfers = ValueNotifier<int>(0);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  void setFolders(List<RtsFolder> folders) => _folders = folders;

  Future<void> start({required int port, required List<RtsFolder> folders}) async {
    _folders = folders;
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
        _send(req, buildConsolesJson(_folders, hostPort), ContentType('application', 'json', charset: 'utf-8'));
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
        await _serveFile(req, folder, Uri.decodeComponent(segs.sublist(2).join('/')));
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
