import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/jksv_meta.dart';
import 'package:retro_toolbox/services/jksv_source.dart';

/// A received Switch backup waiting for the user to confirm the pull.
class IncomingSave {
  final String titleId;
  final String displayName;
  final int bytes;
  const IncomingSave({required this.titleId, required this.displayName, required this.bytes});
}

/// Minimal WebDAV server exposing a [JksvSource] as a tree JKSV can browse.
/// Tree: `/` → one collection per title (display name) → one `.zip` backup.
/// Uploads (Switch→Android) are staged by title id (read from the zip's meta)
/// and surfaced via [incoming] for the user to confirm.
class WebDavServerService {
  JksvSource? _source;
  HttpServer? _server;

  // Current listing: display name (as a path segment) → title id.
  Map<String, String> _nameToId = {};
  // Staged uploads: title id → zip bytes.
  final Map<String, List<int>> _staged = {};

  final ValueNotifier<int> activeTransfers = ValueNotifier(0);
  final ValueNotifier<List<IncomingSave>> incoming = ValueNotifier(const []);

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start({required int port, required JksvSource source}) async {
    await stop();
    _source = source;
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
        .map((id) => IncomingSave(titleId: id, displayName: _source?.displayName(id) ?? id, bytes: _staged[id]!.length))
        .toList();
  }

  // Built aside and swapped in, so a request racing this await still sees
  // the previous listing instead of a half-filled one.
  Future<void> _rebuildListing() async {
    final source = _source;
    final listing = <String, String>{};
    for (final id in await source?.titleIds() ?? const <String>[]) {
      var name = source!.displayName(id);
      if (name.isEmpty) name = id;
      // Disambiguate name clashes by suffixing the id.
      if (listing.containsKey(name)) name = '$name [$id]';
      listing[name] = id;
    }
    _nameToId = listing;
  }

  // A title listed but without a backup (a hub unit with no gens) is a 404,
  // not a server error.
  Future<List<int>?> _backupOrNull(String titleId) async {
    try {
      return await _source!.backupZip(titleId);
    } catch (e) {
      debugPrint('[jdkv] no backup for $titleId: $e');
      return null;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    debugPrint('[jdkv] ${req.method} ${req.uri.path} (depth=${req.headers.value('Depth')})');
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
    await _rebuildListing();
    final segs = _segments(req);
    final responses = <String>[];

    String href(List<String> parts) => '/${parts.map(Uri.encodeComponent).join('/')}';

    if (segs.isEmpty) {
      responses.add(_collectionXml('/'));
      for (final name in _nameToId.keys) {
        responses.add(_collectionXml(href([name])));
      }
    } else if (segs.length == 1 && _nameToId.containsKey(segs[0])) {
      final zip = await _backupOrNull(_nameToId[segs[0]]!);
      if (zip == null) {
        await _end(req, HttpStatus.notFound);
        return;
      }
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
    await _rebuildListing();
    final segs = _segments(req);
    if (segs.length != 2 || !_nameToId.containsKey(segs[0])) {
      debugPrint('[jdkv] GET 404 for ${segs.join('/')} (known: ${_nameToId.keys.toList()})');
      await _end(req, HttpStatus.notFound);
      return;
    }
    debugPrint('[jdkv] GET zip for ${segs[0]} (${_nameToId[segs[0]]})');
    activeTransfers.value++;
    try {
      final zip = await _backupOrNull(_nameToId[segs[0]]!);
      if (zip == null) {
        await _end(req, HttpStatus.notFound);
        return;
      }
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
      // Diagnostic dump of exactly what JKSV uploads.
      try {
        final dump = File('${Directory.systemTemp.path}/jdkv_last_put.zip');
        dump.writeAsBytesSync(bytes);
        debugPrint('[jdkv] dumped PUT body to ${dump.path}');
        final names = ZipDecoder().decodeBytes(bytes).map((e) => e.name).toList();
        debugPrint('[jdkv] PUT zip entries: $names');
      } catch (e) {
        debugPrint('[jdkv] PUT body not a readable zip: $e');
      }
      final fromZip = _titleIdFromZip(bytes);
      final titleId = fromZip ?? _titleIdFromPath(_segments(req));
      debugPrint('[jdkv] PUT ${bytes.length}B → titleId=$titleId (fromZipMeta=${fromZip != null})');
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
