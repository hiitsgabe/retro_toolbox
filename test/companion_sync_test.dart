import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';

class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp() : super(const AppState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDownloads extends StateNotifier<DownloadState> implements DownloadNotifier {
  _FakeDownloads() : super(const DownloadState());
  @override
  bool hasDownloadableSelectedGames() => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  String getDownloadDir(String? consoleId) => '/downloads';
  @override
  Future<void> get loaded => Future.value();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGames extends StateNotifier<Map<String, GameState>> implements GameStateManager {
  _FakeGames() : super(const {});
  void put(GameState s) => state = {...state, s.game.gameId: s};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Game game(String title) => Game(title: title, url: 'https://x/$title.zip', size: 1, consoleId: 'snes');

GameState downloading(String title, double p) => GameState(game: game(title), status: GameStatus.downloading, showProgressBar: true, currentProgress: p);

// testWidgets runs in a FakeAsync zone, so pump(d) moves the sync's timers by d.
void main() {
  late ProviderContainer container;
  late List<Map<String, dynamic>> sent;
  late CompanionSync sync;

  _FakeGames games() => container.read(gameStateManagerProvider.notifier) as _FakeGames;
  void focus(String? title) => container.read(focusedGameProvider.notifier).state = title == null ? null : game(title);
  void onGamesScreen(bool on) => container.read(gamesScreenActiveProvider.notifier).state = on;
  List<String?> titles() => [for (final p in sent) p['mode'] == 'details' ? p['game']['title'] : null];

  setUp(() {
    container = ProviderContainer(overrides: [gameStateManagerProvider.overrideWith((ref) => _FakeGames())]);
    sent = [];
    sync = CompanionSync(container, (json) async => sent.add(jsonDecode(json) as Map<String, dynamic>));
  });

  tearDown(() => container.dispose());

  // The binding fails a test that ends with a timer pending, before tearDown.
  void syncTest(String description, Future<void> Function(WidgetTester t) body) => testWidgets(description, (t) async {
        await body(t);
        sync.dispose();
      });

  syncTest('starts on the task list', (t) async {
    sync.start();
    expect(sent.single['mode'], 'tasks');
    expect(sent.single['tasks'], isEmpty);
  });

  syncTest('a focused game on the games screen sends its details after the debounce', (t) async {
    sync.start();
    sent.clear();
    onGamesScreen(true);
    focus('Zelda');
    await t.pump(const Duration(milliseconds: 149));
    expect(sent, isEmpty);
    await t.pump(const Duration(milliseconds: 1));
    expect(titles(), ['Zelda']);
  });

  syncTest('rapid focus changes send only the last game', (t) async {
    onGamesScreen(true);
    sync.start();
    sent.clear();
    for (final title in ['A', 'B', 'C', 'D']) {
      focus(title);
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pump(const Duration(milliseconds: 150));
    expect(titles(), ['D']);
  });

  syncTest('leaving the games screen sends the task list at once', (t) async {
    onGamesScreen(true);
    focus('Zelda');
    sync.start();
    await t.pump(const Duration(milliseconds: 150));
    expect(titles(), ['Zelda']);
    onGamesScreen(false);
    expect(sent.last['mode'], 'tasks');
    // A details send still pending when the screen goes away never lands.
    onGamesScreen(true);
    focus('Mario');
    onGamesScreen(false);
    await t.pump(const Duration(milliseconds: 300));
    expect(titles(), ['Zelda', null]);
  });

  syncTest('the task list comes back at once even inside a throttle window', (t) async {
    sync.start(); // the first task list opens a window
    onGamesScreen(true);
    focus('Zelda');
    await t.pump(const Duration(milliseconds: 150));
    onGamesScreen(false);
    expect(titles(), [null, 'Zelda', null]);
    await t.pump(const Duration(milliseconds: 350));
  });

  syncTest('task updates go out at most once per throttle window, the latest last', (t) async {
    sync.start();
    await t.pump(const Duration(milliseconds: 500)); // past the first send's window
    sent.clear();
    games().put(downloading('Zelda', 0.1));
    expect(sent, hasLength(1));
    games().put(downloading('Zelda', 0.2));
    games().put(downloading('Zelda', 0.3));
    await t.pump(const Duration(milliseconds: 499));
    expect(sent, hasLength(1));
    await t.pump(const Duration(milliseconds: 1));
    expect(sent, hasLength(2));
    expect(sent.last['tasks'].single['progress'], 0.3);
  });

  syncTest('task updates are ignored while details show', (t) async {
    onGamesScreen(true);
    focus('Zelda');
    sync.start();
    await t.pump(const Duration(milliseconds: 150));
    games().put(downloading('Zelda', 0.1));
    await t.pump(const Duration(seconds: 1));
    expect(titles(), ['Zelda']);
  });

  syncTest('an unchanged payload is not sent again', (t) async {
    onGamesScreen(true);
    sync.start();
    focus('Zelda');
    await t.pump(const Duration(milliseconds: 150));
    focus('Zelda'); // a new Game object, same content
    await t.pump(const Duration(milliseconds: 150));
    expect(titles(), [null, 'Zelda']);

    onGamesScreen(false);
    games().put(downloading('Zelda', 0.5));
    await t.pump(const Duration(milliseconds: 500));
    final before = sent.length;
    games().put(downloading('Zelda', 0.5));
    await t.pump(const Duration(seconds: 1));
    expect(sent, hasLength(before));
  });

  syncTest('dispose stops every send', (t) async {
    onGamesScreen(true);
    sync.start();
    sent.clear();
    focus('Zelda');
    sync.dispose();
    await t.pump(const Duration(seconds: 1));
    games().put(downloading('Zelda', 0.5));
    expect(sent, isEmpty);
  });

  group('the app reports', () {
    testWidgets('the game whose card takes focus, and a tapped one', (t) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final zelda = game('Zelda');
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [
              TextButton(autofocus: true, onPressed: () {}, child: const Text('Above')),
              GameCardActions(game: zelda, selectable: true, child: TextButton(onPressed: () {}, child: const Text('Zelda'))),
              Builder(builder: (c) => TextButton(onPressed: () => showGameActionMenu(c, game('Mario')), child: const Text('Mario'))),
            ]),
          ),
        ),
      ));
      await t.pump();
      expect(container.read(focusedGameProvider), isNull);
      Focus.of(t.element(find.text('Zelda'))).requestFocus();
      await t.pump();
      expect(container.read(focusedGameProvider), same(zelda));

      showGameActionMenu(t.element(find.text('Mario')), game('Mario'));
      expect(container.read(focusedGameProvider)?.title, 'Mario');
    });

    testWidgets('a game list on screen for as long as it is mounted', (t) async {
      final container = ProviderContainer(overrides: [
        appStateProvider.overrideWith((ref) => _FakeApp()),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
        downloadProvider.overrideWith((ref) => _FakeDownloads()),
      ]);
      addTearDown(container.dispose);
      Widget app(Widget home) => UncontrolledProviderScope(container: container, child: MaterialApp(home: home));

      await t.pumpWidget(app(const HomeScreen()));
      await t.pump();
      expect(container.read(gamesScreenActiveProvider), isTrue);
      container.read(focusedGameProvider.notifier).state = game('Zelda');

      await t.pumpWidget(app(const SizedBox()));
      await t.pump();
      expect(container.read(gamesScreenActiveProvider), isFalse);
      expect(container.read(focusedGameProvider), isNull);
    });
  });
}
