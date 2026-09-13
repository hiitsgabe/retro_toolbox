import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/utils/network.dart';
import 'package:roms_downloader/utils/title_metadata_parser.dart';
import 'package:roms_downloader/services/boxart_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _iaMetadataBase = 'https://archive.org/metadata/';
const _iaDownloadBase = 'https://archive.org/download/';

class CatalogService {
  /// The merged catalog of every installed addon. Invalidated by `clearCache`,
  /// which every catalog write calls.
  static MergedCatalog? _merged;
  final BoxartService _boxartService = BoxartService();

  /// The consoles of every installed addon, merged.
  Future<Map<String, Console>> getConsoles() async => (await mergedCatalog()).consoles;

  /// Where each url of a console comes from, in `console.urls` order.
  Future<List<ConsoleSource>> sourcesFor(String consoleId) async => (await mergedCatalog()).sources[consoleId] ?? const [];

  Future<MergedCatalog> mergedCatalog() async {
    final cache = _merged;
    if (cache != null && !cache.isEmpty) return cache;
    try {
      return buildCatalog(await AddonStore.open());
    } catch (e) {
      debugPrint('No catalog source configured yet: $e');
      return const MergedCatalog();
    }
  }

  /// Reads and merges the catalogs of [store]'s addons.
  Future<MergedCatalog> buildCatalog(AddonStore store) async {
    final catalogs = <AddonCatalog>[];
    for (final addon in store.load()) {
      final raw = await store.readCatalog(addon.id) ?? await _bundledCatalog(addon.id);
      if (raw == null) continue;
      try {
        catalogs.add((addonId: addon.id, consoles: parseConsoles(raw)));
      } catch (e) {
        // One addon's broken JSON must not take the others down.
        debugPrint('Unreadable catalog for addon ${addon.id}: $e');
      }
    }
    final merged = mergeCatalogs(catalogs);
    if (!merged.isEmpty) _merged = merged;
    return merged;
  }

  /// The example catalog bundled in the app (`assets/catalog/`, git-ignored).
  /// Only the built-in has one, as its last precedence: user file, asset,
  /// nothing.
  static Future<String?> _bundledCatalog(String addonId) async {
    if (addonId != kBuiltinAddonId) return null;
    try {
      return await rootBundle.loadString('assets/catalog/consoles.json');
    } catch (_) {
      return null;
    }
  }

  /// Forgets the merged catalog. Every catalog write calls this.
  static void clearCache() => _merged = null;

  static Console? consoleByIdSync(String? id) {
    if (id == null) return null;
    return _merged?.consoles[id];
  }

  static String _nameToId(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Public slug used to key a console in the catalog (derived from its name).
  static String consoleId(String name) => _nameToId(name);

  /// Extracts an archive.org item id from a bare id or a full item/details URL.
  /// Returns null if [input] isn't a plausible id or archive.org URL.
  static String? parseIaItemId(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('/') && !s.startsWith('http')) {
      return RegExp(r'^[\w\-.]+$').hasMatch(s) ? s : null;
    }
    return RegExp(r'archive\.org/(?:download|details)/([^/]+)').firstMatch(s)?.group(1);
  }

