import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/game_details_model.dart';
import 'package:roms_downloader/utils/title_match.dart';

class BoxartService {
  static final Map<String, Map<String, String>> _boxartCache = {};

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

      return await compute(_process, [games, boxarts]);
    } catch (e) {
      debugPrint('mutateGamesWithBoxarts error: $e');
      return games;
    }
  }

  /// String config: an HTML directory listing of image files, matched by filename.
  Future<Map<String, String>> _fetchBoxartListing(String boxartBaseUrl) async {
    if (_boxartCache.containsKey(boxartBaseUrl)) {
      return _boxartCache[boxartBaseUrl]!;
    }
    final html = await _fetchBody(boxartBaseUrl);
    if (html == null) return {};
    final boxartMap = _parseBoxartHtml(html, boxartBaseUrl);
    _boxartCache[boxartBaseUrl] = boxartMap;
    return boxartMap;
  }

  /// Map config: a JSON document holding a list of items.
  /// { "url": ..., "list": "dot.path" (optional, default root),
  ///   "name": "field with the game name",
  ///   "id": "field with a serial/title id" (optional — matched exactly
  ///         against bracketed ids in filenames, e.g. "[SJBP52]"),
  ///   "image": "template with {field} placeholders" }
  Future<Map<String, String>> _fetchBoxartJsonMap(Map<String, dynamic> config) async {
    final url = config['url'] as String? ?? '';
    if (url.isEmpty) return {};
    if (_boxartCache.containsKey(url)) return _boxartCache[url]!;

    final body = await _fetchBody(url);
    if (body == null) return {};

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
    _boxartCache[url] = boxartMap;
    return boxartMap;
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

  Map<String, String> _parseBoxartHtml(String html, String baseUrl) {
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
}

List<Game> _process(List<dynamic> data) {
  final games = data[0] as List<Game>;
  final boxarts = data[1] as Map<String, String>;

  final tokenIndex = buildTokenIndex(boxarts.keys);

  final bracketedId = RegExp(r'[\[(]([A-Za-z0-9-]{4,12})[\])]');

  return games.map((game) {
    final gameNameWithoutExt = path.basenameWithoutExtension(game.filename);

    // Exact id match first: filenames carrying a serial/title id in brackets
    // (e.g. "007 - Golden Eye [SJBP52]") beat any fuzzy name matching.
    String? boxartUrl;
    for (final m in bracketedId.allMatches(gameNameWithoutExt)) {
      boxartUrl = boxarts['id:${m.group(1)!.toLowerCase()}'];
      if (boxartUrl != null) break;
    }

    boxartUrl ??= matchTitle(titleToMatch: gameNameWithoutExt, candidates: boxarts, tokenIndex: tokenIndex);

    // ponytail: fallback strips "(...)"/"[...]" groups so decorated names like
    // "Game (1982) (Mattel)" or "Game [SJBP52]" match plain boxart names.
    // May pick a wrong region variant; better than no art.
    if (boxartUrl == null) {
      final stripped = gameNameWithoutExt.replaceAll(RegExp(r'\s*[\[(][^\])]*[\])]'), '').trim();
      if (stripped.isNotEmpty && stripped != gameNameWithoutExt) {
        boxartUrl = matchTitle(titleToMatch: stripped, candidates: boxarts, tokenIndex: tokenIndex);
      }
    }

    if (boxartUrl != null) {
      return game.copyWith(details: GameDetails(boxart: boxartUrl));
    }

    return game;
  }).toList();
}
