import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/utils/rom_search.dart';
import 'package:roms_downloader/widgets/menu_grid/console_slug.dart';
import 'package:roms_downloader/widgets/menu_grid/sport_slug.dart';

/// A game found in the user's console catalog for a sports patcher.
class RomCatalogMatch {
  final Console console;
  final Game game;
  const RomCatalogMatch(this.console, this.game);
}

/// Looks up a sports game in the loaded console catalog so the wizard can offer
/// a direct download instead of a manual file pick.
class SportsRomLookup {
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
    final service = CatalogService();

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
