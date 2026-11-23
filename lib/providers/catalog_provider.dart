import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_group_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/library_snapshot_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/services/filtering_service.dart';
import 'package:retro_toolbox/services/game_groups.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_platforms.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/services/launcher/games_on_disk.dart';
import 'package:retro_toolbox/services/launcher/owned_library.dart';
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

/// Games being downloaded or extracted, put here by the game state manager
/// (it listens to the catalog, so the catalog cannot read it). The next filter
/// run reads it: a download starting does not re-list, which would drop the
/// pages the user scrolled through.
final inFlightGameIdsProvider = StateProvider<Set<String>>((ref) => const {});

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

  // The groups of state.games, built once per list (in an isolate) and kept
  // until the list is replaced: grouping is the costly part of a filter run.
  List<Game>? _groupsSource;
  Future<List<GameGroup>>? _groups;

  /// How many times the groups were built (a test reads it).
  @visibleForTesting
  int debugGroupBuilds = 0;

  /// How many loose game scans started (a test reads it).
  @visibleForTesting
  int debugLooseScans = 0;

  // The loaded console's library listener. Each load replaces it: added to
  // instead, every load would add one more scan of the whole dir per change.
  ProviderSubscription<Map<String, LibrarySnapshot>>? _librarySub;
  // Launcher mode turning off, listened to from the first load that reads it.
  ProviderSubscription<bool>? _modeSub;

  Future<List<GameGroup>> _groupsOf(List<Game> games) {
    if (!identical(_groupsSource, games)) {
      _groupsSource = games;
      debugGroupBuilds++;
      final built = compute(buildGameGroups, games);
      // A failed build is not kept: the next run builds again (the caller of
      // this run gets the error).
      built.then((_) {}, onError: (Object _) {
        if (identical(_groupsSource, games)) _groupsSource = null;
      });
      _groups = built;
    }
    return _groups!;
  }

  // The owned games the shown list was filtered with. Pages and letter jumps
  // reuse it, so one list never mixes two answers (a game twice, or missing);
  // a new first page or a re-pick replaces it.
  Set<String> _listOwned = const {};

  /// Whether the list shows one entry per game: the setting is on and the
  /// console lists files (a console read by a regex lists each game once
  /// already). The one place that decides it.
  bool get groupsVersions =>
      _console?.regex == null && _ref.read(settingsProvider.notifier).groupVersions(state.games.firstOrNull?.consoleId);

  CatalogNotifier(this._ref, this.catalogService) : super(const CatalogState()) {
    _ref.listen<Favorites>(favoritesProvider, (previous, current) {
      if (state.filter.showFavoritesOnly && previous?.gameIds != current.gameIds) {
        updateFilteredGames();
      }
    });
    // Grouping is a setting, per console or general: the list follows it.
    // A download starting or ending changes which version a game shows.
    _ref.listen<Set<String>>(inFlightGameIdsProvider, (_, __) => _repickShown());
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
      List<Game> games;
      Object? failed;
      try {
        games = await catalogService.loadCatalog(
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
      } catch (e) {
        // Launcher mode shows the loose games instead, when there are any;
        // otherwise it is the load's failure, rethrown below.
        failed = e;
        games = const [];
      }

      if (gen != _loadGeneration || !mounted) return;
      final launcher = await _launcherMode();
      if (gen != _loadGeneration || !mounted) return;
      if (failed != null && !launcher) throw failed;

      // The loose games join before LaunchBox matching: one enrich matches
      // them by file name with the catalog's, and writes its cache once.
      if (launcher) {
        final owned = await _scanOwned(console, games);
        if (gen != _loadGeneration || !mounted) return;
        // A dir that cannot be listed would read as owning nothing.
        if (owned.unreadable) {
          state = state.copyWith(loading: false, loadingStatus: '', errorMessage: 'Cannot read ${_ref.read(settingsProvider.notifier).getDownloadDir(console.id)}');
          return;
        }
        _ref.read(ownedLibraryProvider(console.id).notifier).state = owned;
        if (failed != null && owned.games.isEmpty) throw failed;
        games = [...games, ...owned.games];
      }

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
      _librarySub?.close();
      _librarySub = _ref.listen(librarySnapshotProvider(downloadDir), (_, __) async {
        // The mode now, not the load's: it may have turned on or off since.
        if (_ref.read(launcherModeProvider)) await _relistLoose();
        // The scan outlives a notifier disposed meanwhile.
        if (!mounted) return;
        if (state.filter.showInLibraryOnly || state.filter.ownedOnly) {
          updateFilteredGames();
        } else {
          _repickShown();
        }
      });

      final loaded = state.copyWith(
        games: enriched,
        availableRegions: regions,
        availableLanguages: languages,
        availableCategories: categories,
        availableGenres: _genresOf(enriched),
      );
      // Launcher mode opens a console on what is on disk. Off, the owned view
      // is off too: only launcher mode shows its button.
      state = loaded.copyWith(filter: _offeredOnly(loaded).copyWith(ownedOnly: launcher));

      await updateFilteredGames(immediate: true);
      _refocus(enriched);

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
            showFavoritesOnly: false,
            showInLibraryOnly: false,
            // Nothing owned is the truthful answer of the owned view: kept.
            ownedOnly: state.filter.ownedOnly,
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

  /// [console]'s loose games, apart from [catalog]'s. In an isolate: the
  /// catalog's file names are the costly part. Consoles sharing the dir split
  /// it as [ownFormats] does.
  Future<OwnedLibrary> _scanOwned(Console console, List<Game> catalog) async {
    debugLooseScans++;
    final settings = _ref.read(settingsProvider.notifier);
    final dir = settings.getDownloadDir(console.id);
    if (dir.isEmpty) return OwnedLibrary.empty;
    final sharing = {...CatalogService.consolesSync(), console.id: console}.values.where((c) => p.equals(settings.getDownloadDir(c.id), dir));
    final snapshot = await _ref.read(librarySnapshotProvider(dir).notifier).current();
    return compute(OwnedLibrary.scan, (consoleId: console.id, dir: dir, formats: ownFormats(console, sharing), snapshot: snapshot, catalog: catalog));
  }

  /// Launcher mode, after the library changed: the loose games found now. A
  /// different set replaces the shown one and is matched again with the rest.
  Future<void> _relistLoose() async {
    final console = _console, games = state.games;
    if (console == null || games.isEmpty) return;
    final catalog = [for (final g in games) if (!g.isLocal) g];
    final owned = await _scanOwned(console, catalog);
    // The mode may have turned off during the scan: what it found is not shown.
    if (!mounted || !_ref.read(launcherModeProvider) || !identical(state.games, games) || owned.unreadable) return;
    _ref.read(ownedLibraryProvider(console.id).notifier).state = owned;
    if (setEquals({for (final g in games) if (g.isLocal) g.gameId}, {for (final g in owned.games) g.gameId})) return;
    state = state.copyWith(games: [...catalog, ...owned.games]);
    await reapplyLaunchbox();
  }

  /// Scans the loaded console's library dir again: the snapshot's listener
  /// then brings the list up to date. Nothing when no console is loaded.
  Future<void> rescanLibrary() async {
    final consoleId = _console?.id;
    if (consoleId == null) return;
    final dir = _ref.read(settingsProvider.notifier).getDownloadDir(consoleId);
    if (dir.isNotEmpty) await _ref.read(librarySnapshotProvider(dir).notifier).refresh();
  }

  /// Whether launcher mode is on, once its saved config is in.
  Future<bool> _launcherMode() async {
    if (!_ref.read(launcherAvailableProvider)) return false;
    await _ref.read(launchConfigProvider.notifier).loaded;
    if (!mounted) return false;
    _modeSub ??= _ref.listen<bool>(launcherModeProvider, (was, on) {
      if (was == true && !on) _leaveLauncherMode();
    });
    return _ref.read(launcherModeProvider);
  }

  /// Launcher mode turned off with a console loaded: its loose games go, and
  /// so does the owned view, whose button hides with the mode.
  void _leaveLauncherMode() {
    final games = state.games;
    final loose = games.any((g) => g.isLocal);
    if (!loose && !state.filter.ownedOnly) return;
    state = state.copyWith(
      games: loose ? [for (final g in games) if (!g.isLocal) g] : games,
      filter: state.filter.copyWith(ownedOnly: false),
    );
    updateFilteredGames(immediate: true);
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
    await updateFilteredGames(immediate: true);
    _refocus(enriched);
  }

  /// Points the focused game at its copy in the list just filtered (so it
  /// keeps its group), else in [games]: the second screen shows that object,
  /// and would keep the old LaunchBox data until focus moves.
  void _refocus(List<Game> games) {
    final focused = _ref.read(focusedGameProvider);
    if (focused == null) return;
    final fresh = state.paginatedFilteredGames.where((g) => g.gameId == focused.gameId).firstOrNull ??
        games.where((g) => g.gameId == focused.gameId).firstOrNull;
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

  Future<FilterResult> _runFilterAndPaginate({required int skip, required int limit, bool reuseOwned = false}) async {
    final favs = state.filter.showFavoritesOnly ? _ref.read(favoritesProvider).gameIds : null;
    // The owned view lists every file on disk, ungrouped (FilteringService):
    // no groups to build for it.
    final grouped = groupsVersions && !state.filter.ownedOnly;
    final games = state.games;
    // The library is read for the in-library filter and the owned view, and
    // to put a version the user has first among a game's.
    final lib = state.filter.showInLibraryOnly || state.filter.ownedOnly ? await getLibraryStatus() : null;
    final groups = grouped ? await _groupsOf(games) : null;
    final owned = grouped ? (skip > 0 || reuseOwned ? _listOwned : (_listOwned = await _ownedIds(games))) : null;

    return compute(
      FilteringService.filterAndPaginate,
      FilterInput(
        games: games,
        filterText: state.filterText,
        filter: state.filter,
        skip: skip,
        limit: limit,
        favoriteGameIds: favs,
        inLibraryStatus: lib,
        groupVersions: grouped,
        groups: groups,
        ownedGameIds: owned,
      ),
    );
  }

  /// The shown entries again after the owned games changed: a game whose
  /// owned version is not the one shown switches to it, in place (order and
  /// pages stay, only the entries whose game id changes are replaced).
  Future<void> _repickShown() async {
    try {
      await _repick();
    } catch (e) {
      // Not worth more than the old entries: the next filter run sets them.
      debugPrint('Error re-picking shown games: $e');
    }
  }

  Future<void> _repick() async {
    // With the in-library filter or the owned view on, the list is filtered
    // again instead.
    final games = state.games, shown = state.paginatedFilteredGames;
    if (shown.isEmpty || state.filter.showInLibraryOnly || state.filter.ownedOnly || !groupsVersions) return;
    final owned = await _ownedIds(games);
    if (!mounted || !identical(state.games, games) || !identical(state.paginatedFilteredGames, shown)) return;
    // Under a sort by something the version changes (size, rating), the next
    // pages keep the owned set the first page was ordered by: ordered by the
    // new one, a game would show twice and another not at all.
    if (state.filter.sort == CatalogSort.name) _listOwned = owned;
    final input = FilterInput(
      games: games,
      filterText: state.filterText,
      filter: state.filter,
      limit: 0,
      favoriteGameIds: state.filter.showFavoritesOnly ? _ref.read(favoritesProvider).gameIds : null,
      groupVersions: true,
      ownedGameIds: owned,
    );
    var changed = false;
    final next = <Game>[];
    for (final entry in shown) {
      final group = entry.group;
      final fresh = group == null ? null : FilteringService.entryFor(group, input);
      if (fresh != null && fresh.gameId != entry.gameId) {
        changed = true;
        next.add(fresh);
      } else {
        next.add(entry);
      }
    }
    if (changed) state = state.copyWith(cachedFilteredGames: next);
  }

  // state.games by file name without extension, for _ownedIds; per list, built
  // in an isolate (the file names are the costly part).
  List<Game>? _byBaseSource;
  Future<Map<String, List<(String, String)>>>? _byBase;

  /// The games the user has: on disk (downloaded or extracted) or in flight.
  /// Walks the library, not the catalog, so a filter run stays cheap.
  Future<Set<String>> ownedGameIds() => _ownedIds(state.games);

  Future<Set<String>> _ownedIds(List<Game> games) async {
    final owned = <String>{..._ref.read(inFlightGameIdsProvider)};
    final dir = games.isEmpty ? '' : _ref.read(settingsProvider.notifier).getDownloadDir(games.first.consoleId);
    if (dir.isEmpty) return owned;
    final snap = await _ref.read(librarySnapshotProvider(dir).notifier).current();
    if (!identical(_byBaseSource, games)) {
      _byBaseSource = games;
      _byBase = compute(_indexByBase, games);
    }
    final byBase = await _byBase!;
    for (final base in snap.presentBaseNames()) {
      for (final (gameId, filename) in byBase[base] ?? const <(String, String)>[]) {
        if (snap.statusFor(filename) != LibraryPresence.none) owned.add(gameId);
      }
    }
    return owned;
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

  void toggleFavoritesOnly() async {
    final newFilter = state.filter.copyWith(
      showFavoritesOnly: !state.filter.showFavoritesOnly,
    );
    updateFilter(newFilter);
  }

  /// Launcher mode's owned view on or off.
  void toggleOwnedOnly() => updateFilter(state.filter.copyWith(ownedOnly: !state.filter.ownedOnly));

  void toggleLibraryOnly() async {
    final newFilter = state.filter.copyWith(
      showInLibraryOnly: !state.filter.showInLibraryOnly,
    );
    updateFilter(newFilter);
  }

  void setSort(CatalogSort sort) {
    updateFilter(state.filter.copyWith(sort: sort));
  }

  /// Every filter off. The owned view is not one of them: it stays as it is.
  void clearFilters() async {
    updateFilter(CatalogFilter(
      regions: const {},
      languages: const {},
      dumpQualities: const {},
      romTypes: const {},
      modifications: const {},
      distributionTypes: const {},
      showFavoritesOnly: false,
      showInLibraryOnly: false,
      ownedOnly: state.filter.ownedOnly,
      genres: const {},
      players: const {},
      minRating: 0,
    ));
  }

  /// The default filters, the owned view as it is.
  void defaultFilters() async {
    updateFilter(CatalogFilter(ownedOnly: state.filter.ownedOnly));
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
    final all = await _runFilterAndPaginate(skip: 0, limit: 1 << 30, reuseOwned: true);
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

/// [games] as (gameId, filename) by file name without extension.
Map<String, List<(String, String)>> _indexByBase(List<Game> games) {
  final byBase = <String, List<(String, String)>>{};
  for (final g in games) {
    (byBase[p.basenameWithoutExtension(g.filename)] ??= []).add((g.gameId, g.filename));
  }
  return byBase;
}
