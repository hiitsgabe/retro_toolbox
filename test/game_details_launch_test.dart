import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/game_launcher.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_overrides.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_store.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';

class FakeLauncher implements GameLauncher {
  final launched = <LaunchChoice>[];
  Completer<LaunchResult>? pending;
  LaunchResult result = LaunchResult.ok;
  RomMode? mode;

  @override
  Future<LaunchResult> launch(OwnedGame game, LaunchChoice choice) {
    launched.add(choice);
    return pending?.future ?? Future.value(result);
  }

  @override
  RomMode? modeFor(OwnedGame game, LaunchChoice choice) => mode;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class CountingStore implements LaunchPresetStore {
  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class MemoryOverrides implements LaunchOverridesStore {
  MemoryOverrides([this.initial = const {}]);

  final Map<String, LaunchChoice> initial;
  final saved = <Map<String, LaunchChoice>>[];

  @override
  Future<Map<String, LaunchChoice>> load() async => initial;

  @override
  void save(Map<String, LaunchChoice> overrides) => saved.add(overrides);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _game = Game(title: 'Mario World', url: 'https://example.com/snes/Mario%20World.sfc', size: 1, consoleId: 'nintendo-snes');

DetectedEmulator emu(String id, String label) => DetectedEmulator(presetId: id, variant: 'org.example.$id', label: label, systems: const ['snes']);

void main() {
  late FakeLauncher launcher;
  late MemoryOverrides store;

  setUp(() {
    launcher = FakeLauncher();
    store = MemoryOverrides();
    GameDetailsPage.debugImageBuilder = (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => const SizedBox();
  });
  tearDown(() => GameDetailsPage.debugImageBuilder = null);

  Future<void> pump(
    WidgetTester t, {
    GameStatus status = GameStatus.downloaded,
    List<DetectedEmulator> detected = const [],
    bool available = true,
    Map<String, LaunchChoice> overrides = const {},
  }) async {
    store = MemoryOverrides(overrides);
    // A desktop window: the test font is wider than any real one, and with
    // Play, Open with and Open <emulator> the bar does not fit 800 px in it.
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      overrides: [
        launcherAvailableProvider.overrideWithValue(available),
        presetRefreshProvider.overrideWithValue(null),
        gameStateProvider.overrideWith((ref, game) => GameState(game: game, status: status)),
        launcherSessionProvider.overrideWith((ref) async => LauncherSession(presets: const [], detected: detected)),
        gameSystemProvider.overrideWith((ref, consoleId) => (slug: 'snes', name: 'Super Nintendo')),
        ownedGameProvider.overrideWith((ref, game) async => OwnedGame(game: game, dir: '/roms/snes', paths: const ['/roms/snes/Mario World.sfc'])),
        gameLauncherProvider.overrideWith((ref) async => launcher),
        launchOverridesProvider.overrideWith((ref) => LaunchOverridesNotifier(store)),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: const GameDetailsPage(game: _game),
      ),
    ));
    await t.pumpAndSettle();
  }

  /// The action bar's primary, labelled [label] (the bar writes Classic caps).
  Finder primary(String label) => find.descendant(of: find.byKey(const ValueKey('kit-primary')), matching: find.text(label));

  testWidgets('an owned game with one covering emulator: Play is the primary and Start launches it', (t) async {
    await pump(t, detected: [emu('ra', 'RetroArch')]);
    expect(primary('PLAY'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(launcher.launched, [const LaunchChoice(presetId: 'ra', variant: 'org.example.ra')]);
  });

  testWidgets('a game not on disk has no Play', (t) async {
    await pump(t, status: GameStatus.ready, detected: [emu('ra', 'RetroArch')]);
    expect(find.text('PLAY'), findsNothing);
    expect(find.text('OPEN WITH…'), findsNothing);
  });

  testWidgets('where launching is not supported there is no Play', (t) async {
    await pump(t, available: false, detected: [emu('ra', 'RetroArch')]);
    expect(find.text('PLAY'), findsNothing);
  });

  testWidgets('no covering emulator: Play is disabled and says so', (t) async {
    await pump(t);
    expect(primary('NO EMULATOR FOR SUPER NINTENDO'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNull);
  });

  testWidgets('the per-game override beats the single covering emulator', (t) async {
    const kept = LaunchChoice(presetId: 'ds', variant: 'org.example.ds');
    await pump(t, detected: [emu('ra', 'RetroArch'), emu('ds', 'DuckStation')], overrides: {_game.gameId: kept});
    await t.tap(find.text('PLAY'));
    await t.pumpAndSettle();
    expect(launcher.launched, [kept]);
  });

  testWidgets('Open with: Just this once launches and keeps nothing', (t) async {
    await pump(t, detected: [emu('ra', 'RetroArch'), emu('ds', 'DuckStation')]);
    await t.tap(find.text('OPEN WITH…'));
    await t.pumpAndSettle();
    expect(find.text('not tested'), findsNWidgets(2));
    await t.tap(find.descendant(of: find.byKey(const ValueKey('launch-picker-ds')), matching: find.text('Just this once')));
    await t.pumpAndSettle();
    expect(launcher.launched, [const LaunchChoice(presetId: 'ds', variant: 'org.example.ds')]);
    expect(store.saved, isEmpty);
  });

  testWidgets('Open with: Always for this game writes the override and launches', (t) async {
    await pump(t, detected: [emu('ra', 'RetroArch'), emu('ds', 'DuckStation')]);
    await t.tap(find.text('OPEN WITH…'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byKey(const ValueKey('launch-picker-ds')), matching: find.text('Always for this game')));
    await t.pumpAndSettle();
    expect(store.saved.single, {_game.gameId: const LaunchChoice(presetId: 'ds', variant: 'org.example.ds')});
    expect(launcher.launched, hasLength(1));
  });

  testWidgets('two covering emulators and no override: Play asks which', (t) async {
    await pump(t, detected: [emu('ra', 'RetroArch'), emu('ds', 'DuckStation')]);
    await t.tap(find.text('PLAY'));
    await t.pumpAndSettle();
    expect(find.text('Always for this game'), findsNWidgets(2));
    expect(launcher.launched, isEmpty);
  });

  testWidgets('while the launch runs Play reads Starting <emulator>', (t) async {
    launcher.pending = Completer();
    await pump(t, detected: [emu('ra', 'RetroArch')]);
    await t.tap(find.text('PLAY'));
    await t.pump();
    expect(primary('STARTING RETROARCH'), findsOneWidget);
    launcher.pending!.complete(LaunchResult.ok);
    await t.pumpAndSettle();
    expect(primary('PLAY'), findsOneWidget);
  });

  testWidgets('a failed launch shows its message and fix', (t) async {
    launcher.result = const LaunchResult(LaunchCode.notInstalled);
    await pump(t, detected: [emu('ra', 'RetroArch')]);
    await t.tap(find.text('PLAY'));
    await t.pumpAndSettle();
    expect(find.text('RetroArch is not installed anymore'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Detect again'), findsOneWidget);
  });

  testWidgets('a saf choice shows the folder-access hint and Open <emulator>', (t) async {
    launcher.mode = RomMode.saf;
    await pump(t, detected: [emu('ra', 'RetroArch')]);
    expect(find.textContaining('If RetroArch says it cannot open the file, give it access to'), findsOneWidget);
    expect(find.text('OPEN RETROARCH'), findsOneWidget);
  });

  testWidgets('the first details page of a session starts the preset refresh, and only that one', (t) async {
    final store = CountingStore();
    await t.pumpWidget(ProviderScope(
      overrides: [
        launcherAvailableProvider.overrideWithValue(true),
        launchPresetStoreProvider.overrideWithValue(store),
        gameStateProvider.overrideWith((ref, game) => GameState(game: game, status: GameStatus.ready)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => const GameDetailsPage(game: _game))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 2; i++) {
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
    }
    expect(store.refreshes, 1);
  });
}
