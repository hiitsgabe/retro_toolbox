import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/utils/formatters.dart';

const latestReleaseUrl = 'https://api.github.com/repos/hiitsgabe/retro_toolbox/releases/latest';
const releasesPageUrl = 'https://github.com/hiitsgabe/retro_toolbox/releases/latest';
const playStoreInstaller = 'com.android.vending';
const _timeout = Duration(seconds: 15);
const _userAgent = 'retro_toolbox-updater';

/// A failure with a message fit to show the user as is.
class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.size, this.sha256});
  final String name;
  final String url;
  final int size;

  /// Lowercase hex, from the API's `digest` (`sha256:<hex>`); null when absent.
  final String? sha256;
}

class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.htmlUrl, required this.notes, required this.assets});
  final String version;
  final String htmlUrl;
  final String notes;
  final List<ReleaseAsset> assets;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final page = json['html_url'] as String?;
    return ReleaseInfo(
      version: tag.startsWith(RegExp('[vV]')) ? tag.substring(1) : tag,
      // Only ever link out to GitHub.
      htmlUrl: page != null && isTrustedUpdateUrl(Uri.parse(page)) ? page : releasesPageUrl,
      notes: json['body'] as String? ?? '',
      assets: [
        for (final a in (json['assets'] as List? ?? const []).cast<Map<String, dynamic>>())
          ReleaseAsset(
            name: a['name'] as String,
            url: a['browser_download_url'] as String,
            size: (a['size'] as num).toInt(),
            sha256: switch (a['digest']) {
              final String d when d.startsWith('sha256:') => d.substring(7).toLowerCase(),
              _ => null,
            },
          ),
      ],
    );
  }

  ReleaseAsset? asset(String name) {
    for (final a in assets) {
      if (a.name == name) return a;
    }
    return null;
  }
}

/// https on GitHub, its API, or its download CDN (`*.githubusercontent.com`).
bool isTrustedUpdateUrl(Uri url) =>
    url.scheme == 'https' &&
    (url.host == 'github.com' || url.host == 'api.github.com' || url.host.endsWith('.githubusercontent.com'));

final _version = RegExp(r'^[vV]?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$');

bool isValidVersion(String v) => _version.hasMatch(v);

/// Compares versions like "v1.2.10" > "1.2.9"; "+build" is ignored and a
/// "-pre" release sorts before its release. Unreadable versions sort lowest.
int compareVersions(String a, String b) {
  final x = _version.firstMatch(a), y = _version.firstMatch(b);
  if (x == null || y == null) return (x == null ? 0 : 1) - (y == null ? 0 : 1);
  final xs = [for (final s in x.group(1)!.split('.')) int.parse(s)];
  final ys = [for (final s in y.group(1)!.split('.')) int.parse(s)];
  for (var i = 0; i < xs.length || i < ys.length; i++) {
    final d = (i < xs.length ? xs[i] : 0).compareTo(i < ys.length ? ys[i] : 0);
    if (d != 0) return d;
  }
  // ponytail: pre-release tags compare as a whole string ("rc10" < "rc9"); fine for occasional rcs.
  final xp = x.group(2), yp = y.group(2);
  if (xp == yp) return 0;
  if (xp == null) return 1;
  if (yp == null) return -1;
  return xp.compareTo(yp);
}

bool isNewerVersion(String release, String current) => compareVersions(release, current) > 0;

/// The release file this install updates from; null means "no in-app update,
/// open the release page" (desktop).
String? updateAssetName({required bool handheld, required String os, required Abi abi}) {
  if (handheld) return 'retro_toolbox_handheld_arm64.zip';
  if (os != 'android') return null;
  if (abi == Abi.androidArm64 || abi == Abi.androidX64) return 'retro_toolbox_arm64.apk';
  if (abi == Abi.androidArm) return 'retro_toolbox_arm32.apk';
  return 'retro_toolbox_universal.apk';
}

/// The changes part of the release notes: no title, no downloads table.
String releaseNotesExcerpt(String body, {int maxLines = 6}) {
  final out = <String>[];
  for (var line in const LineSplitter().convert(body)) {
    line = line.trim();
    if (line.startsWith('---') || line.toLowerCase().startsWith('### downloads')) break;
    if (line.isEmpty || line.startsWith('## ')) continue;
    line = line.replaceFirst(RegExp(r'^#+\s*'), '').replaceFirst(RegExp(r'^[-*]\s+'), '• ');
    out.add(line);
    if (out.length == maxLines) break;
  }
  return out.join('\n');
}

/// Size, then SHA-256. A release without a checksum is refused: on the
/// handheld nothing else vouches for code that runs as root.
Future<void> verifyDownload(File file, ReleaseAsset asset) async {
  if (asset.sha256 == null) throw const UpdateException(cantVerifyMessage);
  final length = await file.length();
  if (length != asset.size) {
    throw UpdateException('Download incomplete ($length of ${asset.size} bytes). Try again.');
  }
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != asset.sha256) {
    throw const UpdateException('Download corrupted (checksum mismatch). Try again.');
  }
}

