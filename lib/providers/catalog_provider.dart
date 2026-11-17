import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/library_snapshot_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/services/filtering_service.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_platforms.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/utils/letter_jump.dart';

final gameSelectionProvider = Provider.family<bool, String>((ref, gameId) {
  final catalogState = ref.watch(catalogProvider);
  return catalogState.selectedGames.contains(gameId);
});

final catalogProvider = StateNotifierProvider<CatalogNotifier, CatalogState>((ref) {
  final catalogService = CatalogService();
  return CatalogNotifier(ref, catalogService);
});

class CatalogNotifier extends StateNotifier<CatalogState> {
  final CatalogService catalogService;
  final Ref _ref;

  Timer? _filterDebounce;
  bool _loadingMore = false;
  // Incremented per loadCatalog call; awaited results from an older
  // generation are discarded so switching consoles mid-load takes effect.
  int _loadGeneration = 0;
  // The console the games came from, for reapplyLaunchbox.
  Console? _console;
  // Incremented per reapplyLaunchbox call: only the latest one writes, and a
  // load whose matching overlapped one matches again.
  int _launchboxGen = 0;

  CatalogNotifier(this._ref, this.catalogService) : super(const CatalogState()) {
    _ref.listen<Favorites>(favoritesProvider, (previous, current) {
      if (state.filter.showFavoritesOnly && previous?.gameIds != current.gameIds) {
        updateFilteredGames();
      }
    });
    // Grouping is a setting, per console or general: the list follows it.
    _ref.listen<Map<String, dynamic>>(settingWatcherProvider(AppSettings.groupVersions), (previous, current) {
      if (!mapEquals(previous, current)) updateFilteredGames(immediate: true);
    });
  }

  Future<void> loadCatalog(Console console) async {
    final gen = ++_loadGeneration;

    state = state.copyWith(
      loading: true,
      loadingStatus: '',
      errorMessage: '',
      games: [],
      selectedGames: {},
      // Drop the previous console's list too, or a failed/empty load keeps
      // showing it under the new console's name.
      cachedFilteredGames: [],
      cachedTotalCount: 0,
      cachedHasMore: false,
    );

    try {
      final settings = _ref.read(settingsProvider);
      final games = await catalogService.loadCatalog(
        console.id,
        iaAccessKey: settings.iaAccessKey,
        iaSecretKey: settings.iaSecretKey,
        authToken: settings.consoleSettings[console.id]?.authToken,
        onProgress: (done, total) {
          if (mounted && gen == _loadGeneration && total > 1) {
            state = state.copyWith(loadingStatus: 'Reading page $done of $total');
          }
        },
        onStatus: (status) {
          if (mounted && gen == _loadGeneration) {
            state = state.copyWith(loadingStatus: status);
          }
        },
      );

      if (gen != _loadGeneration || !mounted) return;

      // A source that answers but lists nothing (blocked, login page, down) is
      // a failure from the user's point of view: say so instead of "0 games".
      if (games.isEmpty) {
        state = state.copyWith(
          loading: false,
          loadingStatus: '',
          errorMessage: 'No games found for ${console.name}. The catalog source may be unavailable, try again later.',
        );
        return;
      }

      if (launchboxPlatformFor(console) != null) {
        state = state.copyWith(loadingStatus: 'Matching LaunchBox metadata');
      }
      // A reapply meanwhile found no games to apply to (they are cleared until
      // this load ends) and its data may be newer, so match again.
      List<Game> enriched;
      int launchboxGen;
      do {
        launchboxGen = _launchboxGen;
        enriched = await _ref.read(launchboxServiceProvider).enrich(console, games, useCovers: await launchboxUseCovers());
        if (gen != _loadGeneration || !mounted) return;
      } while (launchboxGen != _launchboxGen);
      _console = console;

      Set<String> regions = <String>{};
      Set<String> languages = <String>{};
      Set<String> categories = <String>{};

      for (final game in enriched) {
        if (game.metadata != null) {
          if (game.metadata!.regions.isNotEmpty) {
            regions.addAll(game.metadata!.regions);
          }
          if (game.metadata!.languages.isNotEmpty) {
            languages.addAll(game.metadata!.languages);
          }
          if (game.metadata!.categories.isNotEmpty) {
            categories.addAll(game.metadata!.categories);
          }
        }
      }

      final settingsNotifier = _ref.read(settingsProvider.notifier);
      final downloadDir = settingsNotifier.getDownloadDir(console.id);
      _ref.listen(librarySnapshotProvider(downloadDir), (_, __) {
        if (state.filter.showInLibraryOnly) updateFilteredGames();
      });

      final loaded = state.copyWith(
        games: enriched,
        availableRegions: regions,
        availableLanguages: languages,
        availableCategories: categories,
        availableGenres: _genresOf(enriched),
      );
      state = loaded.copyWith(filter: _offeredOnly(loaded));
      _refocus(enriched);

      await updateFilteredGames(immediate: true);

      // The default filter (USA / normal / good-dump) hides whole catalogs like
      // homebrew or non-USA sets. If it emptied a catalog that actually has
      // games, drop the filter so the user sees something instead of "0 games".
      if (gen == _loadGeneration && mounted &&
          enriched.isNotEmpty && state.filteredGamesCount == 0) {
        state = state.copyWith(
          filter: CatalogFilter(
            regions: {},
            languages: {},
            dumpQualities: {},
            romTypes: {},
            modifications: {},
            distributionTypes: {},
            showLatestRevisionOnly: false,
            showFavoritesOnly: false,
            showInLibraryOnly: false,
            sort: state.filter.sort,
            genres: {},
            players: {},
            minRating: 0,
          ),
        );
        await updateFilteredGames(immediate: true);
      }

      if (gen != _loadGeneration || !mounted) return;
      state = state.copyWith(loading: false, loadingStatus: '');
    } catch (e) {
      debugPrint('Error loading catalog: $e');
      if (gen != _loadGeneration || !mounted) return;
      final authMessage = console.auth?['auth_message'] as String?;
      final needsAuth = authMessage != null && RegExp(r'HTTP (401|403|422)').hasMatch(e.toString());
      state = state.copyWith(
        loading: false,
        loadingStatus: '',
        errorMessage: needsAuth ? authMessage : 'Failed to load catalog: $e',
        games: [],
      );
    }
  }

