import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/utils/network.dart';
import 'package:roms_downloader/utils/title_metadata_parser.dart';
import 'package:roms_downloader/services/boxart_service.dart';

const _iaMetadataBase = 'https://archive.org/metadata/';
const _iaDownloadBase = 'https://archive.org/download/';

class CatalogService {
  static final Map<String, Map<String, Console>> _consolesCache = {};
  final BoxartService _boxartService = BoxartService();

  Future<Map<String, Console>> getConsoles([String consolesFilePath = 'consoles.json']) async {
    if (_consolesCache.containsKey(consolesFilePath) && _consolesCache[consolesFilePath]!.isNotEmpty) {
      return _consolesCache[consolesFilePath]!;
    }

    String jsonStr = '';
    try {
      final supportDir = await getApplicationSupportDirectory();
      final consolesFile = File(path.join(supportDir.path, 'config', consolesFilePath));
      if (await consolesFile.exists()) {
        jsonStr = await consolesFile.readAsString();
      } else {
        jsonStr = await rootBundle.loadString('assets/$consolesFilePath');
      }
    } catch (e) {
      debugPrint('Error reading consoles file: $e');
      return {};
    }

    final decoded = jsonDecode(jsonStr);
    Map<String, Console> consoles;

    if (decoded is List) {
      // PyGame-compatible array format: each item is a system object with a "name" field.
      // Entries with "list_systems: true" are discovery endpoints — skip them here.
      consoles = {};
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        if (item['list_systems'] == true) continue;
        final name = item['name'] as String? ?? '';
        if (name.isEmpty) continue;
        final id = _nameToId(name);
        final consoleData = {'id': id, ...item};
        consoles[id] = Console.fromJson(consoleData);
      }
    } else if (decoded is Map<String, dynamic>) {
      // Legacy map format: top-level keys are console IDs.
      consoles = decoded.map((key, value) {
        final consoleData = {'id': key, ...Map<String, dynamic>.from(value)};
        return MapEntry(key, Console.fromJson(consoleData));
      });
    } else {
      consoles = {};
    }

    if (consoles.isNotEmpty) {
      _consolesCache[consolesFilePath] = consoles;
    }

