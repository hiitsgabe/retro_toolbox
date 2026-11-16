import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';

import 'launchbox_matcher.dart';
import 'launchbox_models.dart';
import 'launchbox_platforms.dart';
import 'launchbox_store.dart';

final launchboxServiceProvider = Provider<LaunchboxService>((ref) => LaunchboxService.instance);

typedef LaunchboxMatcher = Future<List<int?>> Function(List<String> titles, List<LaunchboxGame> games);

/// Reads what the import stored: fills a console's games with their
/// LaunchBox data and looks up one game's full record.
class LaunchboxService {
  LaunchboxService({Future<Directory> Function()? supportDir, @visibleForTesting LaunchboxMatcher? matcher})
      : _supportDir = supportDir ?? getApplicationSupportDirectory,
        _matcher = matcher ?? matchLaunchboxIds;

  static final instance = LaunchboxService();

  final Future<Directory> Function() _supportDir;
  final LaunchboxMatcher _matcher;

  /// Decoded platforms by name, oldest first. A platform file holds up to tens
  /// of thousands of games, so only the last two stay: the console being
  /// browsed and the one before it.
  final _platforms = <String, Future<Map<int, LaunchboxGame>?>>{};
  static const _keptPlatforms = 2;

  Future<LaunchboxStore> store() async => LaunchboxStore(Directory(path.join((await _supportDir()).path, 'launchbox')));

  Future<LaunchboxManifest?> manifest() async => (await store()).readManifest();

  /// [games] with LaunchBox fields filled in their details, or [games]
  /// unchanged when the console has no platform, the platform was not
  /// imported, or anything fails (logged with debugPrint, never thrown).
  Future<List<Game>> enrich(Console console, List<Game> games) async {
    final platform = launchboxPlatformFor(console);
    if (platform == null || games.isEmpty) return games;
    try {
      final store = await this.store();
      final manifest = await store.readManifest();
      if (manifest == null || !manifest.platforms.contains(platform)) return games;
      final byId = await _platform(store, platform);
      if (byId == null) return games;

      final ids = await _matchIds(store, console, platform, manifest.etag, games, byId);
      return [
        for (final g in games)
          if (byId[ids[g.title]] case final lb?) g.copyWith(details: _fill(g.details, lb, platform)) else g,
      ];
    } catch (e) {
      debugPrint('LaunchBox enrich failed for ${console.id}: $e');
      return games;
    }
  }

  /// The full record for the details page, or null.
  Future<LaunchboxGame?> lookup(String platform, int id) async {
    try {
      return (await _platform(await store(), platform))?[id];
    } catch (e) {
      debugPrint('LaunchBox lookup failed for $platform/$id: $e');
      return null;
    }
  }

  /// Drops in-memory caches (after an import or when metadata is turned off).
  void invalidate() => _platforms.clear();

  /// The future is cached, not the result, so two callers on the same platform
  /// share one decode. A failed or missing read is dropped so the next call
  /// tries the disk again.
  Future<Map<int, LaunchboxGame>?> _platform(LaunchboxStore store, String platform) {
    final cached = _platforms.remove(platform);
    if (cached != null) return _platforms[platform] = cached;

    final load = _loadPlatform(store, platform);
    _platforms[platform] = load;
    while (_platforms.length > _keptPlatforms) {
      _platforms.remove(_platforms.keys.first);
    }
    load.then((v) {
      if (v == null && _platforms[platform] == load) _platforms.remove(platform);
    }, onError: (Object _) {
      if (_platforms[platform] == load) _platforms.remove(platform);
    });
    return load;
  }

  static Future<Map<int, LaunchboxGame>?> _loadPlatform(LaunchboxStore store, String platform) async {
    final bytes = await store.readPlatformBytes(platform);
    if (bytes == null) return null;
    final games = await _decode(bytes);
    return {for (final g in games) g.id: g};
  }

  /// LaunchBox id per game title, from the console's match file when it was
  /// made from the same import and knows every title, else matched afresh.
  Future<Map<String, int?>> _matchIds(
    LaunchboxStore store,
    Console console,
    String platform,
    String? etag,
    List<Game> games,
    Map<int, LaunchboxGame> byId,
  ) async {
    final file = File(path.join(store.root.path, 'match_${launchboxPlatformSlug(console.id)}.json'));
    final cached = await _readMatchFile(file, etag, platform);
    if (cached != null && games.every((g) => cached.containsKey(g.title))) return cached;

    final matched = await _matcher([for (final g in games) path.basenameWithoutExtension(g.filename)], byId.values.toList());
    final ids = {for (var i = 0; i < games.length; i++) games[i].title: matched[i]};
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'etag': etag, 'platform': platform, 'ids': ids}));
    } on FileSystemException catch (e) {
      // Matching again next time is the only cost.
      debugPrint('LaunchBox match cache write failed: $e');
    }
    return ids;
  }

  /// Null when the file is missing, unreadable, or from another import.
  static Future<Map<String, int?>?> _readMatchFile(File file, String? etag, String platform) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['etag'] != etag || json['platform'] != platform) return null;
      final ids = json['ids'];
      if (ids is! Map) return null;
      return {
        for (final e in ids.entries)
          if (e.key is String && (e.value == null || e.value is int)) e.key as String: e.value as int?,
      };
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static GameDetails _fill(GameDetails? details, LaunchboxGame lb, String platform) {
    // LaunchBox writes 0 with 0 votes for a game nobody rated.
    final rated = lb.rating != null && !(lb.rating == 0 && (lb.ratingCount ?? 0) == 0);
    return (details ?? const GameDetails()).copyWith(
      launchboxId: lb.id,
      launchboxPlatform: platform,
      rating: rated ? lb.rating : null,
      ratingCount: rated ? lb.ratingCount : null,
      genres: lb.genres,
      maxPlayers: lb.maxPlayers,
      cooperative: lb.cooperative,
      releaseDate: details?.releaseDate ?? lb.releaseDate,
    );
  }
}

// Top-level so the isolate closure captures only the bytes.
Future<List<LaunchboxGame>> _decode(List<int> bytes) => Isolate.run(() => LaunchboxStore.decodePlatform(bytes));
