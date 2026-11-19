import 'package:flutter/foundation.dart';

enum CatalogSort { name, sizeDesc, sizeAsc, newest, popular, topRated }

class CatalogFilter {
  final Set<String> regions;
  final Set<String> languages;
  final Set<String> categories;
  final Set<String> mediaTypes;
  final Set<String> dumpQualities;
  final Set<String> romTypes;
  final Set<String> modifications;
  final Set<String> distributionTypes;
  final bool showFavoritesOnly;
  final bool showInLibraryOnly;
  final CatalogSort sort;
  // LaunchBox fields: a game without LaunchBox data fails any of these.
  final Set<String> genres;
  final Set<String> players; // '1', '2+', 'coop'
  final double minRating; // 0 is off

  const CatalogFilter({
    this.regions = const {'USA'},
    this.languages = const {},
    this.categories = const {},
    this.mediaTypes = const {},
    this.dumpQualities = const {'goodDump'},
    this.romTypes = const {'normal'},
    this.modifications = const {'none'},
    this.distributionTypes = const {'standard', 'multiCart'},
    this.showFavoritesOnly = false,
    this.showInLibraryOnly = false,
    this.sort = CatalogSort.name,
    this.genres = const {},
    this.players = const {},
    this.minRating = 0,
  });

  CatalogFilter copyWith({
    Set<String>? regions,
    Set<String>? languages,
    Set<String>? categories,
    Set<String>? mediaTypes,
    Set<String>? publishers,
    Set<String>? series,
    Set<String>? dumpQualities,
    Set<String>? romTypes,
    Set<String>? modifications,
    Set<String>? distributionTypes,
    bool? showFavoritesOnly,
    bool? showInLibraryOnly,
    CatalogSort? sort,
    String? version,
    int? minYear,
    int? maxYear,
    Set<String>? genres,
    Set<String>? players,
    double? minRating,
  }) {
    return CatalogFilter(
      regions: regions ?? this.regions,
      languages: languages ?? this.languages,
      categories: categories ?? this.categories,
      mediaTypes: mediaTypes ?? this.mediaTypes,
      dumpQualities: dumpQualities ?? this.dumpQualities,
      romTypes: romTypes ?? this.romTypes,
      modifications: modifications ?? this.modifications,
      distributionTypes: distributionTypes ?? this.distributionTypes,
      showFavoritesOnly: showFavoritesOnly ?? this.showFavoritesOnly,
      showInLibraryOnly: showInLibraryOnly ?? this.showInLibraryOnly,
      sort: sort ?? this.sort,
      genres: genres ?? this.genres,
      players: players ?? this.players,
      minRating: minRating ?? this.minRating,
    );
  }

  /// Whether any filter is off its default. [isActive] is true on a fresh
  /// install (the default hides bad dumps and non-USA sets), so the header icon
  /// asks this instead. Sort is not a filter.
  bool get differsFromDefault {
    const d = CatalogFilter();
    return !setEquals(regions, d.regions) ||
        !setEquals(languages, d.languages) ||
        !setEquals(categories, d.categories) ||
        !setEquals(mediaTypes, d.mediaTypes) ||
        !setEquals(dumpQualities, d.dumpQualities) ||
        !setEquals(romTypes, d.romTypes) ||
        !setEquals(modifications, d.modifications) ||
        !setEquals(distributionTypes, d.distributionTypes) ||
        showFavoritesOnly != d.showFavoritesOnly ||
        showInLibraryOnly != d.showInLibraryOnly ||
        !setEquals(genres, d.genres) ||
        !setEquals(players, d.players) ||
        minRating != d.minRating;
  }

  bool get isActive {
    return regions.isNotEmpty ||
        languages.isNotEmpty ||
        categories.isNotEmpty ||
        mediaTypes.isNotEmpty ||
        dumpQualities.isNotEmpty ||
        romTypes.isNotEmpty ||
        modifications.isNotEmpty ||
        distributionTypes.isNotEmpty ||
        showFavoritesOnly ||
        showInLibraryOnly ||
        genres.isNotEmpty ||
        players.isNotEmpty ||
        minRating > 0;
  }
}
