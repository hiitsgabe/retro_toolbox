import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  Future<Set<String>> ownedGameIds() async => const {};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  bool downloadAllDiscs(String? consoleId) => true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGames extends StateNotifier<Map<String, GameState>> implements GameStateManager {
  _FakeGames() : super(const {});
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

GameAddon _addon(AddonKind kind, String label) => GameAddon(
      kind: kind,
      label: label,
      size: 1000,
      url: 'https://api.example.com/games/download/0100BA4026E94000/${kind.name}-$label',
      fileName: 'Castlevania [$label].nsz',
    );

final _update = _addon(AddonKind.update, 'v65536');
final _dlcA = _addon(AddonKind.dlc, 'Bonus Pack');
final _dlcB = _addon(AddonKind.dlc, 'Extra Stage');
final _mod = _addon(AddonKind.mod, 'Rus Lang Mod');
final _game = Game(
  title: 'Castlevania.nsz',
  url: 'https://api.example.com/games/download/0100BA4026E94000/base',
  size: 560321310,
  consoleId: 'switch',
  updates: [_update],
  dlcs: [_dlcA, _dlcB],
  mods: [_mod],
);

void main() {
  late List<List<Game>> started;
  tearDown(() {
    debugStartGameDownloads = null;
    GameDetailsPage.debugImageBuilder = null;
  });

  /// [owned]: file names whose state is on disk, so they offer no download.
  Future<void> pumpPage(WidgetTester t, Game game, {Set<String> owned = const {}}) async {
    started = [];
    debugStartGameDownloads = (ref, context, games, consoleId) async => started.add(games);
    GameDetailsPage.debugImageBuilder =
        (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url));
    t.view.physicalSize = const Size(1240, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        gameStateProvider.overrideWith((ref, g) => owned.contains(g.title)
            ? GameState(game: g, status: GameStatus.extracted, availableActions: const {})
            : GameState(game: g, status: GameStatus.ready, availableActions: const {GameAction.download})),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
      ],
      child: MaterialApp(home: GameDetailsPage(game: game)),
    ));
    await t.pump();
  }

  double top(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

  List<String> titles(Iterable<Game> games) => [for (final g in games) g.title];

  testWidgets('Updates, DLC and Mods sections in that order, one row per addon', (t) async {
    await pumpPage(t, _game);
    final updates = top(t, find.text('Updates'));
    final dlc = top(t, find.text('DLC'));
    final mods = top(t, find.text('Mods'));
    expect(updates < dlc && dlc < mods, isTrue, reason: 'Updates $updates, DLC $dlc, Mods $mods');
    expect(find.byType(GameFileRow), findsNWidgets(4));
    for (final a in [_update, _dlcA, _dlcB, _mod]) {
      expect(find.widgetWithText(GameFileRow, a.label), findsOneWidget);
    }
    // The mod row stands for a mod, not an update.
    final modRow = t.widget<GameFileRow>(find.widgetWithText(GameFileRow, _mod.label));
    expect((modRow.game.addonKind, modRow.game.title), (AddonKind.mod, _mod.fileName));
  });

  testWidgets('a game without DLC or mods has neither section', (t) async {
    await pumpPage(t, _game.copyWith(dlcs: const [], mods: const []));
    expect(find.text('DLC'), findsNothing);
    expect(find.text('Mods'), findsNothing);
    expect(find.text('Download all'), findsNothing);
  });

  testWidgets('Download all only where a section has two or more, above its rows', (t) async {
    await pumpPage(t, _game);
    expect(find.text('Download all'), findsOneWidget);
    final all = top(t, find.text('Download all'));
    expect(top(t, find.text('DLC')) < all && all < top(t, find.text(_dlcA.label)), isTrue);
  });

  testWidgets('Download all queues every DLC in one batch and not the mod or the update', (t) async {
    await pumpPage(t, _game);
    await t.tap(find.text('Download all'));
    await t.pumpAndSettle();
    expect(started, hasLength(1));
    expect(titles(started.single), [_dlcA.fileName, _dlcB.fileName]);
    expect(started.single.every((g) => g.addonKind == AddonKind.dlc), isTrue);
    expect(find.byType(GameDetailsPage), findsOneWidget);
  });

  testWidgets('Download all skips an owned DLC', (t) async {
    await pumpPage(t, _game, owned: {_dlcA.fileName});
    await t.tap(find.text('Download all'));
    await t.pumpAndSettle();
    expect(titles(started.single), [_dlcB.fileName]);
  });

  testWidgets('Download all with everything owned queues nothing and says so', (t) async {
    await pumpPage(t, _game, owned: {_dlcA.fileName, _dlcB.fileName});
    await t.tap(find.text('Download all'));
    await t.pumpAndSettle();
    expect(started, isEmpty);
    expect(find.text('Already downloaded'), findsOneWidget);
  });

  testWidgets('Updates get Download all too when there are two', (t) async {
    final second = _addon(AddonKind.update, 'v131072');
    await pumpPage(t, _game.copyWith(updates: [_update, second], dlcs: const []));
    expect(find.text('Download all'), findsOneWidget);
    await t.tap(find.text('Download all'));
    await t.pumpAndSettle();
    expect(titles(started.single), [_update.fileName, second.fileName]);
  });

  testWidgets('Download all takes the d-pad focus and runs on select', (t) async {
    await pumpPage(t, _game);
    final button = find.ancestor(of: find.text('Download all'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    Focus.of(t.element(find.text('Download all'))).requestFocus();
    await t.pump();
    expect(Focus.of(t.element(find.text('Download all'))).hasPrimaryFocus, isTrue);
    expect(button, findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(titles(started.single), [_dlcA.fileName, _dlcB.fileName]);
  });

  testWidgets('a single row Download still queues just that file', (t) async {
    await pumpPage(t, _game);
    final row = find.widgetWithText(GameFileRow, _mod.label);
    await t.tap(find.descendant(of: row, matching: find.text('Download')));
    await t.pumpAndSettle();
    expect(titles(started.single), [_mod.fileName]);
  });
}
