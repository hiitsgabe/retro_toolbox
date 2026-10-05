import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/utils/title_match.dart';

class BoxartService {
  static final Map<String, Map<String, String>> _boxartCache = {};
  static const _diskCacheTtl = Duration(days: 7);
  static const _diskCacheFormat = 2; // bump when the parsed map's shape (or normalizeTitle) changes

  @visibleForTesting
  static void clearMemoryCache() => _boxartCache.clear();

  static Future<void> _pendingWrites = Future.value();

  @visibleForTesting
  static Future<void> flushDiskWrites() => _pendingWrites;

  /// Drops the cached listing (memory and disk) of one console's box art config.
  static Future<void> clearListingCache(Object config) async {
    final url = _configUrl(config);
    if (url == null) return;
    final key = _cacheKey(url, config);
    _boxartCache.remove(key);
    try {
      final file = await _diskCacheFile(key);
      if (file != null && await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Box art cache clear failed: $e');
    }
  }

  /// Drops every cached listing (memory and disk).
  static Future<void> clearAllListingCaches() async {
    _boxartCache.clear();
    try {
      final dir = await getApplicationCacheDirectory();
      await for (final f in dir.list()) {
        if (f is File && path.basename(f.path).startsWith('boxarts_')) await f.delete();
      }
    } catch (e) {
      debugPrint('Box art cache clear failed: $e');
    }
  }

  static String? _configUrl(Object config) => switch (config) {
        String url => url,
        Map<String, dynamic> map => map['url'] as String?,
        _ => null,
      };

  /// Cache identity: the parsed map depends on the URL and, for JSON-map
  /// configs, on every config field (list/name/id/image).
  static String _cacheKey(String url, Object config) => '$_diskCacheFormat|$url|${config is Map ? jsonEncode(config) : ''}';

  Future<List<Game>> mutateGamesWithBoxarts(List<Game> games, Console console) async {
    final config = console.boxarts;
    if (config == null) return games;

    try {
      final Map<String, String> boxarts;
      if (config is String) {
        boxarts = await _fetchBoxartListing(config);
      } else if (config is Map<String, dynamic>) {
        boxarts = await _fetchBoxartJsonMap(config);
      } else {
        return games;
      }
      if (boxarts.isEmpty) return games;

      final urls = await matchBoxartUrlsParallel([for (final g in games) path.basenameWithoutExtension(g.filename)], boxarts);
      return [
        for (var i = 0; i < games.length; i++) urls[i] != null ? games[i].copyWith(details: (games[i].details ?? const GameDetails()).copyWith(boxart: urls[i])) : games[i],
      ];
    } catch (e) {
      debugPrint('mutateGamesWithBoxarts error: $e');
      return games;
    }
  }

  /// String config: an HTML directory listing of image files, matched by filename.
  Future<Map<String, String>> _fetchBoxartListing(String boxartBaseUrl) {
    // A multi-MB listing: regex over it must not run on the UI isolate.
    return _cachedListing(boxartBaseUrl, boxartBaseUrl, (html) => compute(_parseBoxartHtml, [html, boxartBaseUrl]));
  }

  /// Map config: a JSON document holding a list of items.
  /// { "url": ..., "list": "dot.path" (optional, default root),
  ///   "name": "field with the game name",
  ///   "id": "field with a serial/title id" (optional — matched exactly
  ///         against bracketed ids in filenames, e.g. "[ABCD12]"),
  ///   "image": "template with {field} placeholders" }
  Future<Map<String, String>> _fetchBoxartJsonMap(Map<String, dynamic> config) async {
    final url = config['url'] as String? ?? '';
    if (url.isEmpty) return {};
    return _cachedListing(url, config, (body) async {
      dynamic node = jsonDecode(body);
      for (final part in (config['list'] as String? ?? '').split('.').where((s) => s.isNotEmpty)) {
        node = (node as Map<String, dynamic>)[part];
      }

      final nameKey = config['name'] as String? ?? 'name';
      final idKey = config['id'] as String?;
      final imageTemplate = config['image'] as String? ?? '{image}';
      final boxartMap = <String, String>{};
      for (final item in node as List<dynamic>) {
        if (item is! Map<String, dynamic>) continue;
        final name = item[nameKey]?.toString() ?? '';
        final image = imageTemplate.replaceAllMapped(
          RegExp(r'\{(\w+)\}'),
          (m) => item[m.group(1)]?.toString() ?? '',
        );
        if (name.isEmpty || image.isEmpty) continue;
        boxartMap[normalizeTitle(name)] = image;
        final id = idKey != null ? item[idKey]?.toString() ?? '' : '';
        if (id.isNotEmpty) boxartMap['id:${id.toLowerCase()}'] = image;
      }
      return boxartMap;
    });
  }

  /// Parsed listing for [url]: from memory, else from the app cache dir (a week
  /// old at most), else fetched and parsed, then kept in both. When the fetch
  /// fails an expired disk copy is still better than no art (offline handhelds).
  Future<Map<String, String>> _cachedListing(String url, Object config, Future<Map<String, String>> Function(String body) parse) async {
    final key = _cacheKey(url, config);
    final hit = _boxartCache[key] ?? await _readDiskCache(key);
    if (hit != null) return _boxartCache[key] = hit;

    final body = await _fetchBody(url);
    if (body == null) {
      final stale = await _readDiskCache(key, ignoreTtl: true);
      if (stale != null) _boxartCache[key] = stale;
      return stale ?? {};
    }
    final boxartMap = await parse(body);
    _boxartCache[key] = boxartMap;
    if (boxartMap.isNotEmpty) {
      final write = _writeDiskCache(key, boxartMap);
      _pendingWrites = Future.wait([_pendingWrites, write]);
      unawaited(write); // matching needn't wait for the disk
    }
    return boxartMap;
  }

  /// Cache file for a remote listing; null for bundled assets or when the
  /// cache dir is unavailable.
  static Future<File?> _diskCacheFile(String key) async {
    if (!key.startsWith('$_diskCacheFormat|http')) return null;
    try {
      // FNV-1a: a stable short file name per key (String.hashCode isn't
      // guaranteed stable across runs). The key is also stored and checked.
      var h = 0x811c9dc5;
      for (final c in utf8.encode(key)) {
        h = ((h ^ c) * 0x01000193) & 0xffffffff;
      }
      final dir = await getApplicationCacheDirectory();
      return File(path.join(dir.path, 'boxarts_${h.toRadixString(16)}.json'));
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, String>?> _readDiskCache(String key, {bool ignoreTtl = false}) async {
    final file = await _diskCacheFile(key);
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      // A clock behind the file's mtime (handhelds without an RTC) counts as expired.
      final age = DateTime.now().difference(await file.lastModified());
      if (!ignoreTtl && (age.isNegative || age > _diskCacheTtl)) return null;
      final filePath = file.path;
      final json = await Isolate.run(() => jsonDecode(File(filePath).readAsStringSync()) as Map<String, dynamic>);
      if (json['key'] != key) return null;
      return Map<String, String>.from(json['boxarts'] as Map);
    } catch (e) {
      debugPrint('Box art cache read failed: $e');
      return null;
    }
  }

  /// Written to a temp file then renamed, so a power cut never leaves a
  /// half-written cache behind.
  static Future<void> _writeDiskCache(String key, Map<String, String> boxarts) async {
    final file = await _diskCacheFile(key);
    if (file == null) return;
    try {
      final filePath = file.path;
      final tmpPath = '$filePath.${DateTime.now().microsecondsSinceEpoch}.tmp';
      await Isolate.run(() {
        File(tmpPath).writeAsStringSync(jsonEncode({'key': key, 'boxarts': boxarts}));
        File(tmpPath).renameSync(filePath);
      });
    } catch (e) {
      debugPrint('Box art cache write failed: $e');
    }
  }

  /// Loads a body from a bundled asset path or over HTTP.
  Future<String?> _fetchBody(String url) async {
    if (!url.startsWith('http')) {
      return rootBundle.loadString(url);
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    client.userAgent = 'Mozilla/5.0 (compatible; Flutter app)';
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        debugPrint('Failed to fetch boxarts: ${response.statusCode}');
        return null;
      }
      return await response.transform(utf8.decoder).join();
    } catch (e) {
      debugPrint('Error fetching boxarts: $e');
      return null;
    } finally {
      client.close();
    }
  }
}

Map<String, String> _parseBoxartHtml(List<String> args) {
  final html = args[0], baseUrl = args[1];
  final regExp = RegExp(r'<a href="([^"]+\.(png|jpg|jpeg|gif|webp))"[^>]*>', caseSensitive: false);
  final matches = regExp.allMatches(html);
  final boxartMap = <String, String>{};

  for (final match in matches) {
    final filename = match.group(1)!;
    final decodedFilename = Uri.decodeComponent(filename);
    final nameWithoutExt = path.basenameWithoutExtension(decodedFilename);
    final normalizedName = normalizeTitle(nameWithoutExt);
    final fullUrl = baseUrl.endsWith('/') ? '$baseUrl$filename' : '$baseUrl/$filename';
    boxartMap[normalizedName] = fullUrl;
  }

  return boxartMap;
}