  /// Applies LaunchBox data again to the loaded list, after an import or after
  /// metadata was turned off, without reloading the catalog.
  Future<void> reapplyLaunchbox() async {
    final launchboxGen = ++_launchboxGen;
    final console = _console;
    final source = state.games;
    if (console == null || source.isEmpty) return;
    // Cleared first, so a game the new data no longer matches (or all of them,
    // with metadata off) loses what it had, a LaunchBox cover and release date
    // included. The catalog's own fields stay.
    final cleared = [for (final g in source) _withoutLaunchbox(g)];
    final enriched = await _ref.read(launchboxServiceProvider).enrich(console, cleared, useCovers: await launchboxUseCovers());
    // A catalog load started meanwhile: its list wins.
    if (!mounted || launchboxGen != _launchboxGen || !identical(state.games, source)) return;
    final applied = state.copyWith(games: enriched, availableGenres: _genresOf(enriched));
    state = applied.copyWith(filter: _offeredOnly(applied));
    _refocus(enriched);
    await updateFilteredGames(immediate: true);
  }

  /// Points the focused game at its copy in [games]: the second screen shows
  /// that object, and would keep the old LaunchBox data until focus moves.
  void _refocus(List<Game> games) {
    final focused = _ref.read(focusedGameProvider);
    if (focused == null) return;
    final fresh = games.where((g) => g.gameId == focused.gameId).firstOrNull;
    if (fresh != null) _ref.read(focusedGameProvider.notifier).state = fresh;
  }

  static Game _withoutLaunchbox(Game game) {
    final d = game.details;
    if (d == null) return game;
    return game.copyWith(details: GameDetails(boxart: d.boxart, releaseDate: d.releaseDate, popularity: d.popularity));
  }

  static Set<String> _genresOf(List<Game> games) => {for (final g in games) ...?g.details?.genres};

  /// The filter without the LaunchBox choices the modal no longer shows for
  /// [s]'s games: kept, they would hide every game with no way to clear them.
  static CatalogFilter _offeredOnly(CatalogState s) {
    final f = s.filter;
    final rated = s.hasRatings;
    return f.copyWith(
      genres: f.genres.intersection(s.availableGenres),
      players: s.hasPlayerCounts ? null : const {},
      minRating: rated ? null : 0,
      sort: f.sort == CatalogSort.topRated && !rated ? CatalogSort.name : null,
    );
  }

  Future<Map<String, GameStatus>> getLibraryStatus() async {
    final consoleId = state.games.isNotEmpty ? state.games.first.consoleId : null;
    if (consoleId == null) return {};

    final settingsNotifier = _ref.read(settingsProvider.notifier);
    final downloadDir = settingsNotifier.getDownloadDir(consoleId);
    if (downloadDir.isEmpty) return {};

    final snap = _ref.read(librarySnapshotProvider(downloadDir).notifier);
    final statuses = await snap.getStatuses(state.games.map((g) => g.filename));
    final result = <String, GameStatus>{};
    for (final game in state.games) {
      result[game.gameId] = (statuses[game.filename] ?? LibraryPresence.none).toGameStatus();
    }
    return result;
  }

