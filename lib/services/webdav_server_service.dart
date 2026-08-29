import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/jksv_backend.dart';
import 'package:roms_downloader/services/jksv_meta.dart';

/// A received Switch backup waiting for the user to confirm the pull.
class IncomingSave {
  final String titleId;
  final String displayName;
  final int bytes;
  const IncomingSave({required this.titleId, required this.displayName, required this.bytes});
}

/// Minimal WebDAV server exposing [JksvBackend] as a tree JKSV can browse.
/// Tree: `/` → one collection per title (display name) → one `.zip` backup.
/// Uploads (Switch→Android) are staged by title id (read from the zip's meta)
/// and surfaced via [incoming] for the user to confirm.
class WebDavServerService {
  JksvBackend? _backend;
  HttpServer? _server;

  // Current listing: display name (as a path segment) → title id.
  final Map<String, String> _nameToId = {};
  // Staged uploads: title id → zip bytes.
  final Map<String, List<int>> _staged = {};

  final ValueNotifier<int> activeTransfers = ValueNotifier(0);
  final ValueNotifier<List<IncomingSave>> incoming = ValueNotifier(const []);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start({required int port, required JksvBackend backend}) async {
    await stop();
    _backend = backend;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handle, onError: (e) => debugPrint('webdav error: $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Consume a staged upload (after the user confirms the pull) and drop it
  /// from the incoming list.
  List<int>? takeStaged(String titleId) {
    final bytes = _staged.remove(titleId);
    _refreshIncoming();
    return bytes;
  }

  void _refreshIncoming() {
    incoming.value = _staged.keys
        .map((id) => IncomingSave(titleId: id, displayName: _backend?.displayName(id) ?? id, bytes: _staged[id]!.length))
        .toList();
  }

  void _rebuildListing() {
    _nameToId.clear();
    for (final t in _backend?.listTitles() ?? const <EmuTitle>[]) {
      var name = _backend!.displayName(t.titleId);
      if (name.isEmpty) name = t.titleId;
      // Disambiguate name clashes by suffixing the id.
      if (_nameToId.containsKey(name)) name = '$name [${t.titleId}]';
      _nameToId[name] = t.titleId;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      switch (req.method) {
        case 'OPTIONS':
          req.response.headers
            ..set('DAV', '1,2')
            ..set('Allow', 'OPTIONS, GET, PUT, PROPFIND, MKCOL, DELETE, MOVE');
          await _end(req, HttpStatus.ok);
          break;
        case 'PROPFIND':
          await _propfind(req);
          break;
        case 'GET':
          await _get(req);
          break;
        case 'PUT':
          await _put(req);
          break;
        case 'MKCOL':
          await _end(req, HttpStatus.created);
          break;
        case 'DELETE':
          await _end(req, HttpStatus.noContent);
          break;
        case 'MOVE':
          await _end(req, HttpStatus.created);
          break;
        default:
          await _end(req, HttpStatus.methodNotAllowed);
      }
    } catch (e) {
      debugPrint('webdav request failed: $e');
      try {
        await _end(req, HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  Future<void> _end(HttpRequest req, int status) async {
    req.response.statusCode = status;
    await req.response.close();
  }

  List<String> _segments(HttpRequest req) =>
      req.uri.pathSegments.map(Uri.decodeComponent).where((s) => s.isNotEmpty).toList();

  // PROPFIND Depth:1 — self plus immediate children.
  Future<void> _propfind(HttpRequest req) async {
    await req.drain<void>();
    _rebuildListing();
    final segs = _segments(req);
    final responses = <String>[];

    String href(List<String> parts) => '/${parts.map(Uri.encodeComponent).join('/')}';

    if (segs.isEmpty) {
      responses.add(_collectionXml('/'));
      for (final name in _nameToId.keys) {
        responses.add(_collectionXml(href([name])));
      }
    } else if (segs.length == 1 && _nameToId.containsKey(segs[0])) {
      final titleId = _nameToId[segs[0]]!;
      final zip = _backend!.buildBackupZip(titleId);
      responses.add(_collectionXml(href([segs[0]])));
      responses.add(_fileXml(href([segs[0], '${segs[0]}.zip']), zip.length));
    } else {
      await _end(req, HttpStatus.notFound);
      return;
    }

    final body = '<?xml version="1.0" encoding="utf-8"?>\n'
        '<d:multistatus xmlns:d="DAV:">${responses.join()}</d:multistatus>';
    req.response.statusCode = 207;
    req.response.headers.set(HttpHeaders.contentTypeHeader, 'application/xml; charset=utf-8');
    req.response.write(body);
    await req.response.close();
  }

  String _collectionXml(String href) => '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
      '<d:resourcetype><d:collection/></d:resourcetype></d:prop>'
      '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';

  String _fileXml(String href, int length) => '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
      '<d:resourcetype/><d:getcontentlength>$length</d:getcontentlength>'
      '<d:getcontenttype>application/zip</d:getcontenttype></d:prop>'
      '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';

  // GET /<name>/<file>.zip → build the JKSV backup zip on the fly.
  Future<void> _get(HttpRequest req) async {
    _rebuildListing();
    final segs = _segments(req);
    if (segs.length != 2 || !_nameToId.containsKey(segs[0])) {
      await _end(req, HttpStatus.notFound);
      return;
    }
    activeTransfers.value++;
    try {
      final zip = _backend!.buildBackupZip(_nameToId[segs[0]]!);
      req.response.statusCode = HttpStatus.ok;
      req.response.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/zip')
        ..set(HttpHeaders.contentLengthHeader, '${zip.length}');
      req.response.add(zip);
      await req.response.close();
    } finally {
      activeTransfers.value--;
    }
  }

  // PUT any path → read the zip, derive the title id from its meta, stage it.
  Future<void> _put(HttpRequest req) async {
    activeTransfers.value++;
    try {
      final bytes = <int>[];
      await for (final chunk in req) {
        bytes.addAll(chunk);
      }
      final titleId = _titleIdFromZip(bytes) ?? _titleIdFromPath(_segments(req));
      if (titleId == null) {
        await _end(req, HttpStatus.badRequest);
        return;
      }
      _staged[titleId] = bytes;
      _refreshIncoming();
      await _end(req, HttpStatus.created);
    } finally {
      activeTransfers.value--;
    }
  }

  String? _titleIdFromZip(List<int> zipBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final e in archive) {
        if (p.basename(e.name) == JksvMeta.fileName) {
          final meta = JksvMeta.decode(Uint8List.fromList(e.content as List<int>));
          if (meta.magicOk) {
            return meta.applicationId.toRadixString(16).toUpperCase().padLeft(16, '0');
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String? _titleIdFromPath(List<String> segs) {
    for (final s in segs) {
      final m = RegExp(r'[0-9A-Fa-f]{16}').firstMatch(s);
      if (m != null) return m.group(0)!.toUpperCase();
    }
    return null;
  }

  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final ips = [for (final i in interfaces) for (final a in i.addresses) a.address];
    ips.sort((a, b) => (a.startsWith('192.168.') ? 0 : 1).compareTo(b.startsWith('192.168.') ? 0 : 1));
    return ips;
  }
}
