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

const latestReleaseUrl = 'https://api.github.com/repos/hiitsgabe/retro_toolbox/releases/latest';
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
    return ReleaseInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      htmlUrl: json['html_url'] as String? ?? 'https://github.com/hiitsgabe/retro_toolbox/releases/latest',
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

/// Compares dotted numeric versions ("v1.2.10" > "1.2.9"). A leading "v",
/// "+build" and "-pre" suffixes are ignored.
// ponytail: pre-releases compare equal to their release; /releases/latest never returns one.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final core = (v.startsWith('v') ? v.substring(1) : v).split('+').first.split('-').first;
    return [for (final s in core.split('.')) int.tryParse(s) ?? 0];
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
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

/// Size, then SHA-256 when the release lists one.
Future<void> verifyDownload(File file, ReleaseAsset asset) async {
  final length = await file.length();
  if (length != asset.size) {
    throw UpdateException('Download incomplete ($length of ${asset.size} bytes). Try again.');
  }
  if (asset.sha256 == null) return;
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != asset.sha256) {
    throw const UpdateException('Download corrupted (checksum mismatch). Try again.');
  }
}

/// Unpacks the handheld zip (`ports/retrotoolbox/…`, `ports/Retro Toolbox.sh`)
/// into `<portRoot>/.update/`, READY written last. The launcher swaps it in at
/// the next start.
Future<void> stageHandheldUpdate(File zip, Directory portRoot) async {
  final update = Directory(p.join(portRoot.path, '.update'));
  if (update.existsSync()) await update.delete(recursive: true);
  final raw = p.join(update.path, 'raw');
  try {
    final zipPath = zip.path;
    await Isolate.run(() => extractFileToDisk(zipPath, raw));
    final port = Directory(p.join(raw, 'ports', 'retrotoolbox'));
    final launcher = File(p.join(raw, 'ports', 'Retro Toolbox.sh'));
    if (!port.existsSync() || !launcher.existsSync()) {
      throw const UpdateException('The update package is not a handheld build.');
    }
    await port.rename(p.join(update.path, 'retrotoolbox'));
    await launcher.rename(p.join(update.path, 'Retro Toolbox.sh'));
    await Directory(raw).delete(recursive: true);
    await File(p.join(update.path, 'READY')).writeAsString('ready\n');
  } catch (_) {
    if (update.existsSync()) await update.delete(recursive: true);
    rethrow;
  }
}

class UpdateService {
  UpdateService({this.releaseUrl = latestReleaseUrl, Future<Directory> Function()? cacheDir, String? portRoot})
      : _cacheDir = cacheDir ?? getApplicationCacheDirectory,
        portRoot = portRoot ?? p.dirname(Platform.resolvedExecutable);

  final String releaseUrl;
  final Future<Directory> Function() _cacheDir;

  /// The handheld port folder (flutter-pi sits in ports/retrotoolbox/).
  final String portRoot;

  static const _channel = MethodChannel('retro_toolbox/updater');

  Future<ReleaseInfo> fetchLatest() => _network(() async {
        final client = HttpClient()..connectionTimeout = _timeout;
        try {
          final req = await client.getUrl(Uri.parse(releaseUrl)).timeout(_timeout);
          req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
          req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
          final res = await req.close().timeout(_timeout);
          final body = await res.transform(utf8.decoder).join().timeout(_timeout);
          switch (res.statusCode) {
            case 200:
              return ReleaseInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
            case 403 || 429:
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

  /// Downloads [asset] into the app cache and verifies it; the file is
  /// deleted on any failure.
  Future<File> download(ReleaseAsset asset, void Function(double progress) onProgress) async {
    final dir = await _cacheDir();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, asset.name));
    try {
      await _network(() async {
        final client = HttpClient()..connectionTimeout = _timeout;
        try {
          final req = await client.getUrl(Uri.parse(asset.url)).timeout(_timeout);
          req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
          final res = await req.close().timeout(_timeout);
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
