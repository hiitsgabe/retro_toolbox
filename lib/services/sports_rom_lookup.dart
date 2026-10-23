import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/utils/rom_search.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';
import 'package:retro_toolbox/widgets/menu_grid/sport_slug.dart';

/// A game found in the user's console catalog for a sports patcher.
class RomCatalogMatch {
  final Console console;
  final Game game;
  const RomCatalogMatch(this.console, this.game);
}

/// Looks up a sports game in the loaded console catalog so the wizard can offer
/// a direct download instead of a manual file pick, and in the folders where
/// the user keeps that console's games.
class SportsRomLookup {
  /// The best file of [gameId] in [dirs], then in [looseDirs]: its name, or
  /// the name of the folder it sits in (an extracted download), fuzzy-matches
  /// the game's search terms and its extension is one the patcher takes. Looks
  /// one folder deep: into every folder of [dirs] (the console's own download
  /// folders), but only into the folders of [looseDirs] named after the game
  /// (the general download folder, whose other folders are other systems'),
  /// and never into [skip]. Ranks by folder (the order of [dirs] then
  /// [looseDirs]), then by score, then by the game's extension order (a .cue
  /// before its .bin, an image before the archive it came from), then away
  /// from extra tracks, then by region. Null when nothing matches or no folder
  /// exists.
  static Future<String?> findLocal({
    required Iterable<String> dirs,
    required String gameId,
    Iterable<String> looseDirs = const [],
    Iterable<String> skip = const [],
  }) async {
    final terms = gameSearchTerms(gameId);
    final extensions = gameRomExtensions(gameId);
    final region = gamePreferredRegion(gameId);
    String? best;
    List<int>? bestKey;
    final skipped = {for (final s in skip) if (s.isNotEmpty) p.canonicalize(s)};
    final own = dirs.toSet();
    bool namedAfterGame(String folder) => romBestScore(folder, terms) >= kRomMatchThreshold;
    final roots = [
      for (final dir in own) (dir, (String _) => true),
      for (final dir in looseDirs.toSet().difference(own)) (dir, namedAfterGame),
    ];
    for (final (dirRank, (dir, enter)) in roots.indexed) {
      if (dir.isEmpty || !await Directory(dir).exists()) continue;
      await for (final entity in _files(Directory(dir), depth: 1, skip: skipped, enter: enter)) {
        final name = p.basename(entity.path);
        final rank = extensions.indexOf(p.extension(name).toLowerCase());
        if (rank < 0) continue;
        final parent = p.basename(p.dirname(entity.path));
        final inSubfolder = !p.equals(p.dirname(entity.path), dir);
        var score = romBestScore(name, terms);
        if (inSubfolder) score = max(score, romBestScore(parent, terms));
        if (score < kRomMatchThreshold) continue;
        final extraTrack = _extraTrack.hasMatch(name) ? 1 : 0;
        // Folder first: any match (50+) is a near-exact title, and a loose
        // file in the general folder may be another system's copy.
        final key = [dirRank, -score, rank, extraTrack, ...romTiebreak(name, region)];
        if (bestKey == null || compareTiebreak(key, bestKey) < 0) {
          bestKey = key;
          best = entity.path;
        }
      }
    }
    return best;
  }

  /// [findLocal] on another isolate: a full-set folder takes a moment to
  /// score, and the ROM step is the first screen, so its frames and d-pad stay
  /// free. Static so the closure sent over holds only these arguments: one
  /// built in a widget's method captures the State too, which cannot be sent.
  static Future<String?> findLocalInBackground({
    required List<String> dirs,
    required String gameId,
    List<String> looseDirs = const [],
    List<String> skip = const [],
  }) =>
      Isolate.run(() => findLocal(dirs: dirs, gameId: gameId, looseDirs: looseDirs, skip: skip));

  /// "Track 2" and up, with or without parentheses or leading zeros: the
  /// audio tracks of a .bin set. "Track 1" / "(Track 01)" is the data track.
  static final _extraTrack = RegExp(r'\btrack\s*0*([2-9]|[1-9]\d+)\b', caseSensitive: false);

