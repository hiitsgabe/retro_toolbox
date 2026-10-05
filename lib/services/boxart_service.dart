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

  @visibleForTesting
  static void clearMemoryCache() => _boxartCache.clear();

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
        for (var i = 0; i < games.length; i++) urls[i] != null ? games[i].copyWith(details: GameDetails(boxart: urls[i])) : games[i],
      ];
    } catch (e) {
      debugPrint('mutateGamesWithBoxarts error: $e');
      return games;
    }
  }

  /// String config: an HTML directory listing of image files, matched by filename.
  Future<Map<String, String>> _fetchBoxartListing(String boxartBaseUrl) {
    // A multi-MB listing: regex over it must not run on the UI isolate.
    return _cachedListing(boxartBaseUrl, (html) => compute(_parseBoxartHtml, [html, boxartBaseUrl]));
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
    return _cachedListing(url, (body) async {
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
  /// old at most), else fetched and parsed, then kept in both.
  Future<Map<String, String>> _cachedListing(String url, Future<Map<String, String>> Function(String body) parse) async {
    final hit = _boxartCache[url] ?? await _readDiskCache(url);
    if (hit != null) return _boxartCache[url] = hit;

    final body = await _fetchBody(url);
    if (body == null) return {};
    final boxartMap = await parse(body);
    _boxartCache[url] = boxartMap;
    if (boxartMap.isNotEmpty) await _writeDiskCache(url, boxartMap);
    return boxartMap;
  }

  /// Cache file for a remote listing; null for bundled assets or when the
  /// cache dir is unavailable.
  static Future<File?> _diskCacheFile(String url) async {
    if (!url.startsWith('http')) return null;
    try {
      // FNV-1a: a stable short file name per URL (String.hashCode isn't
      // guaranteed stable across runs). The URL is also stored and checked.
      var h = 0x811c9dc5;
      for (final c in utf8.encode(url)) {
        h = ((h ^ c) * 0x01000193) & 0xffffffff;
      }
      final dir = await getApplicationCacheDirectory();
      return File(path.join(dir.path, 'boxarts_${h.toRadixString(16)}.json'));
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, String>?> _readDiskCache(String url) async {
    final file = await _diskCacheFile(url);
    if (file == null) return null;
    try {
      if (!await file.exists() || DateTime.now().difference(await file.lastModified()) > _diskCacheTtl) return null;
      final filePath = file.path;
      final json = await Isolate.run(() => jsonDecode(File(filePath).readAsStringSync()) as Map<String, dynamic>);
      if (json['url'] != url) return null;
      return Map<String, String>.from(json['boxarts'] as Map);
    } catch (e) {
      debugPrint('Box art cache read failed: $e');
      return null;
    }
  }

  static Future<void> _writeDiskCache(String url, Map<String, String> boxarts) async {
    final file = await _diskCacheFile(url);
    if (file == null) return;
    try {
      final filePath = file.path;
      await Isolate.run(() => File(filePath).writeAsStringSync(jsonEncode({'url': url, 'boxarts': boxarts})));
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
