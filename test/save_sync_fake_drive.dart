import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:retro_toolbox/services/save_sync/drive_api.dart';
import 'package:retro_toolbox/services/save_sync/drive_transport.dart';

/// One file or folder in a [FakeDrive].
class FakeFile {
  FakeFile(this.id, this.name, this.mimeType, this.parent, this.createdTime, this.bytes);

  final String id;
  final String name;
  final String mimeType;
  final String parent;
  final DateTime createdTime;
  List<int> bytes;
  bool trashed = false;

  bool get isFolder => mimeType == driveFolderMime;

  Map<String, Object> json({bool sha = true}) => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'createdTime': createdTime.toIso8601String(),
        if (!isFolder) 'size': '${bytes.length}',
        if (!isFolder && sha) 'sha256Checksum': sha256.convert(bytes).toString(),
        if (!isFolder) 'md5Checksum': md5.convert(bytes).toString(),
      };
}

class _Fail {
  _Fail(this.status, this.reason, this.raw, this.match, this.times, {this.landed});

  final int status;
  final String reason;
  final String? raw;
  final bool Function(DriveRequest r) match;
  int times;

  /// Null for an HTTP error; otherwise the connection drops, before Drive saw the request (false) or
  /// after Drive acted on it (true).
  final bool? landed;
}

/// An in-memory Google Drive behind [DriveTransport], for the requests [DriveApi] makes and no
/// others: folders (two with the same name allowed), paging, sha256Checksum, trash, a 401 for any
/// token but [token], and injected errors. Listings come back newest first, so callers must sort.
class FakeDrive implements DriveTransport {
  FakeDrive({this.pageSize = 1000});

  /// Drive's page size cap; small values force paging.
  final int pageSize;
  final files = <String, FakeFile>{};

  /// `METHOD path` of every request, failed ones included.
  final log = <String>[];
  String token = 'token-1';

  /// Create and update responses carry no sha256Checksum (a metadata get still has it).
  bool omitSha256 = false;

  /// Stores every upload with its first byte flipped.
  bool corruptUploads = false;
  DateTime _clock = DateTime.utc(2026, 11, 12, 9);
  var _ids = 0;
  final _fails = <_Fail>[];
  final _sessions = <String, Map<String, dynamic>>{};

  /// The next [times] requests that [match] (default: any) are answered with [status], a Drive error
  /// body with [reason], or [raw] as the whole body.
  void fail(int status, {String reason = '', String? raw, int times = 1, bool Function(DriveRequest r)? match}) =>
      _fails.add(_Fail(status, reason, raw, match ?? (_) => true, times));

  /// The connection of the next [times] requests that [match] (default: any) drops with a
  /// [DriveNetworkError]: before Drive sees the request, or once Drive has acted on it when [landed].
  void drop({bool landed = false, int times = 1, bool Function(DriveRequest r)? match}) =>
      _fails.add(_Fail(0, '', null, match ?? (_) => true, times, landed: landed));

  /// Adds a folder, or a file when [bytes] is given. [created] defaults to one second after the last item.
  FakeFile add(String name, {String parent = 'root', List<int>? bytes, DateTime? created}) {
    final at = created ?? (_clock = _clock.add(const Duration(seconds: 1)));
    final f = FakeFile('f${++_ids}', name, bytes == null ? driveFolderMime : mimeOf(name), parent, at, [...?bytes]);
    return files[f.id] = f;
  }

  bool _gone(FakeFile f) => f.trashed || (f.parent != 'root' && _gone(files[f.parent]!));

  /// Live items named [name] directly in [parent], oldest first.
  List<FakeFile> named(String parent, String name) =>
      files.values.where((f) => f.parent == parent && f.name == name && !_gone(f)).toList()..sort((a, b) => a.createdTime.compareTo(b.createdTime));

  /// The live item at a `/` path from My Drive, taking the oldest at each step.
  FakeFile? at(String path) {
    var parent = 'root';
    FakeFile? f;
    for (final name in path.split('/')) {
      final hits = named(parent, name);
      if (hits.isEmpty) return null;
      f = hits.first;
      parent = f.id;
    }
    return f;
  }

  static DriveResponse _error(int status, String reason, String message) => DriveResponse.json(status, {
        'error': {
          'code': status,
          'message': message,
          'errors': [
            {'domain': 'global', 'reason': reason, 'message': message},
          ],
        },
      });

  @override
  Future<DriveResponse> send(DriveRequest r) async {
    log.add('${r.method} ${r.url.path}');
    for (final f in _fails) {
      if (f.times > 0 && f.match(r)) {
        f.times--;
        if (f.landed == true) _answer(r);
        if (f.landed != null) throw DriveNetworkError('injected');
        return f.raw != null ? DriveResponse(f.status, utf8.encode(f.raw!)) : _error(f.status, f.reason, 'injected');
      }
    }
    return _answer(r);
  }

  DriveResponse _answer(DriveRequest r) {
    if (r.headers['Authorization'] != 'Bearer $token') return _error(401, 'authError', 'Invalid Credentials');
    final seg = r.url.pathSegments;
    final upload = seg.first == 'upload';
    final rest = seg.sublist(upload ? 4 : 3);
    final q = r.url.queryParameters;
    return switch ((r.method, upload, rest.length)) {
      ('GET', false, 0) => _list(q),
      ('POST', false, 0) => _createFolder(r),
      ('POST', true, 0) when q['uploadType'] == 'multipart' => _multipart(r),
      ('POST', true, 0) when q['uploadType'] == 'resumable' => _startSession(r),
      ('PUT', true, 0) when q['uploadType'] == 'resumable' => _finishSession(r, q['upload_id'] ?? ''),
      ('PATCH', true, 1) => _replace(rest.single, r.body),
      ('PATCH', false, 1) => _trash(rest.single, r),
      ('GET', false, 1) => q['alt'] == 'media' ? _download(rest.single) : _get(rest.single),
      _ => _error(400, 'badRequest', 'FakeDrive does not know ${r.method} ${r.url}'),
    };
  }

