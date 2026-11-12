import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:retro_toolbox/services/save_sync/drive_transport.dart';

const driveFolderMime = 'application/vnd.google-apps.folder';

/// One file or folder as Drive lists it.
class DriveFile {
  const DriveFile({required this.id, required this.name, required this.mimeType, required this.createdTime, this.size = 0, this.sha256, this.md5});

  factory DriveFile.fromJson(Map<String, dynamic> j) => DriveFile(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        mimeType: j['mimeType'] as String? ?? '',
        createdTime: DateTime.tryParse(j['createdTime'] as String? ?? '')?.toUtc() ?? DateTime.utc(1970),
        size: int.tryParse(j['size'] as String? ?? '') ?? 0,
        sha256: j['sha256Checksum'] as String?,
        md5: j['md5Checksum'] as String?,
      );

  final String id;
  final String name;
  final String mimeType;
  final DateTime createdTime;
  final int size;
  final String? sha256;
  final String? md5;

  bool get isFolder => mimeType == driveFolderMime;
}

/// Oldest first: by createdTime, then id. Same-name folders and files resolve in this order.
int oldestFirst(DriveFile a, DriveFile b) {
  final c = a.createdTime.compareTo(b.createdTime);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// A Drive call that failed.
class DriveError implements Exception {
  DriveError(this.status, this.reason, this.message);

  final int status;

  /// Drive's `error.errors[0].reason`; '' when the body had none.
  final String reason;
  final String message;

  @override
  String toString() => 'Google Drive error $status${reason.isEmpty ? '' : ' ($reason)'}: $message';
}

/// 403 storageQuotaExceeded.
class DriveFull extends DriveError {
  DriveFull(String message) : super(403, 'storageQuotaExceeded', message);

  @override
  String toString() => 'Drive is full: free some space in Google Drive (the Drive trash counts too) and try again. Nothing changed on this device.';
}

/// Google refused the token after a fresh one was asked for, or only the user can grant a new one.
class DriveSignInNeeded implements Exception {
  @override
  String toString() => 'Sign in to Google again.';
}

/// Drive's checksum of what it stored differs from what was sent.
class DriveChecksumMismatch implements Exception {
  DriveChecksumMismatch(this.name);

  final String name;

  @override
  String toString() => 'Google Drive stored a damaged copy of $name; it was discarded. Try again.';
}

/// Access tokens for one Google account.
abstract class DriveTokens {
  /// Throws [DriveSignInNeeded] when only the user can grant a token.
  Future<String> token();

  /// [stale] got a 401: forget it, so the next [token] is a new one.
  Future<void> invalidate(String stale);
}

/// The error a failed response stands for. The body may not be JSON (a gateway's error page).
DriveError driveError(DriveResponse r) {
  var reason = '';
  var message = 'HTTP ${r.status}';
  final j = r.json;
  if (j is Map<String, dynamic> && j['error'] is Map<String, dynamic>) {
    final e = j['error'] as Map<String, dynamic>;
    if (e['message'] is String) message = e['message'] as String;
    final errors = e['errors'];
    if (errors is List && errors.isNotEmpty && errors.first is Map && (errors.first as Map)['reason'] is String) {
      reason = (errors.first as Map)['reason'] as String;
    }
  }
  return reason == 'storageQuotaExceeded' ? DriveFull(message) : DriveError(r.status, reason, message);
}

/// Where [pattern] first occurs in [data] at or after [start]; -1 when it does not.
int indexOfBytes(List<int> data, List<int> pattern, [int start = 0]) {
  outer:
  for (var i = start; i <= data.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

String mimeOf(String name) {
  if (name.endsWith('.zip')) return 'application/zip';
  if (name.endsWith('.json')) return 'application/json';
  if (name.endsWith('.txt')) return 'text/plain';
  return 'application/octet-stream';
}

/// The few Drive v3 calls a hub needs, over [DriveTransport] with a bearer token.
///
/// A 401 gets one new token and one more try. 429, 5xx, the rate-limit 403s and a lost connection
/// ([DriveNetworkError]) back off (about 1, 2 and 4 seconds plus up to one second of jitter) for at most
/// [maxTries] tries. 403 storageQuotaExceeded is [DriveFull] at once. Every upload is checked against the
/// checksum Drive reports for what it stored.
class DriveApi {
  DriveApi(this._transport, this._tokens, {Future<void> Function(Duration)? sleep, Random? random, this.multipartLimit = 5000000})
      : _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
        _random = random ?? Random();

  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';
  static const _fields = 'id,name,mimeType,size,createdTime,sha256Checksum,md5Checksum';
  static const maxTries = 4;

  final DriveTransport _transport;
  final DriveTokens _tokens;
  final Future<void> Function(Duration) _sleep;
  final Random _random;

  /// Bodies up to this many bytes go up in one multipart request (Drive's limit for it is 5 MB);
  /// bigger ones through a resumable session.
  final int multipartLimit;

  static bool _retryable(DriveError e) =>
      e.status == 429 || e.status >= 500 || (e.status == 403 && (e.reason == 'rateLimitExceeded' || e.reason == 'userRateLimitExceeded'));

  Duration _backoff(int tries) => Duration(milliseconds: 1000 * (1 << (tries - 1)) + _random.nextInt(1001));

  static Map<String, String> _auth(String token) => {'Authorization': 'Bearer $token'};

  /// Sends what [build] makes with the current token. Statuses in [accept] count as success.
  /// With [retry] false only the 401 refresh happens; any other failure is thrown at once.
  ///
  /// A lost connection is sent again like a 5xx. Drive may have acted on the first one: a create can
  /// then leave a second copy with the same name and bytes, which the same-name rule collapses.
  Future<DriveResponse> _send(DriveRequest Function(String token) build, {Set<int> accept = const {}, bool retry = true}) async {
    var token = await _tokens.token();
    var refreshed = false;
    var tries = 0;
    while (true) {
      final DriveResponse r;
      try {
        r = await _transport.send(build(token));
      } on DriveNetworkError {
        tries++;
        if (!retry || tries >= maxTries) rethrow;
        await _sleep(_backoff(tries));
        continue;
      }
      if (r.ok || accept.contains(r.status)) return r;
      if (r.status == 401) {
        if (refreshed) throw DriveSignInNeeded();
        refreshed = true;
        await _tokens.invalidate(token);
        token = await _tokens.token();
        continue;
      }
      final e = driveError(r);
      tries++;
      if (!retry || !_retryable(e) || tries >= maxTries) throw e;
      await _sleep(_backoff(tries));
    }
  }

  static Map<String, dynamic> _object(DriveResponse r) {
    final j = r.json;
    if (j is Map<String, dynamic>) return j;
    throw DriveError(r.status, '', 'unexpected response from Google Drive');
  }

  static String _quote(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  /// Everything directly in folder [folderId] that is not in the trash, across every page.
  Future<List<DriveFile>> children(String folderId) async {
    final out = <DriveFile>[];
    String? page;
    do {
      final r = await _send((t) => DriveRequest(
            'GET',
            Uri.parse(_api).replace(queryParameters: {
              'q': "'${_quote(folderId)}' in parents and trashed = false",
              'fields': 'nextPageToken,files($_fields)',
              'pageSize': '1000',
              'spaces': 'drive',
              'corpora': 'user',
              if (page != null) 'pageToken': page,
            }),
            headers: _auth(t),
          ));
      final j = _object(r);
      for (final f in j['files'] as List? ?? const []) {
        out.add(DriveFile.fromJson(f as Map<String, dynamic>));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<DriveFile> get(String id) async => DriveFile.fromJson(_object(await _send((t) => DriveRequest('GET', Uri.parse('$_api/$id?fields=$_fields'), headers: _auth(t)))));

  Future<DriveFile> createFolder(String name, String parentId) async => DriveFile.fromJson(_object(await _send((t) => DriveRequest(
        'POST',
        Uri.parse('$_api?fields=$_fields'),
        headers: {..._auth(t), 'Content-Type': 'application/json; charset=UTF-8'},
        body: utf8.encode(jsonEncode({'name': name, 'mimeType': driveFolderMime, 'parents': [parentId]})),
      ))));

  /// A new file [name] in folder [parentId].
  Future<DriveFile> createFile(String name, String parentId, List<int> bytes) async {
    final meta = {'name': name, 'parents': [parentId], 'mimeType': mimeOf(name)};
    final f = bytes.length <= multipartLimit ? await _multipart(meta, bytes) : await _resumable(meta, bytes);
    await _verify(f, bytes, discard: true);
    return f;
  }

  /// Replaces the content of file [id] (named [name]) in place.
  Future<DriveFile> updateFile(String id, String name, List<int> bytes) async {
    final f = DriveFile.fromJson(_object(await _send((t) => DriveRequest(
          'PATCH',
          Uri.parse('$_upload/$id?uploadType=media&fields=$_fields'),
          headers: {..._auth(t), 'Content-Type': mimeOf(name)},
          body: bytes,
        ))));
    await _verify(f, bytes, discard: false);
    return f;
  }

  Future<List<int>> download(String id) async => (await _send((t) => DriveRequest('GET', Uri.parse('$_api/$id?alt=media'), headers: _auth(t)))).body;

  /// Moves file [id] to the Drive trash, where Drive deletes it after 30 days. A file already gone is fine.
  Future<void> trash(String id) async {
    await _send(
      (t) => DriveRequest(
        'PATCH',
        Uri.parse('$_api/$id?fields=id,trashed'),
        headers: {..._auth(t), 'Content-Type': 'application/json; charset=UTF-8'},
        body: utf8.encode('{"trashed":true}'),
      ),
      accept: const {404},
    );
  }

  /// One request: the metadata part, then the bytes, between a boundary that never occurs in them.
  Future<DriveFile> _multipart(Map<String, Object> meta, List<int> bytes) async {
    String boundary;
    do {
      boundary = List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join();
    } while (indexOfBytes(bytes, utf8.encode('--$boundary')) >= 0);
    final body = (BytesBuilder(copy: false)
          ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode(meta)}\r\n'))
          ..add(utf8.encode('--$boundary\r\nContent-Type: ${meta['mimeType']}\r\n\r\n'))
          ..add(bytes)
          ..add(utf8.encode('\r\n--$boundary--')))
        .takeBytes();
    return DriveFile.fromJson(_object(await _send((t) => DriveRequest(
          'POST',
          Uri.parse('$_upload?uploadType=multipart&fields=$_fields'),
          headers: {..._auth(t), 'Content-Type': 'multipart/related; boundary=$boundary'},
          body: body,
        ))));
  }

  /// Starts a session, then sends every byte in one PUT. Drive's advice for any failure of that PUT is to
  /// start over, so a failed or dropped PUT backs off and opens a new session; an old one that never got
  /// every byte never makes a file.
  Future<DriveFile> _resumable(Map<String, Object> meta, List<int> bytes) async {
    for (var tries = 1;; tries++) {
      final start = await _send((t) => DriveRequest(
            'POST',
            Uri.parse('$_upload?uploadType=resumable&fields=$_fields'),
            headers: {
              ..._auth(t),
              'Content-Type': 'application/json; charset=UTF-8',
              'X-Upload-Content-Type': '${meta['mimeType']}',
              'X-Upload-Content-Length': '${bytes.length}',
            },
            body: utf8.encode(jsonEncode(meta)),
          ));
      final session = start.headers['location'];
      if (session == null) throw DriveError(start.status, '', 'Google Drive gave no upload session');
      try {
        return DriveFile.fromJson(_object(await _send(
          (t) => DriveRequest('PUT', Uri.parse(session), headers: {..._auth(t), 'Content-Type': '${meta['mimeType']}'}, body: bytes),
          retry: false,
        )));
      } on DriveNetworkError {
        if (tries >= maxTries) rethrow;
        await _sleep(_backoff(tries));
      } on DriveError catch (e) {
        if (e is DriveFull || tries >= maxTries) rethrow;
        await _sleep(_backoff(tries));
      }
    }
  }

  /// Drive's sha256 of what it stored must match [bytes]. A response without one gets one more
  /// metadata read, then md5 decides; a file Drive gives no checksum for passes, since every gen's
  /// own payloadSha256 is still checked on each pull. A new file that fails is trashed ([discard]).
  Future<void> _verify(DriveFile f, List<int> bytes, {required bool discard}) async {
    final got = f.sha256 != null ? f : await get(f.id);
    final ok = got.sha256 != null
        ? got.sha256!.toLowerCase() == sha256.convert(bytes).toString()
        : got.md5 == null || got.md5!.toLowerCase() == md5.convert(bytes).toString();
    if (ok) return;
    if (discard) await trash(f.id);
    throw DriveChecksumMismatch(f.name);
  }
}
