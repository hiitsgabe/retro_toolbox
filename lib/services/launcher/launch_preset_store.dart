import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_check.dart';

/// Where the presets are downloaded from: the `LAUNCH_PRESETS_URL`
/// dart-define when it is https, else the file on main.
class LaunchPresetsSource {
  static const defaultUrl = 'https://raw.githubusercontent.com/hiitsgabe/retro_toolbox/main/launch_presets/launch_presets.json';

  static String resolve({String define = const String.fromEnvironment('LAUNCH_PRESETS_URL')}) =>
      define.startsWith('https://') ? define : defaultUrl;
}

/// The bundled seed and the downloaded copy, and which of them to use. Not
/// pure Dart (the seed comes from rootBundle through [seed]), so the check
/// tool never imports this file.
class LaunchPresetStore {
  LaunchPresetStore(
      {required this.url, required Future<String> Function() seed, required Future<Directory> Function() supportDir, HttpClient Function()? client})
      : _seed = seed,
        _supportDir = supportDir,
        _client = client ?? (() => HttpClient()..connectionTimeout = _timeout);

  /// The asset key of the seed, the same file as the repo's.
  static const seedAsset = 'launch_presets/launch_presets.json';

  static const _timeout = Duration(seconds: 10);

  final String url;
  final Future<String> Function() _seed;
  final Future<Directory> Function() _supportDir;
  final HttpClient Function() _client;

  /// Another source URL gets another cache file.
  String get cacheName => sha256.convert(utf8.encode(url)).toString().substring(0, 16);

  Future<File> _cacheFile() async => File('${(await _supportDir()).path}/launcher/presets/$cacheName.json');

  Future<File> _etagFile() async => File('${(await _supportDir()).path}/launcher/presets/$cacheName.etag');

  /// The valid copy, seed or cache, with the higher `version`; the seed on a
  /// tie, since it shipped with this app. An empty file when neither is
  /// valid. Never throws.
  Future<LaunchPresetFile> load() async {
    final seed = await _check(_seed);
    final cache = await _check(() async => (await _cacheFile()).readAsString());
    if (seed == null) return cache ?? LaunchPresetFile.empty;
    if (cache == null) return seed;
    return cache.version > seed.version ? cache : seed;
  }

  Future<LaunchPresetFile?> _check(Future<String> Function() read) async {
    try {
      final check = checkPresetFile(await read());
      return check.usable ? check.file : null;
    } catch (_) {
      return null;
    }
  }

  /// A conditional GET. Only a 200 whose body is a usable preset file
  /// replaces the cache; a 304, a junk body or any error keeps what was
  /// there. Never throws.
  Future<void> refresh() async {
    try {
      final cache = await _cacheFile();
      final etagFile = await _etagFile();
      final etag = await cache.exists() && await etagFile.exists() ? await etagFile.readAsString() : null;
      final client = _client();
      try {
        final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
        if (etag != null) request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
        final response = await request.close().timeout(_timeout);
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          return;
        }
        final bytes = await response.fold(BytesBuilder(copy: false), (b, chunk) => b..add(chunk)).timeout(_timeout);
        final body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
        if (!checkPresetFile(body).usable) return;
        await cache.parent.create(recursive: true);
        await cache.writeAsString(body);
        final fresh = response.headers.value(HttpHeaders.etagHeader);
        if (fresh != null) {
          await etagFile.writeAsString(fresh);
        } else if (await etagFile.exists()) {
          await etagFile.delete();
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // Offline, a stall or a full disk: the copy we had stays.
    }
  }
}