  Future<FilterResult> _runFilterAndPaginate({required int skip, required int limit}) async {
    final favs = state.filter.showFavoritesOnly ? _ref.read(favoritesProvider).gameIds : null;
    final lib = state.filter.showInLibraryOnly ? await getLibraryStatus() : null;

    return compute(
      FilteringService.filterAndPaginate,
      FilterInput(
        games: state.games,
        filterText: state.filterText,
        filter: state.filter,
        skip: skip,
        limit: limit,
        favoriteGameIds: favs,
        inLibraryStatus: lib,
        groupVersions: _ref.read(settingsProvider.notifier).groupVersions(state.games.firstOrNull?.consoleId),
      ),
    );
  }

  Future<void> loadMoreItems() async {
    if (_loadingMore || !state.hasMoreItems) return;

    _loadingMore = true;
    state = state.copyWith(loadingMore: true);

    try {
      final before = state.paginatedFilteredGames;
      final filteredAndPaginated = await _runFilterAndPaginate(skip: before.length, limit: kDefaultCatalogDisplaySize);
      // A letter jump or a new filter replaced the list meanwhile: this page
      // no longer follows it.
      if (!identical(state.paginatedFilteredGames, before)) return;
      state = state.copyWith(
        cachedFilteredGames: [...state.paginatedFilteredGames, ...filteredAndPaginated.games],
        cachedTotalCount: filteredAndPaginated.totalCount,
        cachedHasMore: filteredAndPaginated.hasMore,
      );
    } catch (e) {
      debugPrint('Error loading more items: $e');
    } finally {
      _loadingMore = false;
      state = state.copyWith(loadingMore: false);
    }
  }

  Future<void> updateFilteredGames({bool immediate = false}) async {
    if (state.games.isEmpty) return;

    callback() async {
      try {
        final source = state.games;
        final filteredAndPaginated = await _runFilterAndPaginate(skip: 0, limit: kDefaultCatalogDisplaySize);
        // The console changed while filtering ran: this result is stale.
        if (!identical(state.games, source)) return;
        state = state.copyWith(
          cachedFilteredGames: filteredAndPaginated.games,
          cachedTotalCount: filteredAndPaginated.totalCount,
          cachedHasMore: filteredAndPaginated.hasMore,
        );
      } catch (e) {
        debugPrint('Error filtering games: $e');
      }
    }

    if (immediate) {
      _filterDebounce?.cancel();
      await callback();
    } else {
      _filterDebounce?.cancel();
      _filterDebounce = Timer(const Duration(milliseconds: 200), callback);
    }
  }

  void updateFilterText(String filter) {
    state = state.copyWith(filterText: filter);
    updateFilteredGames();
  }

  void toggleGameSelection(String gameId) {
    final selectedGames = Set<String>.from(state.selectedGames);

    if (selectedGames.contains(gameId)) {
      selectedGames.remove(gameId);
    } else {
      selectedGames.add(gameId);
    }

    state = state.copyWith(selectedGames: selectedGames);
  }

  void selectGame(String gameId) {
    final selectedGames = Set<String>.from(state.selectedGames);
    selectedGames.add(gameId);
    state = state.copyWith(selectedGames: selectedGames);
  }

  void deselectGame(String gameId) {
    final selectedGames = Set<String>.from(state.selectedGames);
    selectedGames.remove(gameId);
    state = state.copyWith(selectedGames: selectedGames);
  }

  void updateFilter(CatalogFilter filter) {
    state = state.copyWith(filter: filter);
    updateFilteredGames();
  }

  void toggleRegionFilter(String region) async {
    final regions = Set<String>.from(state.filter.regions);
    if (regions.contains(region)) {
      regions.remove(region);
    } else {
      regions.add(region);
    }
    final newFilter = state.filter.copyWith(regions: regions);
    updateFilter(newFilter);
  }

  void toggleLanguageFilter(String language) async {
    final languages = Set<String>.from(state.filter.languages);
    if (languages.contains(language)) {
      languages.remove(language);
    } else {
      languages.add(language);
    }
    final newFilter = state.filter.copyWith(languages: languages);
    updateFilter(newFilter);
  }

  void toggleGenreFilter(String genre) async {
    final genres = Set<String>.from(state.filter.genres);
    if (genres.contains(genre)) {
      genres.remove(genre);
    } else {
      genres.add(genre);
    }
    final newFilter = state.filter.copyWith(genres: genres);
    updateFilter(newFilter);
  }

  void togglePlayersFilter(String players) async {
    final selected = Set<String>.from(state.filter.players);
    if (selected.contains(players)) {
      selected.remove(players);
    } else {
      selected.add(players);
    }
    final newFilter = state.filter.copyWith(players: selected);
    updateFilter(newFilter);
  }