  static Map<String, Console> parseConsoles(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    final consoles = <String, Console>{};
    if (decoded is List) {
      // PyGame-compatible array format: each item is a system object with a "name".
      // Entries with "list_systems: true" are discovery endpoints: skip them here.
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        if (item['list_systems'] == true) continue;
        final name = item['name'] as String? ?? '';
        if (name.isEmpty) continue;
        final id = _nameToId(name);
        consoles[id] = Console.fromJson({'id': id, ...item});
      }
    } else if (decoded is Map<String, dynamic>) {
      // Legacy map format: top-level keys are console IDs.
      decoded.forEach((key, value) {
        consoles[key] = Console.fromJson({'id': key, ...Map<String, dynamic>.from(value)});
      });
    }
    return consoles;
  }

  Future<File> _userConsolesFile([String consolesFilePath = 'consoles.json']) async {
    final supportDir = await getApplicationSupportDirectory();
    return File(path.join(supportDir.path, 'config', consolesFilePath));
  }

  /// Strips `auth.token` from the whole catalog and stores what it finds in the
  /// vault.
  ///
  /// The catalog is the file the user shares, and its format allows a token
  /// inside; moving it to the vault on install keeps the secret out of that
  /// shared file. Where a `token` was, leaves `requires_token: true` so the
  /// user still gets the screen to type one.
  ///
  /// Returns the cleaned JSON. Does not validate format; [setCatalogFromJson]
  /// does.
  static Future<String> harvestAuthTokens(String jsonStr, {required SecretVault vault, required String addonId}) async {
    final decoded = jsonDecode(jsonStr);

    Future<void> harvest(String id, Map<dynamic, dynamic> item) async {
      final auth = item['auth'];
      if (auth is! Map) return;
      if (!auth.containsKey('token')) return;
      final token = auth.remove('token');
      // The marker replaces `containsKey`, not the value, so it stays even when
      // the token is empty.
      auth['requires_token'] = true;
      if (token is! String || token.isEmpty) return;
      final key = SecretRef.addonToken(addonId, id);
      // What is already in the vault is the newest: reinstalling an old catalog
      // must not restore a token the user has since rotated.
      if (await vault.read(key) != null) return;
      await vault.write(key, token);
    }

    if (decoded is List) {
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['name'] as String? ?? '';
        if (name.isEmpty) continue;
        // Discovery entries (`list_systems`) still pass through here: a token
        // inside one leaks just the same.
        await harvest(_nameToId(name), item);
      }
    } else if (decoded is Map) {
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        await harvest(entry.key.toString(), value);
      }
    } else {
      return jsonStr;
    }

    return jsonEncode(decoded);
  }

  /// Validates [jsonStr] parses into at least one console, saves it as the
  /// active catalog source, and clears caches. Throws on invalid content.
  Future<void> setCatalogFromJson(String jsonStr, {required SecretVault vault, required String addonId}) async {
    final cleaned = await harvestAuthTokens(jsonStr, vault: vault, addonId: addonId);
    final consoles = parseConsoles(cleaned);
    if (consoles.isEmpty) {
      throw const FormatException('No consoles found in the provided catalog.');
    }
    final file = await _userConsolesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(cleaned);
    clearCache();
  }

  /// Fetches a catalog from [url] and installs it. Throws on network/format error.
  Future<void> setCatalogFromUrl(String url, {required SecretVault vault, required String addonId}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} fetching catalog');
      }
      final body = await response.transform(utf8.decoder).join();
      await setCatalogFromJson(body, vault: vault, addonId: addonId);
    } finally {
      client.close();
    }
  }

  /// Appends [consoleObj] to a raw catalog JSON string, preserving its shape
  /// (PyGame array or legacy id-keyed map) and any existing entries such as
  /// list_systems discovery endpoints. Null/blank input yields a fresh array.
  /// Throws [StateError] if a console with [id] already exists.
  static String appendConsoleToRaw(String? rawJson, String id, Map<String, dynamic> consoleObj) {
    final trimmed = rawJson?.trim() ?? '';
    final obj = Map<String, dynamic>.from(consoleObj)..remove('id');

    if (trimmed.isEmpty) return jsonEncode([obj]);

    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map && _nameToId(item['name'] as String? ?? '') == id) {
          throw StateError('A console with id "$id" already exists.');
        }
      }
      return jsonEncode([...decoded, obj]);
    }
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey(id)) {
        throw StateError('A console with id "$id" already exists.');
      }
      return jsonEncode({...decoded, id: obj});
    }
    throw const FormatException('Unrecognized catalog JSON shape.');
  }

  /// Appends a single [console] to the user catalog (creating it from the
  /// bundled asset if needed), marks it as added, and clears caches.
  Future<void> addConsole(Console console) async {
    final file = await _userConsolesFile();
    String? raw;
    if (await file.exists()) {
      raw = await file.readAsString();
    } else {
      try {
        raw = await rootBundle.loadString('assets/catalog/consoles.json');
      } catch (_) {
        raw = null;
      }
    }
    final id = _nameToId(console.name);
    final merged = appendConsoleToRaw(raw, id, {...console.toJson(), 'added': true});
    await file.parent.create(recursive: true);
    await file.writeAsString(merged);
    clearCache();
  }

  /// Removes the user catalog, reverting to the bundled example (if any).
  Future<void> resetCatalog() async {
    final file = await _userConsolesFile();
    if (await file.exists()) await file.delete();
    clearCache();
  }

  Future<bool> hasUserCatalog() async => (await _userConsolesFile()).exists();

  Future<List<Game>> loadCatalog(String consoleId,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final merged = await mergedCatalog();
    final console = merged.consoles[consoleId];

    if (console == null) {
      debugPrint("Console with id '$consoleId' not found");
      return [];
    }

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

    return _fetchCatalog(console, merged.sources[consoleId] ?? const [],
        iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, tokens: tokens, onProgress: onProgress);
  }

  Future<List<Game>> _fetchCatalog(Console console, List<ConsoleSource> sources,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    List<Game> catalog = [];

    try {
      catalog = await fetchSources(client, console, sources,
          iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, tokens: tokens, onProgress: onProgress);
      catalog = await _boxartService.mutateGamesWithBoxarts(catalog, console);
      final cacheFile = await _getCacheFile(console.cacheFile);
      await cacheFile.writeAsString(jsonEncode(catalog.map((g) => g.toJson()).toList()));
    } catch (e) {
      debugPrint('Error fetching catalog: $e');
      rethrow;
    } finally {
      client.close();
    }

    return catalog;
  }

  /// Fetches every source in [sources] in parallel and returns all their games,
  /// each tagged with the addon that served it, sorted by title.
  ///
  /// Each source speaks with the auth and token of the addon that declared it
  /// (`tokens[addonId]`), so one addon's token never reaches another's server.
  Future<List<Game>> fetchSources(HttpClient client, Console console, List<ConsoleSource> sources,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final total = sources.length;
    var done = 0;
    Object? firstError;
    onProgress?.call(0, total);
    final results = await Future.wait(
      sources.map((source) => _fetchFromUrl(client, source, console,
                  iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, authToken: tokens[source.addonId])
              .then((games) {
            onProgress?.call(++done, total);
            return games;
          }).catchError((Object e) {
            // Keep the partial result when only some pages fail; the error
            // rises only when none delivered anything.
            firstError ??= e;
            onProgress?.call(++done, total);
            return <Game>[];
          })),
    );
    if (firstError != null && results.every((r) => r.isEmpty)) {
      throw firstError!;
    }

    return results.expand((games) => games).toList()..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<List<Game>> _fetchFromUrl(HttpClient client, ConsoleSource source, Console console,
      {String? iaAccessKey, String? iaSecretKey, String? authToken}) async {
    final url = source.url;
    if (_isArchiveOrgUrl(url)) {
      return _fetchFromUrlIA(client, source, console, iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey);
    }

    final request = await client.getUrl(Uri.parse(url));
    // `source.auth`, not `console.auth`: auth belongs to the url, since two
    // addons can serve the same console.
    final headers = buildDownloadHeaders(url, buildConsoleAuthHeaders(source.auth, tokenOverride: authToken));
    headers.forEach(request.headers.set);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: Failed to fetch catalog from $url');
    }

    final body = await response.transform(utf8.decoder).join();
    // Auto-detect: a JSON listing (e.g. from Retro Tools Server) vs HTML.
    final trimmed = body.trimLeft();
    final parsed = (trimmed.startsWith('[') || trimmed.startsWith('{'))
        ? _parseJsonListing(body, console, url)
        : await compute(_parseHtmlIsolate, [body, console.toJson(), url]);
    return parsed.map((entry) => Game.fromJson(entry).copyWith(sourceId: source.addonId)).toList();
  }

  Future<List<Game>> _fetchFromUrlIA(HttpClient client, ConsoleSource source, Console console,
      {String? iaAccessKey, String? iaSecretKey}) async {
    final itemId = _extractIAItemId(source.url);
    if (itemId == null) return [];

    final request = await client.getUrl(Uri.parse('$_iaMetadataBase$itemId'));

    // User-saved credentials take precedence over per-system auth config.
    final resolvedKey = iaAccessKey ?? (source.auth?['type'] == 'ia_s3' ? source.auth!['access_key'] as String? : null);
    final resolvedSecret = iaSecretKey ?? (source.auth?['type'] == 'ia_s3' ? source.auth!['secret_key'] as String? : null);
    if (resolvedKey != null && resolvedKey.isNotEmpty && resolvedSecret != null && resolvedSecret.isNotEmpty) {
      request.headers.set('Authorization', 'LOW $resolvedKey:$resolvedSecret');
    }

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: IA metadata fetch failed for $itemId');
    }

    final body = await response.transform(utf8.decoder).join();
    final parsed = await compute(_parseIAMetadataIsolate, [body, console.toJson(), itemId]);
    debugPrint('IA $itemId: body=${body.length}b parsed=${parsed.length} shouldUnzip=${console.shouldUnzip} fmts=${console.fileFormat}');
    return parsed.map((entry) => Game.fromJson(entry).copyWith(sourceId: source.addonId)).toList();
  }

  static bool _isArchiveOrgUrl(String url) => url.contains('archive.org/download/');

  static String? _extractIAItemId(String url) {
    final match = RegExp(r'archive\.org/download/([^/]+)').firstMatch(url);
    return match?.group(1);
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

  /// Forgets everything that depended on the addon list: each console's game
  /// cache files, and then the merged catalog.
  ///
  /// Order matters: `clearCatalogCache` iterates `getConsoles()` to find which
  /// files to delete, so it needs the old catalog. Reversed, it would leave
  /// behind the cache of a console only the removed addon served.
  Future<void> invalidateForAddonChange() async {
    await clearCatalogCache();
    clearCache();
  }
}

