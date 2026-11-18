import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/services/filtering_service.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/widgets/header/filter_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

Game _game(String title, [GameDetails? details]) =>
    Game(title: title, url: 'https://host.example/$title.bin', size: 1, consoleId: 'con', details: details);

// Everything the DAT-based defaults would hide is let through.
const _open = CatalogFilter(
  regions: {},
  dumpQualities: {},
  romTypes: {},
  modifications: {},
  distributionTypes: {},
);

List<String> _shown(List<Game> games, CatalogFilter filter) => [
      for (final g in FilteringService.filterAndPaginate(FilterInput(games: games, filterText: '', filter: filter, limit: 100)).games)
        g.title,
    ];

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog(super.state);
  final calls = <String>[];

  @override
  void setSort(CatalogSort sort) => calls.add('sort ${sort.name}');

  @override
  void toggleGenreFilter(String genre) => calls.add('genre $genre');

  @override
  void togglePlayersFilter(String players) => calls.add('players $players');

  @override
  void setMinRating(double rating) => calls.add('rating $rating');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _OneGameService extends CatalogService {
  @override
  Future<List<Game>> loadCatalog(String consoleId,
          {String? iaAccessKey, String? iaSecretKey, String? authToken, void Function(int done, int total)? onProgress, void Function(String status)? onStatus}) async =>
      [_game('one', const GameDetails(boxart: 'https://host.example/one.png', releaseDate: 19870000, popularity: 7))];
}

/// Gives every game what the fields hold when enrich is called, as reading
/// the disk would, or leaves the list alone when they hold nothing. With
/// [hold] set, each call waits on its own completer in [held].
class _FakeLaunchbox extends LaunchboxService {
  List<String> genres = const ['Shooter'];
  double? rating = 4.0;
  int? maxPlayers = 2;
  bool hold = false;
  final held = <Completer<void>>[];
  final coversAsked = <bool>[];

  @override
  Future<List<Game>> enrich(Console console, List<Game> games, {bool useCovers = false}) async {
    coversAsked.add(useCovers);
    final genres = this.genres, rating = this.rating, maxPlayers = this.maxPlayers;
    if (hold) {
      final c = Completer<void>();
      held.add(c);
      await c.future;
    }
    if (genres.isEmpty && rating == null && maxPlayers == null) return games;
    return [
      for (final g in games)
        g.copyWith(
          details: (g.details ?? const GameDetails())
              .copyWith(launchboxId: 1, rating: rating, ratingCount: rating == null ? null : 9, genres: genres, maxPlayers: maxPlayers, launchboxCover: useCovers ? 'https://lb.example/${g.title}.jpg' : null, launchboxReleaseDate: 19900000),
        ),
    ];
  }
}

const _nes = Console(id: 'nes', name: 'NES', urls: [], launchboxPlatform: 'Nintendo Entertainment System');