  void setMinRating(double rating) {
    updateFilter(state.filter.copyWith(minRating: rating));
  }

  void toggleFlagFilter(String flagType, String flag) async {
    CatalogFilter newFilter;
    switch (flagType) {
      case 'dumpQualities':
        final flags = Set<String>.from(state.filter.dumpQualities);
        if (flags.contains(flag)) {
          flags.remove(flag);
        } else {
          flags.add(flag);
        }
        newFilter = state.filter.copyWith(dumpQualities: flags);
        break;
      case 'romTypes':
        final flags = Set<String>.from(state.filter.romTypes);
        if (flags.contains(flag)) {
          flags.remove(flag);
        } else {
          flags.add(flag);
        }
        newFilter = state.filter.copyWith(romTypes: flags);
        break;
      case 'modifications':
        final flags = Set<String>.from(state.filter.modifications);
        if (flags.contains(flag)) {
          flags.remove(flag);
        } else {
          flags.add(flag);
        }
        newFilter = state.filter.copyWith(modifications: flags);
        break;
      case 'distributionTypes':
        final flags = Set<String>.from(state.filter.distributionTypes);
        if (flags.contains(flag)) {
          flags.remove(flag);
        } else {
          flags.add(flag);
        }
        newFilter = state.filter.copyWith(distributionTypes: flags);
        break;
      default:
        return;
    }
    updateFilter(newFilter);
  }

  void toggleLatestRevisionOnly() async {
    final newFilter = state.filter.copyWith(
      showLatestRevisionOnly: !state.filter.showLatestRevisionOnly,
    );
    updateFilter(newFilter);
  }

  void toggleFavoritesOnly() async {
    final newFilter = state.filter.copyWith(
      showFavoritesOnly: !state.filter.showFavoritesOnly,
    );
    updateFilter(newFilter);
  }

  void toggleLibraryOnly() async {
    final newFilter = state.filter.copyWith(
      showInLibraryOnly: !state.filter.showInLibraryOnly,
    );
    updateFilter(newFilter);
  }

  void setSort(CatalogSort sort) {
    updateFilter(state.filter.copyWith(sort: sort));
  }

  void clearFilters() async {
    updateFilter(const CatalogFilter(
      regions: {},
      languages: {},
      dumpQualities: {},
      romTypes: {},
      modifications: {},
      distributionTypes: {},
      showFavoritesOnly: false,
      showInLibraryOnly: false,
      genres: {},
      players: {},
      minRating: 0,
    ));
  }

  void defaultFilters() async {
    updateFilter(const CatalogFilter());
  }

  Future<void> clearCatalogCache([String? consoleId]) async {
    await catalogService.clearCatalogCache(consoleId);
  }

  Future<void> refreshCatalog() async {
    if (state.games.isEmpty) return;

    final consoleId = state.games.first.consoleId;
    final consoles = await catalogService.getConsoles();
    final console = consoles[consoleId];
    if (console == null) return;

    state = state.copyWith(
      games: [],
      cachedFilteredGames: [],
      cachedTotalCount: 0,
      cachedHasMore: false,
      selectedGames: {},
      availableRegions: {},
      availableLanguages: {},
      availableCategories: {},
      availableGenres: {},
    );
    await loadCatalog(console);
  }

  /// L1/R1: the game to focus for a jump from [fromGame]'s first letter to the
  /// next ([forward]) or previous letter among the filtered games, in the order
  /// shown, with that letter. The shown list grows to a page past it so the
  /// views can scroll to it. Null at the ends, with no games, or when the
  /// catalog, filter or search changed while the list was being sorted.
  Future<({String gameId, String letter})?> letterJump(Game? fromGame, {required bool forward}) async {
    if (state.games.isEmpty) return null;
    final games = state.games, filter = state.filter, text = state.filterText;
    final all = await _runFilterAndPaginate(skip: 0, limit: 1 << 30);
    if (!identical(state.games, games) || !identical(state.filter, filter) || state.filterText != text) return null;
    final target = letterJumpTarget([for (final g in all.games) g.displayTitle], fromGame?.displayTitle, forward: forward);
    if (target == null) return null;
    // Straight from this sort, in this same synchronous step: a second fetch
    // would race loadMoreItems. The shown rows stay the same objects (their
    // per-game state is keyed by identity); only the missing tail is added.
    final have = state.paginatedFilteredGames;
    if (target.index >= have.length) {
      final end = min(all.games.length, target.index + kDefaultCatalogDisplaySize);
      state = state.copyWith(
        cachedFilteredGames: [...have, ...all.games.sublist(have.length, end)],
        cachedTotalCount: all.totalCount,
        cachedHasMore: end < all.games.length,
      );
    }
    return (gameId: all.games[target.index].gameId, letter: target.letter);
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    super.dispose();
  }
}
