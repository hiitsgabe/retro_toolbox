import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_ops.dart';

/// True for a trimmed `http`/`https` link with a host and no whitespace, control or bidi characters.
bool isValidDownloadUrl(String input) {
  final s = input.trim();
  // Whitespace, control and bidi-override characters could hide or alter what the user confirms.
  if (s.isEmpty || s.contains(RegExp(r'[\s\x00-\x1f\x7f\u200e\u200f\u202a-\u202e\u2066-\u2069]'))) return false;
  final uri = Uri.tryParse(s);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

/// [raw] reduced to a safe single file name: basename only, characters that
/// are illegal on common filesystems replaced, control characters dropped.
String safeFileName(String raw) {
  final base = raw.split(RegExp(r'[/\\]')).last;
  // Leading dots dropped too: a hidden file would be easy to lose (and as root, dotfiles matter).
  final name = base.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim().replaceFirst(RegExp(r'^[.\s]+'), '');
  return name.replaceAll(RegExp(r'[_ ]'), '').isEmpty ? 'download' : name;
}

/// The decoded last path segment of [url], through [safeFileName].
String fileNameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'download';
  try {
    final segs = uri.pathSegments;
    return safeFileName(segs.isEmpty ? '' : segs.last);
  } on FormatException {
    // invalid UTF-8 escape (e.g. %FF): use the undecoded segment
    return safeFileName(uri.path.split('/').last);
  }
}

/// The file name in a Content-Disposition header; `filename*` wins over `filename`.
String? fileNameFromContentDisposition(String? header) {
  if (header == null) return null;
  final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false).firstMatch(header);
  if (star != null) {
    try {
      return safeFileName(Uri.decodeComponent(star.group(1)!.trim()));
    } on FormatException {
      // not UTF-8: fall back to plain filename
    } on ArgumentError {
      // malformed escape: fall back to plain filename
    }
  }
  final plain = RegExp(r'filename\s*=\s*(?:"([^"]*)"|([^;]+))', caseSensitive: false).firstMatch(header);
  final value = plain == null ? null : (plain.group(1) ?? plain.group(2)!.trim());
  return value == null || value.isEmpty ? null : safeFileName(value);
}

/// The name the server suggests for [url] via Content-Disposition, or null.
/// Tries HEAD, then a GET that is dropped once the headers arrive.
Future<String?> probeFileName(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  Future<String?> ask(String method) async {
    final req = await client.openUrl(method, Uri.parse(url));
    final res = await req.close();
    if (res.statusCode >= 400) return null;
    return fileNameFromContentDisposition(res.headers.value('content-disposition'));
  }

  try {
    return await Future(() async {
      try {
        final head = await ask('HEAD');
        if (head != null) return head;
      } on Exception {
        // some servers reject HEAD; try GET
      }
      return ask('GET');
    }).timeout(const Duration(seconds: 10));
  } on Exception {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Downloads [url] to `<destPath>.part`, resuming it with a Range request when
/// it already exists, then renames it to exactly [destPath] (a [StateError] if
/// something is there now). Throws [HttpException] on a non-2xx response and
/// [TimeoutException] when the server goes quiet for [idleTimeout] (a dropped
/// Wi-Fi with no reset would otherwise hold the transfer slot forever); the
/// `.part` is kept for a retry.
Future<void> downloadToFile({
  required String url,
  required String destPath,
  required FileOpsProgress onProgress,
  HttpClient? client,
  Duration idleTimeout = const Duration(seconds: 60),
}) async {
  final http = client ?? HttpClient();
  http.connectionTimeout = const Duration(seconds: 30);
  // Resume offsets are raw bytes on disk, so never let the transfer be compressed.
  http.autoUncompress = false;
  final part = File('$destPath.part');
  try {
    var have = part.existsSync() ? part.lengthSync() : 0;
    final req = await http.getUrl(Uri.parse(url));
    req.followRedirects = true;
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
    final res = await req.close().timeout(idleTimeout);
    if (res.statusCode < 200 || res.statusCode > 299) {
      await res.drain<void>();
      // A stale .part the server can no longer range over would fail every retry.
      if (res.statusCode == 416) await part.delete();
      throw HttpException('HTTP ${res.statusCode}');
    }
    final resumed = res.statusCode == 206 && have > 0;
    if (!resumed) have = 0; // 200 ignores Range: the body is the whole file
    final len = res.contentLength;
    final total = len < 0 ? 0 : len + have;
    var done = have;
    onProgress(done, total);
    await part.parent.create(recursive: true);
    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var stalled = false;
    try {
      // addStream applies backpressure, so a slow disk can't buffer the file in RAM.
      // A stall ends the stream cleanly, so the .part keeps everything received; it fails below.
      await sink.addStream(res.timeout(idleTimeout, onTimeout: (s) {
        stalled = true;
        s.close();
      }).map((chunk) {
        done += chunk.length;
        onProgress(done, total);
        return chunk;
      }));
    } finally {
      await sink.close();
    }
    if (stalled) throw TimeoutException('No data for ${idleTimeout.inSeconds}s', idleTimeout);
    // The task's path (for Extract) is destPath, so land there or fail.
    if (FileSystemEntity.typeSync(destPath) != FileSystemEntityType.notFound) throw StateError('${p.basename(destPath)} already exists');
    await part.rename(destPath);
    onProgress(done, done);
  } finally {
    if (client == null) http.close(force: true);
  }
}

/// Paths handed out by [reserveDownloadPath] whose download hasn't finished this session.
final _reserved = <String>{};

/// A free path for [name] in [dir]: no file, no leftover `.part` and no
/// unfinished download this session uses it. Held until its [downloadJob] succeeds.
String reserveDownloadPath(String dir, String name) {
  final path = p.join(dir, FileOps.uniqueName(dir, name, reserved: (path) => _reserved.contains(path) || File('$path.part').existsSync()));
  _reserved.add(path);
  return path;
}

/// The task-queue job for [url] to [destPath] (from [reserveDownloadPath]).
/// Its first run drops any `.part` there (some other file's); a retry runs the
/// same job and resumes what the failed run left.
Future<void> Function(FileOpsProgress) downloadJob(String url, String destPath) {
  var first = true;
  return (onProgress) async {
    final part = File('$destPath.part');
    if (first && part.existsSync()) await part.delete();
    first = false;
    await downloadToFile(url: url, destPath: destPath, onProgress: onProgress);
    _reserved.remove(destPath);
  };
}
