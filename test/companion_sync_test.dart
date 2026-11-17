import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/menu_grid/cover_flow.dart';

class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp() : super(const AppState());
  void pick(String id) => state = AppState(selectedConsole: Console(id: id, name: id, urls: const []));
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

class _Pushes extends NavigatorObserver {
  _Pushes(this.routes);
  final List<Route<dynamic>> routes;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.add(route);
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

/// Stands for the LaunchBox import the main side has read.
final _launchboxVersion = StateProvider<String?>((ref) => null);

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
    container = ProviderContainer(overrides: [
      gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
      launchboxVersionProvider.overrideWith((ref) => ref.watch(_launchboxVersion)),
    ]);
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

  syncTest('details carry the LaunchBox import, and a new one sends them again', (t) async {
    onGamesScreen(true);
    focus('Zelda');
    sync.start();
    await t.pump(const Duration(milliseconds: 150));
    container.read(_launchboxVersion.notifier).state = '"e2"';
    await t.pump(const Duration(milliseconds: 150));
    expect(titles(), ['Zelda', 'Zelda']);
    expect([for (final p in sent) p['launchbox']], [null, '"e2"']);
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

    testWidgets('no Task Manager row, focused or tapped', (t) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final task = game('Task');
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [
              TextButton(autofocus: true, onPressed: () {}, child: const Text('Above')),
              GameCardActions(game: task, selectable: false, child: TextButton(onPressed: () {}, child: const Text('Task'))),
            ]),
          ),
        ),
      ));
      await t.pump();
      container.read(focusedGameProvider.notifier).state = game('Zelda');
      Focus.of(t.element(find.text('Task'))).requestFocus();
      await t.pump();
      expect(container.read(focusedGameProvider)?.title, 'Zelda');

      showGameActionMenu(t.element(find.text('Task')), task, selectable: false);
      expect(container.read(focusedGameProvider)?.title, 'Zelda');
    });

    testWidgets('the centre game as cover flow browses under its one focus stop', (t) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final games = [game('A'), game('B'), game('C')];
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: CoverFlow(aspectRatio: 0.72, items: [
              for (final g in games) CoverFlowItem(face: Text(g.title), label: g.title, wrapFocus: (f) => GameCardActions(game: g, selectable: true, child: f)),
            ]),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(container.read(focusedGameProvider)?.title, 'A');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(container.read(focusedGameProvider)?.title, 'B');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(container.read(focusedGameProvider)?.title, 'C');
    });

    ProviderContainer homeContainer() {
      final container = ProviderContainer(overrides: [
        appStateProvider.overrideWith((ref) => _FakeApp()),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
        downloadProvider.overrideWith((ref) => _FakeDownloads()),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('a game list only while no other page covers it', (t) async {
      final container = homeContainer();
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(navigatorKey: nav, navigatorObservers: [HomeScreen.routeObserver], home: const HomeScreen()),
      ));
      await t.pump();
      bool active() => container.read(gamesScreenActiveProvider);
      expect(active(), isTrue);
      container.read(focusedGameProvider.notifier).state = game('Zelda');

      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Settings'))));
      await t.pumpAndSettle();
      expect(active(), isFalse);
      expect(container.read(focusedGameProvider)?.title, 'Zelda', reason: 'kept for the way back');
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(active(), isTrue);

      // Popups (the task manager, filters, dialogs) keep the details.
      showModalBottomSheet<void>(context: nav.currentContext!, builder: (_) => const Text('Tasks'));
      await t.pumpAndSettle();
      expect(active(), isTrue);
      nav.currentState!.pop();
      await t.pumpAndSettle();

      // The game's own page shows the same game.
      nav.currentState!
          .push(MaterialPageRoute<void>(settings: const RouteSettings(name: gameDetailsRouteName), builder: (_) => const Scaffold(body: Text('Details'))));
      await t.pumpAndSettle();
      expect(active(), isTrue);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(active(), isTrue);
    });

    testWidgets('a game page opened from a card is named for the observer', (t) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final routes = <Route<dynamic>>[];
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorObservers: [_Pushes(routes)],
          home: Builder(builder: (c) => TextButton(onPressed: () => showGameActionMenu(c, game('Mario')), child: const Text('Mario'))),
        ),
      ));
      showGameActionMenu(t.element(find.text('Mario')), game('Mario'));
      expect(routes.last.settings.name, gameDetailsRouteName);
    });

    testWidgets('no game from the last console', (t) async {
      final container = homeContainer();
      await t.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: HomeScreen())));
      await t.pump();
      (container.read(appStateProvider.notifier) as _FakeApp).pick('snes');
      await t.pump();
      container.read(focusedGameProvider.notifier).state = game('Zelda');
      (container.read(appStateProvider.notifier) as _FakeApp).pick('snes');
      await t.pump();
      expect(container.read(focusedGameProvider)?.title, 'Zelda', reason: 'same console');
      (container.read(appStateProvider.notifier) as _FakeApp).pick('gba');
      await t.pump();
      expect(container.read(focusedGameProvider), isNull);
    });

    testWidgets('a game list on screen for as long as it is mounted', (t) async {
      final container = homeContainer();
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