void main() {
  group('bayesianRating', () {
    test('many votes at 4.5 beat one vote at 5.0', () {
      expect(bayesianRating(4.5, 800, 3.5), greaterThan(bayesianRating(5.0, 1, 3.5)));
      expect(bayesianRating(5.0, 1, 3.5), closeTo((1 / 11) * 5.0 + (10 / 11) * 3.5, 1e-9));
      expect(bayesianRating(4.0, 0, 3.5), 3.5);
    });
  });

  group('top rated', () {
    test('orders by score, unrated last by name, zero votes counted as unrated', () {
      final games = [
        _game('Echo', const GameDetails(rating: 3.0, ratingCount: 100)),
        _game('Delta', const GameDetails(rating: 4.9, ratingCount: 0)),
        _game('Charlie'),
        _game('Bravo', const GameDetails(rating: 4.5, ratingCount: 800)),
        _game('Able', const GameDetails(boxart: 'https://host.example/able.png')),
        _game('Easy', const GameDetails(rating: 3.0, ratingCount: 100)),
        _game('Alpha', const GameDetails(rating: 5.0, ratingCount: 1)),
      ];
      expect(_shown(games, _open.copyWith(sort: CatalogSort.topRated)), ['Bravo', 'Alpha', 'Easy', 'Echo', 'Able', 'Charlie', 'Delta']);
    });

    test('the mean counts only ratings with votes', () {
      // C = (5.0 + 4.0 + 4.8) / 3 = 4.6: A 4.67, B 4.12, D 4.80. A mean of 3.5,
      // or one that took E's 1.0 in (3.7), puts B above A.
      final games = [
        _game('A', const GameDetails(rating: 5.0, ratingCount: 2)),
        _game('B', const GameDetails(rating: 4.0, ratingCount: 40)),
        _game('D', const GameDetails(rating: 4.8, ratingCount: 1000)),
        _game('E', const GameDetails(rating: 1.0, ratingCount: 0)),
      ];
      expect(_shown(games, _open.copyWith(sort: CatalogSort.topRated)), ['D', 'A', 'B', 'E']);
    });

    test('hiding games with a filter does not move the mean', () {
      Game rated(String title, double rating, int votes, String region) => Game(
            title: title,
            url: 'https://host.example/$title.bin',
            size: 1,
            consoleId: 'con',
            metadata: GameMetadata(displayTitle: title, regions: [region]),
            details: GameDetails(rating: rating, ratingCount: votes),
          );
      // C over the console is (3 + 4 + 5 + 5) / 4 = 4.25: Zed 4.14, Abe 4.00.
      // Over only the USA games it would be 3.5, and Abe would pass Zed.
      final games = [
        rated('Zed', 3.0, 1, 'USA'),
        rated('Abe', 4.0, 1000, 'USA'),
        rated('Hi One', 5.0, 1000, 'Japan'),
        rated('Hi Two', 5.0, 1000, 'Japan'),
      ];
      final top = _open.copyWith(sort: CatalogSort.topRated);
      expect(_shown(games, top), ['Hi One', 'Hi Two', 'Zed', 'Abe']);
      expect(_shown(games, top.copyWith(regions: {'USA'})), ['Zed', 'Abe']);
    });
  });

  group('LaunchBox filters', () {
    final games = [
      _game('a', const GameDetails(genres: ['Action', 'Shooter'], maxPlayers: 1, rating: 4.6, ratingCount: 50)),
      _game('b', const GameDetails(genres: ['Puzzle'], maxPlayers: 2, cooperative: true, rating: 3.2, ratingCount: 5)),
      _game('c', const GameDetails(genres: ['RPG'], maxPlayers: 4, cooperative: false, rating: 4.0, ratingCount: 3)),
      _game('d'),
      _game('e', const GameDetails(boxart: 'https://host.example/e.png')),
    ];

    test('all games show while the new filters are off', () {
      expect(_shown(games, _open), ['a', 'b', 'c', 'd', 'e']);
    });

    test('genre keeps games sharing one, drops games without LaunchBox data', () {
      expect(_shown(games, _open.copyWith(genres: {'Shooter', 'Puzzle'})), ['a', 'b']);
      expect(_shown(games, _open.copyWith(genres: {'RPG'})), ['c']);
    });

    test('players matches any selected value', () {
      expect(_shown(games, _open.copyWith(players: {'1'})), ['a']);
      expect(_shown(games, _open.copyWith(players: {'2+'})), ['b', 'c']);
      expect(_shown(games, _open.copyWith(players: {'coop'})), ['b']);
      expect(_shown(games, _open.copyWith(players: {'1', 'coop'})), ['a', 'b']);
    });

    test('minimum rating is inclusive and drops unrated games', () {
      expect(_shown(games, _open.copyWith(minRating: 4)), ['a', 'c']);
      expect(_shown(games, _open.copyWith(minRating: 4.6)), ['a']);
    });

    test('each new field alone makes the filter active', () {
      const off = CatalogFilter(
        regions: {},
        dumpQualities: {},
        romTypes: {},
        modifications: {},
        distributionTypes: {},
      );
      expect(off.isActive, isFalse);
      expect(off.copyWith(genres: {'RPG'}).isActive, isTrue);
      expect(off.copyWith(players: {'coop'}).isActive, isTrue);
      expect(off.copyWith(minRating: 3).isActive, isTrue);
    });
  });

  group('filter modal', () {
    Future<_FakeCatalog> pump(WidgetTester t, CatalogState state) async {
      final catalog = _FakeCatalog(state);
      await t.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [catalogProvider.overrideWith((_) => catalog)],
        child: const MaterialApp(home: Scaffold(body: FilterModal())),
      ));
      return catalog;
    }

    // The chip, not its text: a selected chip's label is not hit-testable.
    Future<void> tap(WidgetTester t, String label) async {
      final chip = find.ancestor(of: find.text(label), matching: find.byType(FilterChip));
      await t.ensureVisible(chip);
      await t.pump();
      await t.tap(chip);
    }

    const labels = ['Top rated', 'Genres', 'Players', 'Minimum rating'];

    testWidgets('hides the LaunchBox sort and sections without data', (t) async {
      await pump(t, CatalogState(games: [_game('a'), _game('b', const GameDetails(popularity: 3))]));
      for (final label in labels) {
        expect(find.text(label), findsNothing);
      }
    });

    testWidgets('shows them after Sort, genres in name order, and passes taps on', (t) async {
      final catalog = await pump(
        t,
        CatalogState(
          games: [
            _game('a', const GameDetails(genres: ['Shooter', 'Action'], rating: 4.2, ratingCount: 9)),
            _game('b', const GameDetails(maxPlayers: 2)),
          ],
          availableGenres: const {'Shooter', 'Action'},
          availableRegions: const {'USA'},
        ),
      );
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      final y = [for (final s in ['Sort by', 'Genres', 'Players', 'Minimum rating', 'Regions']) t.getTopLeft(find.text(s)).dy];
      expect(y, orderedEquals([...y]..sort()));
      expect(t.getTopLeft(find.text('Action')).dx, lessThan(t.getTopLeft(find.text('Shooter')).dx));

      await tap(t, 'Top rated');
      await tap(t, 'Shooter');
      await tap(t, '2+ players');
      await tap(t, 'Co-op');
      await tap(t, '4+');
      await tap(t, 'Any');
      expect(catalog.calls, ['sort topRated', 'genre Shooter', 'players 2+', 'players coop', 'rating 4.0', 'rating 0.0']);
    });

    testWidgets('players shows for a co-op flag alone and marks the chosen rating', (t) async {
      await pump(
        t,
        CatalogState(
          games: [_game('a', const GameDetails(cooperative: false, rating: 3.6, ratingCount: 2))],
          filter: const CatalogFilter(minRating: 3.5),
        ),
      );
      expect(find.text('Players'), findsOneWidget);
      final chip = t.widget<FilterChip>(find.ancestor(of: find.text('3.5+'), matching: find.byType(FilterChip)));
      expect(chip.selected, isTrue);
    });
  });

  group('catalog notifier', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('launchbox_filters');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );

    late _FakeLaunchbox launchbox;
    late CatalogNotifier notifier;
    late ProviderContainer container;
    CatalogState state() => container.read(catalogProvider);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      launchbox = _FakeLaunchbox();
      container = ProviderContainer(overrides: [
        catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _OneGameService())),
        launchboxServiceProvider.overrideWithValue(launchbox),
      ]);
      notifier = container.read(catalogProvider.notifier);
    });
    tearDown(() => container.dispose());

    test('loadCatalog enriches and lists genres, reapplyLaunchbox takes them away again', () async {
      final statuses = <String>[];
      container.listen(catalogProvider, (_, s) => statuses.add(s.loadingStatus));

      await notifier.loadCatalog(_nes);
      var s = state();
      expect(statuses, contains('Matching LaunchBox metadata'));
      expect(s.availableGenres, {'Shooter'});
      expect(s.paginatedFilteredGames.single.details?.genres, ['Shooter']);
      expect(s.paginatedFilteredGames.single.details?.launchboxReleaseDate, 19900000);

      launchbox
        ..genres = const []
        ..rating = null
        ..maxPlayers = null;
      await notifier.reapplyLaunchbox();
      s = state();
      expect(s.availableGenres, isEmpty);
      final d = s.paginatedFilteredGames.single.details!;
      expect((d.launchboxId, d.rating, d.ratingCount, d.maxPlayers), (null, null, null, null));
      expect(d.genres, isEmpty);
      // The catalog's own date stays; LaunchBox's goes with the rest.
      expect((d.boxart, d.popularity, d.releaseDate, d.launchboxReleaseDate), ('https://host.example/one.png', 7, 19870000, null));
    });

    test('covers follow the setting, and turning them off restores the mapped box art', () async {
      SharedPreferences.setMockInitialValues({'launchbox_use_covers': true});
      await notifier.loadCatalog(_nes);
      expect(state().paginatedFilteredGames.single.boxart, 'https://lb.example/one.jpg');

      await (await SharedPreferences.getInstance()).setBool('launchbox_use_covers', false);
      await notifier.reapplyLaunchbox();
      final d = state().paginatedFilteredGames.single.details!;
      expect((d.launchboxCover, d.boxart), (null, 'https://host.example/one.png'));
      expect(launchbox.coversAsked, [true, false]);
    });

    test('no matching status for a console LaunchBox has no platform for', () async {
      final statuses = <String>[];
      container.listen(catalogProvider, (_, s) => statuses.add(s.loadingStatus));
      await notifier.loadCatalog(const Console(id: 'con', name: 'Con', urls: []));
      expect(statuses, isNot(contains('Matching LaunchBox metadata')));
      expect(state().availableGenres, {'Shooter'});
    });

    test('a reapply while the load is matching is not lost', () async {
      launchbox
        ..genres = const ['Old']
        ..hold = true;
      final load = notifier.loadCatalog(_nes);
      await pumpEventQueue();
      expect(launchbox.held, hasLength(1));

      launchbox
        ..genres = const ['New']
        ..hold = false;
      await notifier.reapplyLaunchbox();
      launchbox.held.single.complete();
      await load;
      expect(state().availableGenres, {'New'});
      expect(state().paginatedFilteredGames.single.details?.genres, ['New']);
    });

    test('the focused game is swapped for its copy from a reapply or a reload', () async {
      Game? focused() => container.read(focusedGameProvider);
      await notifier.loadCatalog(_nes);
      container.read(focusedGameProvider.notifier).state = state().games.single;

      launchbox.genres = const ['New'];
      await notifier.reapplyLaunchbox();
      expect(focused(), same(state().games.single));
      expect(focused()?.details?.genres, ['New']);

      launchbox.genres = const ['Reloaded'];
      await notifier.loadCatalog(_nes);
      expect(focused(), same(state().games.single));
      expect(focused()?.details?.genres, ['Reloaded']);

      // One the list does not have is left alone.
      final other = _game('other');
      container.read(focusedGameProvider.notifier).state = other;
      await notifier.reapplyLaunchbox();
      expect(focused(), same(other));
    });

    test('of two overlapping reapplies the later one wins', () async {
      await notifier.loadCatalog(_nes);
      launchbox
        ..hold = true
        ..genres = const ['New'];
      final first = notifier.reapplyLaunchbox();
      await pumpEventQueue();
      launchbox.genres = const [];
      final second = notifier.reapplyLaunchbox();
      await pumpEventQueue();
      expect(launchbox.held, hasLength(2));

      launchbox.held[0].complete();
      await first;
      launchbox.held[1].complete();
      await second;
      expect(state().availableGenres, isEmpty);
    });

    group('choices the modal no longer offers are dropped', () {
      Future<CatalogFilter> after(void Function() change) async {
        launchbox.genres = const ['RPG', 'Gone'];
        await notifier.loadCatalog(_nes);
        notifier.updateFilter(state().filter.copyWith(
              genres: {'RPG', 'Gone'},
              players: {'2+'},
              minRating: 3.5,
              sort: CatalogSort.topRated,
            ));
        change();
        await notifier.reapplyLaunchbox();
        return state().filter;
      }

      void expectFilter(CatalogFilter f, Set<String> genres, Set<String> players, double minRating, CatalogSort sort) {
        expect(f.genres, genres);
        expect(f.players, players);
        expect((f.minRating, f.sort), (minRating, sort));
      }

      test('a genre no game has any more', () async {
        final f = await after(() => launchbox.genres = const ['RPG']);
        expectFilter(f, {'RPG'}, {'2+'}, 3.5, CatalogSort.topRated);
        expect(state().filteredGamesCount, 1);
      });

      test('players when no game has player data', () async {
        final f = await after(() => launchbox.maxPlayers = null);
        expectFilter(f, {'RPG', 'Gone'}, <String>{}, 3.5, CatalogSort.topRated);
      });

      test('the minimum rating and the top rated sort when no game has a rating', () async {
        final f = await after(() => launchbox.rating = null);
        expectFilter(f, {'RPG', 'Gone'}, {'2+'}, 0.0, CatalogSort.name);
      });

      test('everything once metadata is off, so the list is not left empty', () async {
        final f = await after(() => launchbox
          ..genres = const []
          ..rating = null
          ..maxPlayers = null);
        expectFilter(f, <String>{}, <String>{}, 0.0, CatalogSort.name);
        expect(state().filteredGamesCount, 1);
      });

      test('on load, for the console switched to', () async {
        notifier.updateFilter(state().filter.copyWith(genres: {'RPG'}, players: {'coop'}));
        launchbox
          ..genres = const ['Puzzle']
          ..maxPlayers = null;
        await notifier.loadCatalog(_nes);
        final f = state().filter;
        expect(f.genres, isEmpty);
        expect(f.players, isEmpty);
        // The DAT defaults survive: the list was not emptied, so the
        // reset-everything fallback did not run.
        expect(f.regions, {'USA'});
        expect(state().filteredGamesCount, 1);
      });
    });
  });
}