  FakeFile? _live(String id) {
    final f = files[id];
    return f == null || _gone(f) ? null : f;
  }

  DriveResponse _list(Map<String, String> q) {
    final m = RegExp(r"^'([^']+)' in parents and trashed = false$").firstMatch(q['q'] ?? '');
    if (m == null) return _error(400, 'invalid', 'Invalid Value');
    if (!(q['fields'] ?? '').startsWith('nextPageToken,files(')) return _error(400, 'invalidParameter', 'Invalid field selection');
    final all = files.values.where((f) => f.parent == m[1] && !_gone(f)).toList().reversed.toList();
    final start = int.parse(q['pageToken'] ?? '0');
    final page = all.skip(start).take(min(pageSize, int.parse(q['pageSize'] ?? '100'))).toList();
    final next = start + page.length;
    return DriveResponse.json(200, {
      'files': [for (final f in page) f.json()],
      if (next < all.length) 'nextPageToken': '$next',
    });
  }

  /// A new file from create metadata; null when the parent is not a live folder.
  FakeFile? _create(Map<String, dynamic> meta, List<int>? bytes) {
    final parent = ((meta['parents'] as List?) ?? const ['root']).single as String;
    if (parent != 'root' && !(_live(parent)?.isFolder ?? false)) return null;
    final stored = [...?bytes];
    if (corruptUploads && stored.isNotEmpty) stored[0] ^= 0xff;
    return add(meta['name'] as String, parent: parent, bytes: bytes == null ? null : stored);
  }

  DriveResponse _created(FakeFile? f) => f == null ? _error(404, 'notFound', 'File not found') : DriveResponse.json(200, f.json(sha: !omitSha256));

  DriveResponse _createFolder(DriveRequest r) {
    final meta = jsonDecode(utf8.decode(r.body)) as Map<String, dynamic>;
    if (meta['mimeType'] != driveFolderMime) return _error(400, 'badRequest', 'a file needs the upload URL');
    return _created(_create(meta, null));
  }

  DriveResponse _multipart(DriveRequest r) {
    final b = RegExp(r'^multipart/related; boundary=(\S+)$').firstMatch(r.headers['Content-Type'] ?? '')?[1];
    if (b == null) return _error(400, 'badRequest', 'not multipart/related');
    final body = r.body;
    final head = utf8.encode('--$b\r\n');
    final second = indexOfBytes(body, utf8.encode('\r\n--$b\r\n'));
    final metaStart = indexOfBytes(body, utf8.encode('\r\n\r\n')) + 4;
    final mediaStart = indexOfBytes(body, utf8.encode('\r\n\r\n'), second + 2) + 4;
    final end = indexOfBytes(body, utf8.encode('\r\n--$b--'), mediaStart);
    if (indexOfBytes(body, head) != 0 || second < 0 || end < 0 || end + 6 + b.length != body.length) return _error(400, 'badRequest', 'bad multipart body');
    final meta = jsonDecode(utf8.decode(body.sublist(metaStart, second))) as Map<String, dynamic>;
    return _created(_create(meta, body.sublist(mediaStart, end)));
  }

  DriveResponse _startSession(DriveRequest r) {
    final id = 's${_sessions.length + 1}';
    _sessions[id] = {
      'meta': jsonDecode(utf8.decode(r.body)),
      'length': int.parse(r.headers['X-Upload-Content-Length'] ?? '-1'),
    };
    return DriveResponse(200, const [], headers: {'location': 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=$id'});
  }

  DriveResponse _finishSession(DriveRequest r, String id) {
    final s = _sessions.remove(id);
    if (s == null) return _error(404, 'notFound', 'no such upload session');
    if (s['length'] != r.body.length) return _error(400, 'badRequest', 'length differs from X-Upload-Content-Length');
    return _created(_create(s['meta'] as Map<String, dynamic>, r.body));
  }

  DriveResponse _replace(String id, List<int> bytes) {
    final f = _live(id);
    if (f == null || f.isFolder) return _error(404, 'notFound', 'File not found: $id');
    f.bytes = [...bytes];
    if (corruptUploads && f.bytes.isNotEmpty) f.bytes[0] ^= 0xff;
    return DriveResponse.json(200, f.json(sha: !omitSha256));
  }

  DriveResponse _trash(String id, DriveRequest r) {
    final f = _live(id);
    if (f == null) return _error(404, 'notFound', 'File not found: $id');
    if ((jsonDecode(utf8.decode(r.body)) as Map)['trashed'] != true) return _error(400, 'badRequest', 'only trashing is supported');
    f.trashed = true;
    return DriveResponse.json(200, {'id': id, 'trashed': true});
  }

  DriveResponse _download(String id) {
    final f = _live(id);
    return f == null || f.isFolder ? _error(404, 'notFound', 'File not found: $id') : DriveResponse(200, f.bytes);
  }

  DriveResponse _get(String id) {
    final f = _live(id);
    return f == null ? _error(404, 'notFound', 'File not found: $id') : DriveResponse.json(200, f.json());
  }
}

/// Hands out [tokens] in order, moving on each time one is invalidated; the last one repeats.
class FakeTokens implements DriveTokens {
  FakeTokens(this.tokens);

  final List<String> tokens;
  final invalidated = <String>[];
  var _next = 0;

  @override
  Future<String> token() async => tokens[min(_next, tokens.length - 1)];

  @override
  Future<void> invalidate(String stale) async {
    invalidated.add(stale);
    _next++;
  }
}