// Top-level isolate functions: cannot be instance methods.

List<Map<String, dynamic>> _parseIAMetadataIsolate(List<dynamic> args) {
  final body = args[0] as String;
  final console = args[1] as Map<String, dynamic>;
  final itemId = args[2] as String;

  final data = jsonDecode(body) as Map<String, dynamic>;
  final rawFiles = data['files'] as List<dynamic>? ?? [];

  final fileFormats = console['file_format'] != null
      ? List<String>.from(console['file_format'] as List).map((e) => e.toLowerCase()).toList()
      : <String>[];
  // Zipped sets (should_unzip) are stored as .zip on IA; the ROM formats
  // in file_format only exist inside the archives.
  final shouldUnzip = console['should_unzip'] as bool? ?? false;

  final out = <Map<String, dynamic>>[];

  for (final f in rawFiles) {
    final file = f as Map<String, dynamic>;
    final name = file['name'] as String? ?? '';
    if (name.isEmpty) continue;

    // Skip derivative files (thumbnails, metadata, etc.)
    if (file['source'] == 'derivative') continue;

    // should_unzip sources list .zip archives; otherwise list only file_format.
    final ext = name.contains('.') ? '.${name.split('.').last.toLowerCase()}' : '';
    if (shouldUnzip) {
      if (ext != '.zip') continue;
    } else if (fileFormats.isNotEmpty && !fileFormats.contains(ext)) {
      continue;
    }

    final sizeRaw = file['size'];
    final size = int.tryParse(sizeRaw?.toString() ?? '') ?? 0;
    final downloadUrl = '$_iaDownloadBase$itemId/${Uri.encodeComponent(name)}';
    // Items may nest files in subdirectories: the title is the basename.
    final title = name.split('/').last;
    final metadata = TitleMetadataParser.parseRomTitle(title).toJson();

    out.add({
      'title': title,
      'url': downloadUrl,
      'size': size,
      'consoleId': console['id'],
      'metadata': metadata,
    });
  }

  return out;
}

