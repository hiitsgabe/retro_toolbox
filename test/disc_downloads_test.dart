import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/disc_sets.dart';
import 'package:retro_toolbox/services/game_groups.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_title.dart';
import 'package:retro_toolbox/widgets/header/header.dart';
import 'package:retro_toolbox/widgets/settings/version_grouping_setting.dart';

import 'game_groups_support.dart';

/// Real resolution (console, then general) over an in-memory [AppSettings].
class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings([super.state = const AppSettings()]);

  BaseSettings _scope(String? consoleId) => consoleId == null ? state.generalSettings : state.consoleSettings[consoleId] ?? const BaseSettings();

  @override
  T? getSetting<T>(String key, [String? consoleId]) =>
      (consoleId == null ? null : state.consoleSettings[consoleId]?.getSetting<T>(key)) ?? state.generalSettings.getSetting<T>(key);

  @override
  T? getGeneralSetting<T>(String key) => state.generalSettings.getSetting<T>(key);

  @override
  Future<void> setGeneralSetting<T>(String key, T value) => setSetting(key, value);

  @override
  bool groupVersions(String? consoleId) => getSetting<bool>(AppSettings.groupVersions, consoleId) ?? true;

  @override
  bool downloadAllDiscs(String? consoleId) => getSetting<bool>(AppSettings.downloadAllDiscs, consoleId) ?? true;

  @override
  Future<void> setSetting<T>(String key, T value, [String? consoleId]) async {
    final updated = _scope(consoleId).setSetting(key, value);
    state = consoleId == null ? state.copyWith(generalSettings: updated) : state.copyWith(consoleSettings: {...state.consoleSettings, consoleId: updated});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGames extends StateNotifier<Map<String, GameState>> implements GameStateManager {
  _FakeGames([super.state = const {}]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog(super.state, {this.groups = true});
  final bool groups;

  @override
  bool get groupsVersions => groups;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Game _g(String title, {int size = 100}) => Game(title: title, url: 'https://example.com/files/${Uri.encodeComponent(title)}.chd', size: size, consoleId: 'psx');

final _d1 = _g('Final Fantasy VII (USA) (Disc 1)');
final _d2 = _g('Final Fantasy VII (USA) (Disc 2)');
final _d3 = _g('Final Fantasy VII (USA) (Disc 3)');
final _other = _g('Crash Bandicoot (USA)');
final _grouped = groupDiscSets([_d1, _d2, _d3]).single;

AppSettings _settings({bool? group, bool? all}) => AppSettings(
      consoleSettings: {
        'psx': BaseSettings(groupVersions: group, downloadAllDiscs: all),
      },
    );

List<String> _titles(Iterable<Game> games) => [for (final g in games) g.title];

void main() {
  late List<List<Game>> started;
  setUp(() {
    started = [];
    debugStartGameDownloads = (ref, context, games, consoleId) async => started.add(games);
    debugStartDownloads = (ref, context, games, consoleId) async => started.add(games);
  });
  tearDown(() {
    debugStartGameDownloads = null;
    debugStartDownloads = null;
    debugRunGameAction = null;
    GameDetailsPage.debugImageBuilder = null;
  });

  /// Pumps a button whose press runs [onPress] with the scope's ref.
  Future<void> pumpRef(
    WidgetTester t,
    AppSettings settings,
    Future<void> Function(WidgetRef ref, BuildContext context) onPress, {
    Map<String, GameState> states = const {},
    CatalogState catalog = const CatalogState(),
    bool? groups,
  }) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => _FakeSettings(settings)),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames(states)),
        catalogProvider.overrideWith((ref) => _FakeCatalog(catalog, groups: groups ?? settings.consoleSettings['psx']?.groupVersions ?? true)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) => TextButton(onPressed: () => onPress(ref, context), child: const Text('go'))),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
  }

  group('Download on a grouped game', () {
    Future<void> download(WidgetTester t, AppSettings s, {Map<String, GameState> states = const {}}) => pumpRef(
          t,
          s,
          (ref, context) => runGameAction(ref, context, _grouped, GameState(game: _grouped, status: GameStatus.ready), GameAction.download),
          states: states,
        );

    testWidgets('gets every disc by default', (t) async {
      await download(t, _settings(group: true));
      expect(_titles(started.single), _titles([_d1, _d2, _d3]));
    });

    testWidgets('gets only disc 1 with "Download every disc" off', (t) async {
      await download(t, _settings(group: true, all: false));
      expect(_titles(started.single), [_d1.title]);
    });

    testWidgets('leaves discs already done or running alone', (t) async {
      await download(t, _settings(group: true), states: {
        _d2.gameId: GameState(game: _d2, status: GameStatus.extracted),
      });
      expect(_titles(started.single), _titles([_d1, _d3]));
    });

    testWidgets('a single disc in the ungrouped list is just that disc', (t) async {
      await pumpRef(t, _settings(), (ref, context) => runGameAction(ref, context, _d2, GameState(game: _d2, status: GameStatus.ready), GameAction.download));
      expect(_titles(started.single), [_d2.title]);
    });
  });

  group('Download Selected', () {
    final catalog = CatalogState(games: [_other, _d1, _d2, _d3], selectedGames: {_d1.gameId, _other.gameId});

    testWidgets('with grouping on, a selected set brings its other discs, counted in the dialog', (t) async {
      await pumpRef(t, _settings(group: true), (ref, context) => downloadSelected(ref, context, 'psx'), catalog: catalog);
      expect(find.text('Download 4 games?'), findsOneWidget);
      expect(find.text('${formatBytes(400)} in total.'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Download'));
      await t.pumpAndSettle();
      expect(_titles(started.single), _titles([_other, _d1, _d2, _d3]));
    });

    // The setting says group; the catalog says this console does not (a regex
    // console): the catalog decides.
    testWidgets('the catalog predicate decides, not the setting', (t) async {
      await pumpRef(t, _settings(group: true), (ref, context) => downloadSelected(ref, context, 'psx'), catalog: catalog, groups: false);
      expect(find.text('Download 2 games?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Download'));
      await t.pumpAndSettle();
      expect(_titles(started.single), _titles([_other, _d1]));
    });

    testWidgets('with grouping off, only what was selected', (t) async {
      await pumpRef(t, _settings(group: false), (ref, context) => downloadSelected(ref, context, 'psx'), catalog: catalog);
      expect(find.text('Download 2 games?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Download'));
      await t.pumpAndSettle();
      expect(_titles(started.single), _titles([_other, _d1]));
    });

    testWidgets('with grouping on and "Download every disc" off, only what was selected', (t) async {
      await pumpRef(t, _settings(group: true, all: false), (ref, context) => downloadSelected(ref, context, 'psx'), catalog: catalog);
      await t.tap(find.widgetWithText(FilledButton, 'Download'));
      await t.pumpAndSettle();
      expect(_titles(started.single), _titles([_other, _d1]));
    });
  });

  group('box sets', () {
    final files = psxGamesStartingWith('Arc the Lad Collection - ');
    final box = groupEntry(buildGameGroups(files).single, (_) => true)!;
    const arc = [
      'Arc the Lad Collection - Arc Arena - Monster Tournament (USA).zip',
      'Arc the Lad Collection - Arc the Lad (USA).zip',
      'Arc the Lad Collection - Arc the Lad II (USA).zip',
      'Arc the Lad Collection - Arc the Lad III (USA) (Disc 1).zip',
      'Arc the Lad Collection - Arc the Lad III (USA) (Disc 2).zip',
      'Arc the Lad Collection - The Making of Arc the Lad (USA).zip',
    ];
    Game file(String title) => files.firstWhere((g) => g.title == title);

    testWidgets('Download gets every game in the box, in its main version with all its discs', (t) async {
      await pumpRef(t, _settings(), (ref, context) => runGameAction(ref, context, box, GameState(game: box, status: GameStatus.ready), GameAction.download));
      expect(_titles(started.single), arc);
    });

    testWidgets('games of the box the user already has are not downloaded again', (t) async {
      final states = {
        for (final title in [arc[1], arc[3]]) file(title).gameId: GameState(game: file(title), status: GameStatus.extracted),
      };
      await pumpRef(t, _settings(), (ref, context) => runGameAction(ref, context, box, GameState(game: box, status: GameStatus.ready), GameAction.download),
          states: states);
      // Arc the Lad is whole; Arc the Lad III has disc 1, so only disc 2 is left.
      expect(_titles(started.single), [arc[0], arc[2], arc[4], arc[5]]);
    });

    testWidgets('a game of the box the user has in another region follows that version', (t) async {
      final names = [
        'Foo Collection - Bar (USA)',
        'Foo Collection - Bar (Europe)',
        'Foo Collection - Baz (USA)',
        'Foo Collection - Baz (Europe)',
      ];
      final foo = [for (final n in names) psxGame(n)];
      final group = buildGameGroups(foo).single;
      final entry = groupEntry(group, (_) => true)!;
      final europeBar = foo[1];
      await pumpRef(
        t,
        _settings(),
        (ref, context) => runGameAction(ref, context, entry, GameState(game: entry, status: GameStatus.ready), GameAction.download),
        states: {europeBar.gameId: GameState(game: europeBar, status: GameStatus.downloaded)},
      );
      // Bar is whole in Europe: no second copy. Baz has none: its main version.
      expect(_titles(started.single), [foo[2].title]);
    });

    testWidgets('Download Selected on a box counts all of it', (t) async {
      final catalog = CatalogState(games: files, selectedGames: {box.gameId}, cachedFilteredGames: [box]);
      await pumpRef(t, _settings(), (ref, context) => downloadSelected(ref, context, 'psx'), catalog: catalog);
      expect(find.text('Download 6 games?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Download'));
      await t.pumpAndSettle();
      expect(_titles(started.single), arc);
    });

    testWidgets('Download Selected downloads the version the list shows now, not the one that was selected', (t) async {
      final ff = psxGamesStartingWith('Final Fantasy VII (');
      final group = buildGameGroups(ff).single;
      final before = groupEntry(group, (_) => true)!;
      final spain = ff.where((g) => g.title.contains('(Spain)') && g.title.contains('(Rev 1)')).toList();
      final after = groupEntry(group, (_) => true, owned: (g) => g.gameId == spain.first.gameId)!;
      expect(after.gameId, isNot(before.gameId)); // the premise: a re-pick changed the entry
      final catalog = CatalogState(games: ff, selectedGames: {before.gameId}, cachedFilteredGames: [after]);
      await pumpRef(t, _settings(), (ref, context) => downloadSelected(ref, context, 'psx'), catalog: catalog);
      await t.tap(find.widgetWithText(FilledButton, 'Download'));
      await t.pumpAndSettle();
      expect(_titles(started.single), _titles(spain));
    });
  });

  testWidgets('a grouped card says how many discs; a lone disc keeps its number', (t) async {
    final disc = Game(title: _d2.title, url: _d2.url, size: 1, consoleId: 'psx');
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          GameTitle(game: _grouped, gameState: GameState(game: _grouped)),
          GameTitle(game: disc, gameState: GameState(game: disc)),
        ]),
      ),
    ));
    expect(find.text('3 discs'), findsOneWidget);
    expect(find.textContaining('Disk'), findsNothing); // no metadata on the lone disc: no chip
  });

  group('details page', () {
    late List<(Game, GameAction)> ran;

    Future<void> pumpPage(WidgetTester t, Game game) async {
      ran = [];
      debugRunGameAction = (ref, context, game, state, action) async => ran.add((game, action));
      GameDetailsPage.debugImageBuilder =
          (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url));
      t.view.physicalSize = const Size(1240, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          gameStateProvider.overrideWith((ref, g) => GameState(
                game: g,
                status: g.gameId == _d2.gameId ? GameStatus.extracted : GameStatus.ready,
                availableActions: g.gameId == _d2.gameId ? const {} : const {GameAction.download},
              )),
          favoritesProvider.overrideWith((ref) => _FakeFavorites()),
          catalogProvider.overrideWith((ref) => _FakeCatalog(const CatalogState())),
        ],
        child: MaterialApp(home: Builder(builder: (context) => GameDetailsPage(game: game))),
      ));
      await t.pump();
    }

    Finder inDiscs(Finder f) => find.descendant(of: find.byType(GameDiscList), matching: f);

    testWidgets('a grouped game lists its discs; a disc download runs for that disc alone and the page stays', (t) async {
      await pumpPage(t, _grouped);
      for (final n in [1, 2, 3]) {
        expect(inDiscs(find.text('Disc $n')), findsOneWidget);
      }
      expect(inDiscs(find.text('Extracted')), findsOneWidget); // disc 2's own state
      expect(inDiscs(find.text('Download')), findsNWidgets(2)); // disc 2 has nothing to do
      await t.tap(inDiscs(find.text('Download')).last);
      await t.pumpAndSettle();
      expect(ran, [(_d3, GameAction.download)]);
      expect(find.byType(GameDetailsPage), findsOneWidget);
    });

    testWidgets('an ungrouped game has no disc list', (t) async {
      await pumpPage(t, _d1);
      expect(find.byType(GameDiscList), findsNothing);
      expect(find.text('Discs'), findsNothing);
    });
  });

  group('settings', () {
    Future<_FakeSettings> pumpSetting(WidgetTester t, AppSettings s, {Console? console}) async {
      final fake = _FakeSettings(s);
      await t.pumpWidget(ProviderScope(
        overrides: [settingsProvider.overrideWith((ref) => fake)],
        child: MaterialApp(home: Scaffold(body: VersionGroupingSetting(console: console))),
      ));
      return fake;
    }

    testWidgets('a console read by a regex has no grouping rows', (t) async {
      await pumpSetting(t, const AppSettings(), console: const Console(id: 'psx', name: 'PSX', urls: [], regex: 'x'));
      expect(find.text('Group versions'), findsNothing);
      expect(find.text('Download every disc'), findsNothing);
    });

    testWidgets('"Download every disc" shows only while grouping is on', (t) async {
      final fake = await pumpSetting(t, const AppSettings());
      expect(find.text('Group versions'), findsOneWidget);
      expect(find.text('Download every disc'), findsOneWidget); // on by default

      await t.tap(find.byType(Switch).first);
      await t.pump();
      expect(fake.state.generalSettings.groupVersions, isFalse);
      expect(find.text('Download every disc'), findsNothing);
    });
  });
}
