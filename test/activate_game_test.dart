import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launch_overrides.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/services/launcher/owned_library.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  final selected = <String>[];
  @override
  void toggleGameSelection(String gameId) => selected.add(gameId);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Dual extends DualScreenNotifier {
  _Dual(super.ref, bool open) : super(enabled: false) {
    state = DualScreenState(companionOpen: open);
  }
}

class MemoryConfig implements LaunchConfigStore {
  MemoryConfig(this.initial);
  final LaunchConfig initial;
  @override
  Future<LaunchConfig> load() async => initial;
  @override
  Future<void> save(LaunchConfig config) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class MemoryOverrides implements LaunchOverridesStore {
  MemoryOverrides(this.initial);
  final Map<String, LaunchChoice> initial;
  @override
  Future<Map<String, LaunchChoice>> load() async => initial;
  @override
  void save(Map<String, LaunchChoice> overrides) {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _mario = Game(title: 'Mario World', url: 'https://example.com/snes/Mario%20World.sfc', size: 1, consoleId: 'nintendo-snes');
const _ra = LaunchChoice(presetId: 'ra', variant: 'org.example.ra');
const _snes9x = LaunchChoice(presetId: 'snes9x', variant: 'org.example.snes9x');

/// The card every style other than Classic builds its game faces on.
final _styled = StyledGameCard(game: _mario, face: (context, state, selected, focused) => const Text('Mario World'));

DetectedEmulator _emu(LaunchChoice c) => DetectedEmulator(presetId: c.presetId, variant: c.variant, label: c.presetId, systems: const ['snes']);

void main() {
  late List<(Game, LaunchChoice)> launched;
  late _FakeCatalog catalog;

  setUp(() {
    launched = [];
    catalog = _FakeCatalog();
    debugLaunchGame = (context, game, choice, onStarting) async => launched.add((game, choice));
    GameDetailsPage.debugImageBuilder = (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url));
  });
  tearDown(() {
    debugLaunchGame = null;
    GameDetailsPage.debugImageBuilder = null;
  });

  /// [card] under launcher mode [on], with [game] in [status], [detected]
  /// emulators, the console's [defaults] and the per-game [overrides].
  Future<ProviderContainer> pump(
    WidgetTester t,
    Widget card, {
    bool on = true,
    GameStatus status = GameStatus.downloaded,
    List<DetectedEmulator> detected = const [],
    Map<String, LaunchChoice> defaults = const {},
    Map<String, LaunchChoice> overrides = const {},
    bool companion = false,
  }) async {
    final nav = GlobalKey<NavigatorState>();
    final c = ProviderContainer(overrides: [
      launcherAvailableProvider.overrideWithValue(true),
      launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(LaunchConfig(enabled: on, defaults: defaults)))),
      launchOverridesProvider.overrideWith((ref) => LaunchOverridesNotifier(MemoryOverrides(overrides))),
      launcherSessionProvider.overrideWith((ref) async => LauncherSession(presets: const [], detected: detected)),
      gameSystemProvider.overrideWith((ref, consoleId) => (slug: 'snes', name: 'Super Nintendo')),
      ownedGameProvider.overrideWith((ref, game) async => OwnedGame(game: game, dir: '/roms', paths: const ['/roms/Mario World.sfc'])),
      presetRefreshProvider.overrideWithValue(null),
      gameStateProvider.overrideWith((ref, game) => GameState(game: game, status: status, isInteractable: status == GameStatus.ready, availableActions: const {})),
      favoritesProvider.overrideWith((ref) => _FakeFavorites()),
      catalogProvider.overrideWith((ref) => catalog),
      dualScreenProvider.overrideWith((ref) => _Dual(ref, companion)),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(
          body: Column(children: [
            TextButton(autofocus: true, onPressed: () {}, child: const Text('Above')),
            SizedBox(width: 800, height: 160, child: card),
          ]),
        ),
      ),
    ));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> tapCard(WidgetTester t, [String title = 'Mario World']) async {
    await t.tap(find.text(title).first);
    await t.pumpAndSettle();
  }

  final details = find.byType(GameDetailsPage);

  testWidgets('mode off: a tap on a game on disk opens its page, as before', (t) async {
    await pump(t, const GameGridItem(game: _mario), on: false, detected: [_emu(_ra)]);
    await tapCard(t);
    expect(details, findsOneWidget);
    expect(launched, isEmpty);
  });

  for (final (name, card) in <(String, Widget)>[('grid item', const GameGridItem(game: _mario)), ('row', const GameRow(game: _mario)), ('styled card', _styled)]) {
    testWidgets('mode on, $name: a game on disk launches with its console default, and the second screen shows it', (t) async {
      final c = await pump(t, card, detected: [_emu(_ra), _emu(_snes9x)], defaults: {'nintendo-snes': _snes9x});
      await tapCard(t);
      expect(launched, [(_mario, _snes9x)]);
      expect(details, findsNothing);
      expect(c.read(focusedGameProvider)?.gameId, _mario.gameId);
    });
  }