const cantVerifyMessage = "Can't verify this download: the release lists no checksum.";
const _unsafePackage = 'The update package is not a valid handheld build.';

/// Where handheld-zip entry [name] goes under `.update/` ("retrotoolbox/…" or
/// "Retro Toolbox.sh"), null for the bare `ports/` folders. Throws for links,
/// special files, absolute paths, `..`/`.` segments, backslashes and anything
/// outside `ports/retrotoolbox/` or `ports/Retro Toolbox.sh`.
String? handheldEntryTarget(String name, {required int mode, bool symlink = false}) {
  final type = mode & 0xf000; // unix file type, when the zip was made on unix
  if (symlink || (type != 0 && type != 0x8000 && type != 0x4000)) throw const UpdateException(_unsafePackage);
  if (name.startsWith('/') || name.contains('\\') || name.contains('\x00')) throw const UpdateException(_unsafePackage);
  final parts = name.split('/');
  if (parts.last.isEmpty) parts.removeLast(); // directory entry
  if (parts.isEmpty || parts.any((s) => s.isEmpty || s == '.' || s == '..')) {
    throw const UpdateException(_unsafePackage);
  }
  final path = parts.join('/');
  if (path == 'ports' || path == 'ports/retrotoolbox') return null;
  if (path == 'ports/Retro Toolbox.sh') return 'Retro Toolbox.sh';
  if (path.startsWith('ports/retrotoolbox/')) return path.substring('ports/'.length);
  throw const UpdateException(_unsafePackage);
}

/// Executables in the staged tree; everything else is 0644.
bool _isExecutable(String target) =>
    target.endsWith('.sh') || target == 'retrotoolbox/flutter-pi' || target.startsWith('retrotoolbox/bin/');

/// Unpacks the handheld zip into [updateDir]. Every entry is checked before
/// anything is written; one bad entry rejects the whole package. Modes from
/// the zip are ignored.
Future<void> _extractHandheldZip(String zipPath, String updateDir) async {
  final input = InputFileStream(zipPath);
  try {
    final entries = [
      for (final e in ZipDecoder().decodeStream(input))
        (e, handheldEntryTarget(e.name, mode: e.mode, symlink: e.isSymbolicLink)),
    ];
    final executables = <String>[];
    for (final (entry, target) in entries) {
      if (target == null) continue;
      final out = p.joinAll([updateDir, ...target.split('/')]);
      if (!entry.isFile) {
        Directory(out).createSync(recursive: true);
        continue;
      }
      Directory(p.dirname(out)).createSync(recursive: true);
      final stream = OutputFileStream(out);
      try {
        entry.writeContent(stream);
      } finally {
        await stream.close();
      }
      if (File(out).lengthSync() != entry.size) throw UpdateException('Could not write $target.');
      if (_isExecutable(target)) executables.add(out);
    }
    if (!Platform.isWindows) {
      // Explicit modes: 0644 files / 0755 folders, then 0755 for executables.
      // Best effort: exFAT/FAT refuse chmod, and have no modes to fix anyway.
      await Process.run('chmod', ['-R', 'u=rwX,go=rX', updateDir]);
      if (executables.isNotEmpty) await Process.run('chmod', ['755', ...executables]);
    }
  } finally {
    await input.close();
  }
}

/// Flushes writes to the SD card so a power cut can't reorder them.
Future<void> _sync() async {
  if (Platform.isLinux) await Process.run('sync', const []);
}

/// Unpacks the handheld zip (`ports/retrotoolbox/…`, `ports/Retro Toolbox.sh`)
/// into `<portRoot>/.update/`, synced, READY written last. The launcher swaps
/// it in at the next start.
Future<void> stageHandheldUpdate(File zip, Directory portRoot) async {
  final update = Directory(p.join(portRoot.path, '.update'));
  if (update.existsSync()) await update.delete(recursive: true);
  try {
    final zipPath = zip.path, updatePath = update.path;
    await Isolate.run(() => _extractHandheldZip(zipPath, updatePath));
    if (!Directory(p.join(update.path, 'retrotoolbox')).existsSync() ||
        !File(p.join(update.path, 'Retro Toolbox.sh')).existsSync()) {
      throw const UpdateException(_unsafePackage);
    }
    await _sync();
    await File(p.join(update.path, 'READY')).writeAsString('ready\n');
    await _sync();
  } catch (_) {
    if (update.existsSync()) await update.delete(recursive: true);
    rethrow;
  }
}

class UpdateService {
  UpdateService({
    this.releaseUrl = latestReleaseUrl,
    Future<Directory> Function()? cacheDir,
    String? portRoot,
    this.isTrusted = isTrustedUpdateUrl,
    this.freeSpace = DirectoryService.getFreeSpace,
  })  : _cacheDir = cacheDir ?? getApplicationCacheDirectory,
        portRoot = portRoot ?? p.dirname(Platform.resolvedExecutable);