  /// What a downloaded [archiveName] in [dir] became once extracted: a file of
  /// the same base name with one of the game's extensions next to it, or the
  /// best such file in a folder named after it. Null when neither exists.
  static String? extractedFor({required String dir, required String archiveName, required String gameId}) {
    final extensions = gameRomExtensions(gameId).where((e) => e != '.zip').toList();
    final base = p.basenameWithoutExtension(archiveName);
    for (final ext in extensions) {
      final sibling = p.join(dir, '$base$ext');
      if (File(sibling).existsSync()) return sibling;
    }
    final folder = Directory(p.join(dir, base));
    if (!folder.existsSync()) return null;
    String? best;
    List<int>? bestKey;
    try {
      for (final entity in folder.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final rank = extensions.indexOf(p.extension(name).toLowerCase());
        if (rank < 0) continue;
        final key = [rank, _extraTrack.hasMatch(name) ? 1 : 0, name.length];
        if (bestKey == null || compareTiebreak(key, bestKey) < 0) {
          bestKey = key;
          best = entity.path;
        }
      }
    } on FileSystemException {
      return null;
    }
    return best;
  }

  /// Files under [dir], [depth] folders down, entering only the folders whose
  /// name passes [enter] and none in [skip] (canonical paths); unreadable
  /// folders are skipped.
  static Stream<File> _files(Directory dir, {required int depth, Set<String> skip = const {}, bool Function(String name)? enter}) async* {
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }
    for (final entity in entries) {
      if (p.basename(entity.path).startsWith('.')) continue;
      if (entity is File) {
        yield entity;
      } else if (entity is Directory &&
          depth > 0 &&
          (enter?.call(p.basename(entity.path)) ?? true) &&
          !skip.contains(p.canonicalize(entity.path))) {
        yield* _files(entity, depth: depth - 1, skip: skip);
      }
    }
  }

  /// The catalog service [find] loads consoles' games with. A seam for tests.
  @visibleForTesting
  static CatalogService Function() catalogService = CatalogService.new;

  /// Finds [gameName] on any catalog console matching [platform] (e.g. "snes").
  /// Loads each candidate console's games via CatalogService (which returns a
  /// list without disturbing the app's selected-console state). Returns the
  /// first fuzzy title match, or null when the catalog has no such game.
  static Future<RomCatalogMatch?> find({
    required List<Console> consoles,
    required String gameId,
    required String platform,
  }) async {
    final wantSlug = consoleArtSlugForText(platform);
    final terms = gameSearchTerms(gameId);
    final region = gamePreferredRegion(gameId);
    debugPrint('[SportsRomLookup] gameId=$gameId platform="$platform" wantSlug=$wantSlug terms=$terms region=$region consoles=${consoles.length}');
    if (wantSlug == null) return null;
    final service = catalogService();

    for (final console in consoles) {
      final slug = consoleArtSlug(console);
      if (slug != wantSlug) continue;
      debugPrint('[SportsRomLookup] console id=${console.id} name="${console.name}" slug=$slug');
      List<Game> games;
      try {
        games = await service.loadCatalog(console.id);
      } catch (e) {
        debugPrint('[SportsRomLookup] loadCatalog failed for ${console.id}: $e');
        continue;
      }
      debugPrint('[SportsRomLookup] ${console.id} loaded ${games.length} games');
      if (games.isEmpty) continue;

      Game? best;
      var bestScore = 0;
      List<int>? bestTie;
      for (final g in games) {
        final score = romBestScore(g.title, terms);
        if (score < kRomMatchThreshold) continue;
        final tie = romTiebreak(g.title, region);
        // Higher score wins; on a tie, the region/beta/length key decides.
        if (score > bestScore || (score == bestScore && bestTie != null && compareTiebreak(tie, bestTie) < 0)) {
          bestScore = score;
          bestTie = tie;
          best = g;
        }
      }
      debugPrint('[SportsRomLookup] best="${best?.title}" score=$bestScore (threshold $kRomMatchThreshold)');
      if (best != null) return RomCatalogMatch(console, best);
    }
    return null;
  }
}