/// Parses a JSON listing (e.g. from Retro Tools Server): a top-level array, or
/// an object whose [list_json_file_location] key holds the array. Each item is
/// an object with a name ([list_item_id]) and optional size. Download URLs are
/// [baseUrl] + the encoded name, matching the HTML path.
List<Map<String, dynamic>> _parseJsonListing(String body, Console console, String baseUrl) {
  final decoded = jsonDecode(body);
  final List list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map<String, dynamic>) {
    final key = console.listJsonFileLocation;
    list = (decoded[key] is List) ? decoded[key] as List : const [];
  } else {
    return [];
  }

  final nameKey = console.listItemId;
  final fileFormats = console.fileFormat?.map((e) => e.toLowerCase()).toList() ?? const [];
  final shouldUnzip = console.shouldUnzip;
  final ignoreExtFilter = console.ignoreExtensionFiltering;

  final out = <Map<String, dynamic>>[];
  for (final item in list) {
    if (item is! Map) continue;
    final name = (item[nameKey] ?? item['name'])?.toString() ?? '';
    if (name.isEmpty) continue;
    final lower = name.toLowerCase();
    if (!ignoreExtFilter) {
      if (shouldUnzip) {
        if (!lower.endsWith('.zip')) continue;
      } else if (fileFormats.isNotEmpty && !fileFormats.any((ext) => lower.endsWith(ext))) {
        continue;
      }
    }
    final title = name.split('/').last;
    out.add({
      'title': title,
      'url': '$baseUrl${Uri.encodeComponent(name)}',
      'size': int.tryParse(item['size']?.toString() ?? '') ?? 0,
      'consoleId': console.id,
      'metadata': TitleMetadataParser.parseRomTitle(title).toJson(),
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
  final shouldUnzip = console['should_unzip'] as bool? ?? false;
  final fileFormats = console['file_format'] != null
      ? List<String>.from(console['file_format'] as List).map((e) => e.toLowerCase()).toList()
      : <String>[];

  final regExp = RegExp(
    // Configs use Python-flavor named groups ((?P<name>...)); Dart wants (?<name>...).
    ((console['regex'] as String?) ?? Console.fromJson(console).defaultRegex).replaceAll('(?P<', '(?<'),
    multiLine: true,
    dotAll: true,
  );
  final matches = regExp.allMatches(html);
  final out = <Map<String, dynamic>>[];

  for (final match in matches) {
    // Resolve the download URL: prefer id+template, fall back to href.
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
    String title = text ?? titleRaw ?? hrefGroup ?? idGroup ?? fullUrl;
    if (title == '.' || title == '..') continue;

    // Template-based downloads (id + download_url) have no filename in the URL;
    // give the title the console's extension so filenames/ids derive cleanly.
    if (idGroup != null && downloadUrlTemplate != null && fileFormats.isNotEmpty) {
      final lower = title.toLowerCase();
      if (!fileFormats.any((ext) => lower.endsWith(ext))) {
        title = '$title${fileFormats.first}';
      }
    }

    // File format filter (skip when ignore_extension_filtering is set).
    // should_unzip sources list .zip archives; otherwise list only file_format.
    if (!ignoreExtFilter) {
      final lowerTitle = title.toLowerCase();
      if (shouldUnzip) {
        if (!lowerTitle.endsWith('.zip')) continue;
      } else if (fileFormats.isNotEmpty && !fileFormats.any((ext) => lowerTitle.endsWith(ext))) {
        continue;
      }
    }

    final sizeStr = _tryNamedGroup(match, 'size');
    final size = sizeStr != null ? _parseSizeBytesIsolate(sizeStr) : 0;

    final metadata = TitleMetadataParser.parseRomTitle(title).toJson();
    // Some configs (e.g. ultranx) capture a banner_url group: use it as the
    // boxart, resolving relative paths against the catalog host.
    final banner = _tryNamedGroup(match, 'banner_url');
    out.add({
      'title': title,
      'url': fullUrl,
      'size': size,
      'consoleId': console['id'],
      'metadata': metadata,
      if (banner != null && banner.isNotEmpty) 'details': {'boxart': Uri.parse(baseUrl).resolve(banner).toString()},
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