  final String releaseUrl;
  final Future<Directory> Function() _cacheDir;

  /// The handheld port folder (flutter-pi sits in ports/retrotoolbox/).
  final String portRoot;

  /// Every request and redirect hop must pass; tests swap in loopback.
  final bool Function(Uri url) isTrusted;
  final Future<int> Function(String path) freeSpace;

  static const _channel = MethodChannel('retro_toolbox/updater');

  /// Downloads live in `<cache>/updates/`: the only folder the Android
  /// FileProvider exposes.
  Future<Directory> _downloads() async => Directory(p.join((await _cacheDir()).path, 'updates'));

  Future<ReleaseInfo> fetchLatest() => _network(() async {
        final client = HttpClient()..connectionTimeout = _timeout;
        try {
          final res = await _get(client, Uri.parse(releaseUrl), accept: 'application/vnd.github+json');
          final body = await res.transform(utf8.decoder).join().timeout(_timeout);
          switch (res.statusCode) {
            case 200:
              return ReleaseInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
            case 403 when res.headers.value('x-ratelimit-remaining') == '0':
            case 429:
              throw const UpdateException('GitHub rate limit reached. Try again later.');
            case 404:
              throw const UpdateException('No releases published yet.');
            default:
              throw UpdateException('GitHub returned HTTP ${res.statusCode}.');
          }
        } finally {
          client.close(force: true);
        }
      });

  /// GET following redirects by hand, so every hop is checked before it is
  /// requested.
  Future<HttpClientResponse> _get(HttpClient client, Uri url, {String? accept}) async {
    for (var hop = 0; hop < 6; hop++) {
      if (!isTrusted(url)) throw UpdateException('Refusing to download from ${url.scheme}://${url.host}.');
      final req = await client.getUrl(url).timeout(_timeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      if (accept != null) req.headers.set(HttpHeaders.acceptHeader, accept);
      final res = await req.close().timeout(_timeout);
      final location = res.headers.value(HttpHeaders.locationHeader);
      if (!res.isRedirect || location == null) return res;
      await res.drain<void>();
      url = url.resolve(location);
    }
    throw const UpdateException('Too many redirects.');
  }

  /// Handheld staging holds the zip, the unpacked tree and the launcher's
  /// copy at once: about 4x the zip. Android: the APK plus the installed copy.
  Future<void> ensureSpace(ReleaseAsset asset, {required bool handheld}) async {
    final dir = handheld ? portRoot : (await _cacheDir()).path;
    final need = asset.size * (handheld ? 4 : 2);
    final free = await freeSpace(dir);
    if (free < need) {
      throw UpdateException('Not enough free space: the update needs ${formatBytes(need)}, ${formatBytes(free)} free.');
    }
  }

  /// Downloads [asset] into the app cache and verifies it; the file is
  /// deleted on any failure.
  Future<File> download(ReleaseAsset asset, void Function(double progress) onProgress) async {
    if (asset.sha256 == null) throw const UpdateException(cantVerifyMessage);
    final dir = await _downloads();
    if (dir.existsSync()) await dir.delete(recursive: true); // stale downloads
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, asset.name));
    try {
      await _network(() async {
        final client = HttpClient()..connectionTimeout = _timeout;
        try {
          final res = await _get(client, Uri.parse(asset.url));
          if (res.statusCode != 200) throw UpdateException('Download failed (HTTP ${res.statusCode}).');
          final sink = file.openWrite();
          var received = 0;
          try {
            await for (final chunk in res.timeout(_timeout)) {
              sink.add(chunk);
              received += chunk.length;
              if (asset.size > 0) onProgress((received / asset.size).clamp(0, 1).toDouble());
            }
          } finally {
            await sink.close();
          }
        } finally {
          client.close(force: true);
        }
      });
      await verifyDownload(file, asset);
      return file;
    } catch (_) {
      if (file.existsSync()) await file.delete();
      rethrow;
    }
  }

  Future<void> stageHandheld(File zip) async {
    try {
      await stageHandheldUpdate(zip, Directory(portRoot));
    } finally {
      if (zip.existsSync()) await zip.delete();
    }
  }

  /// The package that installed this Android app (Play is
  /// [playStoreInstaller]); null when unknown or sideloaded.
  Future<String?> installerPackage() => _channel.invokeMethod<String>('installerPackage');

  /// Hands the APK to the system installer. False when the app may not
  /// install packages yet: Android's settings page for that was opened.
  Future<bool> installApk(File apk) async =>
      await _channel.invokeMethod<bool>('installApk', {'path': apk.path}) ?? false;

  static Future<T> _network<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on SocketException {
      throw const UpdateException("Can't reach GitHub. Check your connection.");
    } on TimeoutException {
      throw const UpdateException('GitHub took too long to answer. Try again.');
    } on HandshakeException {
      throw const UpdateException("Can't reach GitHub securely. Check the device clock and connection.");
    } on HttpException catch (e) {
      throw UpdateException('Network error: ${e.message}');
    }
  }
}