    return consoles;
  }

  static String _nameToId(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<List<Game>> loadCatalog(String consoleId, {String? iaAccessKey, String? iaSecretKey, String? authToken}) async {
    final consoles = await getConsoles();

    if (!consoles.containsKey(consoleId)) {
      debugPrint("Console with id '$consoleId' not found");
      return [];
    }

    Console console = consoles[consoleId]!;

    final cacheFile = await _getCacheFile(console.cacheFile);
    if (await cacheFile.exists()) {
      try {
        final jsonStr = await cacheFile.readAsString();
        final List<Map<String, dynamic>> jsonList = await compute(_decodeGamesIsolate, jsonStr);
        final cachedResult = jsonList.map((json) => Game.fromJson(json)).toList();
        if (cachedResult.isNotEmpty && cachedResult.first.metadata != null) {
          final hasBoxarts = cachedResult.any((game) => game.details?.boxart != null);
          if (!hasBoxarts && console.boxarts != null) {
            final enrichedResult = await _boxartService.mutateGamesWithBoxarts(cachedResult, console);
            await cacheFile.writeAsString(jsonEncode(enrichedResult.map((g) => g.toJson()).toList()));
            return enrichedResult;
          }
          return cachedResult;
        }
      } catch (e) {
        debugPrint('Error reading cache: $e');
        await cacheFile.delete();
      }
    }

    return _fetchCatalog(console, iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, authToken: authToken);
  }

  Future<List<Game>> _fetchCatalog(Console console, {String? iaAccessKey, String? iaSecretKey, String? authToken}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    List<Game> catalog = [];

    try {
      final results = await Future.wait(
        console.urls.map((url) => _fetchFromUrl(client, url, console, iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, authToken: authToken)),
      );

      // Merge all results, sort alphabetically by title.
      catalog = results.expand((games) => games).toList()
        ..sort((a, b) => a.title.compareTo(b.title));

      catalog = await _boxartService.mutateGamesWithBoxarts(catalog, console);
      final cacheFile = await _getCacheFile(console.cacheFile);
      await cacheFile.writeAsString(jsonEncode(catalog.map((g) => g.toJson()).toList()));
    } catch (e) {
      debugPrint('Error fetching catalog: $e');
    } finally {
      client.close();
    }

    return catalog;
  }

  Future<List<Game>> _fetchFromUrl(HttpClient client, String url, Console console, {String? iaAccessKey, String? iaSecretKey, String? authToken}) async {
    if (_isArchiveOrgUrl(url)) {
      return _fetchFromUrlIA(client, url, console, iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey);
    }

    final request = await client.getUrl(Uri.parse(url));
    final headers = buildDownloadHeaders(url, _buildAuthHeaders(console.auth, tokenOverride: authToken));
    headers.forEach(request.headers.set);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: Failed to fetch catalog from $url');
    }

    final html = await response.transform(utf8.decoder).join();
    final parsed = await compute(_parseHtmlIsolate, [html, console.toJson(), url]);
    return parsed.map((entry) => Game.fromJson(entry)).toList();
  }

  Future<List<Game>> _fetchFromUrlIA(HttpClient client, String url, Console console, {String? iaAccessKey, String? iaSecretKey}) async {
    final itemId = _extractIAItemId(url);
    if (itemId == null) return [];

    final request = await client.getUrl(Uri.parse('$_iaMetadataBase$itemId'));

    // User-saved credentials take precedence over per-system auth config.
    final resolvedKey = iaAccessKey ?? (console.auth?['type'] == 'ia_s3' ? console.auth!['access_key'] as String? : null);
    final resolvedSecret = iaSecretKey ?? (console.auth?['type'] == 'ia_s3' ? console.auth!['secret_key'] as String? : null);
    if (resolvedKey != null && resolvedKey.isNotEmpty && resolvedSecret != null && resolvedSecret.isNotEmpty) {
      request.headers.set('Authorization', 'LOW $resolvedKey:$resolvedSecret');
    }

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: IA metadata fetch failed for $itemId');
    }

    final body = await response.transform(utf8.decoder).join();
    final parsed = await compute(_parseIAMetadataIsolate, [body, console.toJson(), itemId]);
    return parsed.map((entry) => Game.fromJson(entry)).toList();
  }

  static bool _isArchiveOrgUrl(String url) => url.contains('archive.org/download/');

  static String? _extractIAItemId(String url) {
    final match = RegExp(r'archive\.org/download/([^/]+)').firstMatch(url);
    return match?.group(1);
  }

  static Map<String, String> _buildAuthHeaders(Map<String, dynamic>? auth, {String? tokenOverride}) {
    if (auth == null) return {};
    // IA S3 auth is handled separately in _fetchFromUrlIA.
    if (auth['type'] == 'ia_s3') return {};

    final token = tokenOverride ?? auth['token'] as String?;
    if (token == null || token.isEmpty) return {};

    if (auth['cookies'] == true) {
      final cookieName = auth['cookie_name'] as String? ?? 'auth_token';
      return {'Cookie': '$cookieName=$token'};
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<File> _getCacheFile(String cacheFile) async {
    final dir = await getApplicationCacheDirectory();
    final cachedFilePath = '${dir.path}/$cacheFile';
    return File(cachedFilePath);
  }

  Future<void> clearCatalogCache([String? consoleId]) async {
    try {
      final consoles = await getConsoles();
      if (consoleId != null) {
        if (consoles.containsKey(consoleId)) {
          final console = consoles[consoleId]!;
          final cacheFile = await _getCacheFile(console.cacheFile);
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        }
      } else {
        final consoles = await getConsoles();
        for (final consoleId in consoles.keys) {
          await clearCatalogCache(consoleId);
        }
      }
    } catch (e) {
      debugPrint('Error clearing catalog cache: $e');
    }
  }
}

// Top-level isolate functions — cannot be instance methods.

List<Map<String, dynamic>> _parseIAMetadataIsolate(List<dynamic> args) {
  final body = args[0] as String;
  final console = args[1] as Map<String, dynamic>;
  final itemId = args[2] as String;

  final data = jsonDecode(body) as Map<String, dynamic>;
  final rawFiles = data['files'] as List<dynamic>? ?? [];

  final fileFormats = console['file_format'] != null
      ? List<String>.from(console['file_format'] as List).map((e) => e.toLowerCase()).toList()
      : <String>[];

  final out = <Map<String, dynamic>>[];

  for (final f in rawFiles) {
    final file = f as Map<String, dynamic>;
    final name = file['name'] as String? ?? '';
    if (name.isEmpty) continue;

    // Skip derivative files (thumbnails, metadata, etc.)
    if (file['source'] == 'derivative') continue;

    // Filter by file_format if specified.
    if (fileFormats.isNotEmpty) {
      final ext = name.contains('.') ? '.${name.split('.').last.toLowerCase()}' : '';
      if (!fileFormats.contains(ext)) continue;
    }

    final sizeRaw = file['size'];
    final size = int.tryParse(sizeRaw?.toString() ?? '') ?? 0;
    final downloadUrl = '$_iaDownloadBase$itemId/${Uri.encodeComponent(name)}';
    final metadata = TitleMetadataParser.parseRomTitle(name).toJson();

    out.add({
      'title': name,
      'url': downloadUrl,
      'size': size,
      'consoleId': console['id'],
      'metadata': metadata,
    });
  }

  return out;
}

List<Map<String, dynamic>> _parseHtmlIsolate(List<dynamic> args) {
  final html = args[0] as String;
  final console = args[1] as Map<String, dynamic>;
  // args[2] is the specific URL being fetched, used as the base for relative hrefs.
  final String baseUrl;
  if (args.length > 2 && args[2] is String) {
    baseUrl = args[2] as String;
  } else {
    final rawUrl = console['url'];
    baseUrl = rawUrl is List ? rawUrl.first as String : rawUrl as String;
  }

  final downloadUrlTemplate = console['download_url'] as String?;
  final ignoreExtFilter = console['ignore_extension_filtering'] as bool? ?? false;
  final fileFormats = console['file_format'] != null
      ? List<String>.from(console['file_format'] as List).map((e) => e.toLowerCase()).toList()
      : <String>[];

  final regExp = RegExp(
    (console['regex'] as String?) ?? Console.fromJson(console).defaultRegex,
    multiLine: true,
    dotAll: true,
  );
  final matches = regExp.allMatches(html);
  final out = <Map<String, dynamic>>[];

  for (final match in matches) {
    // Resolve the download URL — prefer id+template, fall back to href.
    String? fullUrl;
    final idGroup = _tryNamedGroup(match, 'id');
    final hrefGroup = _tryNamedGroup(match, 'href');

    if (idGroup != null && downloadUrlTemplate != null) {
      fullUrl = downloadUrlTemplate.replaceAll('<id>', idGroup);
    } else if (hrefGroup != null) {
      fullUrl = hrefGroup.startsWith('http') ? hrefGroup : '$baseUrl$hrefGroup';
    }

    if (fullUrl == null) continue;

    // Resolve the display title.
    final text = _tryNamedGroup(match, 'text');
    final titleRaw = _tryNamedGroup(match, 'title');
    final title = text ?? titleRaw ?? hrefGroup ?? idGroup ?? fullUrl;
    if (title == '.' || title == '..') continue;

    // File format filter (skip when ignore_extension_filtering is set).
    if (!ignoreExtFilter && fileFormats.isNotEmpty) {
      final lowerTitle = title.toLowerCase();
      if (!fileFormats.any((ext) => lowerTitle.endsWith(ext))) continue;
    }

    final sizeStr = _tryNamedGroup(match, 'size');
    final size = sizeStr != null ? _parseSizeBytesIsolate(sizeStr) : 0;

    final metadata = TitleMetadataParser.parseRomTitle(title).toJson();
    out.add({
      'title': title,
      'url': fullUrl,
      'size': size,
      'consoleId': console['id'],
      'metadata': metadata,
    });
  }

  return out;
}

/// Named group lookup that returns null instead of throwing when the group
/// doesn't exist in the pattern.
String? _tryNamedGroup(RegExpMatch match, String name) {
  try {
    return match.namedGroup(name);
  } catch (_) {
    return null;
  }
}

int _parseSizeBytesIsolate(String sizeStr) {
  try {
    final trimmed = sizeStr.trim();
    if (trimmed.isEmpty) return 0;
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-zA-Z]*)$').firstMatch(trimmed);
    if (match == null) return 0;
    final numVal = double.tryParse(match.group(1)!) ?? 0.0;
    final unit = match.group(2)!;
    switch (unit.toLowerCase()) {
      case 'k':
      case 'kb':
      case 'kib':
        return (numVal * 1024).round();
      case 'm':
      case 'mb':
      case 'mib':
        return (numVal * 1024 * 1024).round();
      case 'g':
      case 'gb':
      case 'gib':
        return (numVal * 1024 * 1024 * 1024).round();
      default:
        return numVal.round();
    }
  } catch (_) {
    return 0;
  }
}

List<Map<String, dynamic>> _decodeGamesIsolate(String jsonStr) {
  final list = jsonDecode(jsonStr) as List<dynamic>;
  return list.whereType<Map<String, dynamic>>().toList();
}
