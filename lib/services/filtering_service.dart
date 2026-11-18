import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/game_group_model.dart';
import 'package:retro_toolbox/services/game_groups.dart';

/// [rating] pulled toward [mean] as if [m] more people had voted the mean, so
/// a 5.0 from one vote doesn't outrank a 4.5 from hundreds.
double bayesianRating(double rating, int votes, double mean, {int m = 10}) =>
    (votes / (votes + m)) * rating + (m / (votes + m)) * mean;

class FilteringService {
  static FilterResult filterAndPaginate(FilterInput input) {
    final games = input.games;
    final filter = input.filter;
    final skip = input.skip;
    final limit = input.limit;

    List<Game> allMatched;
    if (input.groupVersions) {
      // A game shows when one of its versions passes; the region filter's
      // order (else the default) picks which one is the entry.
      final regions = filter.regions.isEmpty ? defaultRegionOrder : filter.regions.toList();
      allMatched = [
        for (final group in buildGameGroups(games))
          if (groupEntry(group, (g) => _matchesFilter(g, input, checkText: false), text: input.filterText, regions: regions) case final entry?) entry,
      ];
    } else {
      allMatched = [
        for (final game in games)
          if (_matchesFilter(game, input)) game,
      ];
    }

    allMatched.sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));

    final key = _sortKey(filter.sort, games);
    if (key != null) {
      // Games without the key go last; equal keys keep name order (the sort
      // isn't stable, so the name is compared explicitly).
      allMatched.sort((a, b) {
        final ka = key(a), kb = key(b);
        if (ka != kb) {
          if (ka == null) return 1;
          if (kb == null) return -1;
          return kb.compareTo(ka);
        }
        return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
      });
    }

    final paginatedGames = allMatched.skip(skip).take(limit).toList();

    return FilterResult(
      games: paginatedGames,
      totalCount: allMatched.length,
      hasMore: skip + limit < allMatched.length,
    );
  }

  /// The value [sort] orders by, largest first (null: a game lacks it), or
  /// null for the name order the list already has. [games] is the whole
  /// console, unfiltered.
  static int? Function(Game)? _sortKey(CatalogSort sort, List<Game> games) => switch (sort) {
        CatalogSort.name => null,
        CatalogSort.sizeDesc => (g) => g.size > 0 ? g.size : null,
        CatalogSort.sizeAsc => (g) => g.size > 0 ? -g.size : null,
        CatalogSort.newest => (g) => g.details?.releaseDate ?? g.details?.launchboxReleaseDate,
        CatalogSort.popular => (g) => g.details?.popularity,
        CatalogSort.topRated => _ratingKey(games),
      };

  /// The Bayesian score against the mean of [games], scaled to an int to share
  /// the comparator. A rating with no votes counts as no rating. The mean is
  /// the whole console's, so another filter never reorders two games.
  static int? Function(Game) _ratingKey(List<Game> games) {
    double? rating(Game g) => (g.details?.ratingCount ?? 0) > 0 ? g.details?.rating : null;
    final ratings = games.map(rating).whereType<double>().toList();
    if (ratings.isEmpty) return (_) => null;
    final mean = ratings.reduce((a, b) => a + b) / ratings.length;
    return (g) {
      final r = rating(g);
      return r == null ? null : (bayesianRating(r, g.details!.ratingCount!, mean) * 1e6).round();
    };
  }

  static bool _hasPlayers(GameDetails? details, String players) => switch (players) {
        '1' => details?.maxPlayers == 1,
        '2+' => (details?.maxPlayers ?? 0) >= 2,
        'coop' => details?.cooperative == true,
        _ => false,
      };

  static bool _matchesFilter(Game game, FilterInput input, {bool checkText = true}) {
    final filterText = input.filterText.toLowerCase();
    final filter = input.filter;
    final favoriteGameIds = input.favoriteGameIds;
    final inLibraryStatus = input.inLibraryStatus;

    if (filter.showFavoritesOnly && favoriteGameIds != null) {
      if (!favoriteGameIds.contains(game.gameId)) return false;
    }

    if (filter.showInLibraryOnly && inLibraryStatus != null) {
      if (inLibraryStatus[game.gameId] != GameStatus.downloaded && inLibraryStatus[game.gameId] != GameStatus.extracted) {
        return false;
      }
    }

    if (checkText && filterText.isNotEmpty) {
      final titleMatch = game.displayTitle.toLowerCase().contains(filterText);
      final originalMatch = game.title.toLowerCase().contains(filterText);
      if (!titleMatch && !originalMatch) return false;
    }

    // LaunchBox data lives in the details, so these come before the DAT
    // metadata check below.
    final details = game.details;
    if (filter.genres.isNotEmpty && !(details?.genres.any(filter.genres.contains) ?? false)) return false;
    if (filter.players.isNotEmpty && !filter.players.any((p) => _hasPlayers(details, p))) return false;
    if (filter.minRating > 0) {
      final rating = details?.rating;
      if (rating == null || rating < filter.minRating) return false;
    }

    final metadata = game.metadata;
    if (metadata == null) return true;

    if (filter.regions.isNotEmpty) {
      if (metadata.regions.isNotEmpty && !metadata.regions.any((region) => filter.regions.contains(region))) {
        return false;
      }
    }

    if (filter.languages.isNotEmpty) {
      if (metadata.languages.isNotEmpty && !metadata.languages.any((language) => filter.languages.contains(language))) {
        return false;
      }
    }

    if (filter.categories.isNotEmpty && !filter.categories.any((category) => metadata.categories.contains(category))) {
      return false;
    }

    if (filter.dumpQualities.isNotEmpty) {
      if (metadata.dumpQualities.isEmpty) {
        if (!filter.dumpQualities.contains('goodDump')) return false;
      } else {
        final hasAllowedDumpQuality = metadata.dumpQualities.any((quality) => filter.dumpQualities.contains(quality.name));
        if (!hasAllowedDumpQuality) return false;
      }
    }

    if (filter.romTypes.isNotEmpty) {
      if (metadata.romTypes.isEmpty) {
        if (!filter.romTypes.contains('normal')) return false;
      } else {
        final hasAllowedRomType = metadata.romTypes.any((type) => filter.romTypes.contains(type.name));
        if (!hasAllowedRomType) return false;
      }
    }

    if (filter.modifications.isNotEmpty) {
      if (metadata.modifications.isEmpty) {
        if (!filter.modifications.contains('none')) return false;
      } else {
        final hasAllowedModification = metadata.modifications.any((mod) => filter.modifications.contains(mod.name));
        if (!hasAllowedModification) return false;
      }
    }

    if (filter.distributionTypes.isNotEmpty) {
      if (metadata.distributionTypes.isEmpty) {
        if (!filter.distributionTypes.contains('standard')) return false;
      } else {
        final hasAllowedDistribution = metadata.distributionTypes.any((dist) => filter.distributionTypes.contains(dist.name));
        if (!hasAllowedDistribution) return false;
      }
    }

    return true;
  }
}

class FilterInput {
  final List<Game> games;
  final String filterText;
  final CatalogFilter filter;
  final int skip;
  final int limit;
  final Set<String>? favoriteGameIds;
  final Map<String, GameStatus>? inLibraryStatus;

  /// One entry per game (see buildGameGroups).
  final bool groupVersions;

  const FilterInput({
    required this.games,
    required this.filterText,
    required this.filter,
    this.skip = 0,
    required this.limit,
    this.favoriteGameIds,
    this.inLibraryStatus,
    this.groupVersions = false,
  });
}

class FilterResult {
  final List<Game> games;
  final int totalCount;
  final bool hasMore;

  const FilterResult({
    required this.games,
    required this.totalCount,
    required this.hasMore,
  });
}