  testWidgets('mode on: A and Start with nothing selected launch too', (t) async {
    await pump(t, const GameGridItem(game: _mario), detected: [_emu(_ra)]);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(launched, [(_mario, _ra), (_mario, _ra)]);
  });

  testWidgets('mode on: while a card\'s launch is starting, a second tap, A or Start starts nothing, and after it a tap launches again', (t) async {
    final pending = Completer<void>();
    debugLaunchGame = (context, game, choice, onStarting) {
      launched.add((game, choice));
      return pending.future;
    };
    await pump(t, const GameGridItem(game: _mario), detected: [_emu(_ra)]);
    await tapCard(t);
    await t.pump(const Duration(milliseconds: 500));
    await tapCard(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(launched, hasLength(1));
    expect(details, findsNothing, reason: 'ignored, not sent to the page');
    pending.complete();
    await t.pumpAndSettle();
    debugLaunchGame = (context, game, choice, onStarting) async => launched.add((game, choice));
    await tapCard(t);
    expect(launched, hasLength(2));
  });

  testWidgets('mode on: a card\'s launch says which emulator is starting until it returned', (t) async {
    final pending = Completer<void>();
    debugLaunchGame = (context, game, choice, onStarting) {
      onStarting('RetroArch');
      return pending.future;
    };
    await pump(t, const GameGridItem(game: _mario), detected: [_emu(_ra)]);
    await tapCard(t);
    expect(find.text('Starting RetroArch'), findsOneWidget);
    pending.complete();
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing, reason: 'the launch ended well: nothing left to say');
  });

  testWidgets('mode on: a game with only a per-game override launches with it', (t) async {
    await pump(t, const GameGridItem(game: _mario), detected: [_emu(_ra), _emu(_snes9x)], overrides: {_mario.gameId: _snes9x});
    await tapCard(t);
    expect(launched, [(_mario, _snes9x)]);
  });

  testWidgets('mode on: a game with one covering emulator and no default launches with it', (t) async {
    await pump(t, const GameGridItem(game: _mario), detected: [_emu(_ra)]);
    await tapCard(t);
    expect(launched, [(_mario, _ra)]);
  });

  testWidgets('mode on: two covering emulators and no choice open the page, where Play asks', (t) async {
    await pump(t, const GameGridItem(game: _mario), detected: [_emu(_ra), _emu(_snes9x)]);
    await tapCard(t);
    expect(launched, isEmpty);
    expect(details, findsOneWidget);
  });

  testWidgets('mode on: a game not on disk opens its page', (t) async {
    await pump(t, const GameGridItem(game: _mario), status: GameStatus.ready, detected: [_emu(_ra)]);
    await tapCard(t);
    expect(launched, isEmpty);
    expect(details, findsOneWidget);
  });

  testWidgets('mode on: a loose game launches before its state is known', (t) async {
    final loose = Game(title: 'Chrono Trigger', url: localGameUrl('nintendo-snes', 'Chrono Trigger.sfc'), size: 1, consoleId: 'nintendo-snes');
    await pump(t, GameGridItem(game: loose), status: GameStatus.init, detected: [_emu(_ra)]);
    await tapCard(t, 'Chrono Trigger');
    expect(launched, [(loose, _ra)]);
  });

  testWidgets('mode on: a Task Manager row never launches, it opens the page', (t) async {
    await pump(t, const GameRow(game: _mario, selectable: false), detected: [_emu(_ra)]);
    await tapCard(t);
    expect(launched, isEmpty);
    expect(details, findsOneWidget);
  });

  testWidgets('mode on: Y opens the page', (t) async {
    await pump(t, const GameGridItem(game: _mario), detected: [_emu(_ra)]);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await t.pumpAndSettle();
    expect(launched, isEmpty);
    expect(details, findsOneWidget);
  });

  for (final (name, card) in <(String, Widget)>[('grid item', const GameGridItem(game: _mario)), ('row', const GameRow(game: _mario)), ('styled card', _styled)]) {
    testWidgets('mode on, $name: a long press opens the page', (t) async {
      await pump(t, card, detected: [_emu(_ra)]);
      await t.longPress(find.text('Mario World').first);
      await t.pumpAndSettle();
      expect(launched, isEmpty);
      expect(details, findsOneWidget);
    });
  }

  testWidgets('mode on, second screen open: a tap shows the game there, a tap on the shown game launches it', (t) async {
    final c = await pump(t, const GameGridItem(game: _mario), detected: [_emu(_ra)], companion: true);
    await tapCard(t);
    expect(c.read(focusedGameProvider)?.gameId, _mario.gameId);
    expect(launched, isEmpty);
    await tapCard(t);
    expect(launched, [(_mario, _ra)]);
    expect(catalog.selected, isEmpty);
  });

  testWidgets('mode on, second screen open: a tap on the shown game that would not launch selects it, as before', (t) async {
    final c = await pump(t, const GameGridItem(game: _mario), status: GameStatus.ready, detected: [_emu(_ra)], companion: true);
    c.read(focusedGameProvider.notifier).state = _mario;
    await tapCard(t);
    expect(launched, isEmpty);
    expect(catalog.selected, [_mario.gameId]);
  });
}
