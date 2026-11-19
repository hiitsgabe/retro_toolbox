import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_list.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_menu_card.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid.dart';
import 'package:retro_toolbox/widgets/game_list/letter_jump.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _snes = Console(id: 'snes', name: 'SNES', urls: []);
const _gba = Console(id: 'gba', name: 'GBA', urls: []);

Game _game(int i) => Game(title: 'Game ${i.toString().padLeft(2, '0')}', url: 'https://x/g$i.zip', size: 1, consoleId: 'snes');

class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog([super.state = const CatalogState()]);
  int loadMores = 0;
  final toggled = <String>[];

  @override
  bool get groupsVersions => false;

  @override
  Future<void> loadMoreItems() async => loadMores++;

  @override
  void toggleGameSelection(String gameId) {
    toggled.add(gameId);
    final sel = {...state.selectedGames};
    if (!sel.remove(gameId)) sel.add(gameId);
    state = state.copyWith(selectedGames: sel);
  }

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
  @override
  bool isResolving(String gameId) => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A kit that draws nothing of a real style, so the tests see the dispatch only.
class _FakeKit {
  final menuCalls = <(String, bool, bool)>[];

  late final kit = CardStyleKit(
    menuList: (context, tiles, {required shrinkWrap, required autofocusFirst}) {
      menuCalls.add((tiles.map((t) => t.label).join(', '), shrinkWrap, autofocusFirst));
      return Column(key: const ValueKey('fake-menu'), children: [for (final t in tiles) Text('fake ${t.label}')]);
    },
    gameList: (context) => const SizedBox(key: ValueKey('fake-games')),
  );
}

void main() {
  late _FakeKit fake;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = _FakeKit();
    // Classic keeps its own widgets; any other style is the fake.
    debugCardStyleKitOverride = (style) => style == CardStyle.classic ? null : fake.kit;
  });
  tearDown(() => debugCardStyleKitOverride = null);

  /// Pumps [home] under [overrides] with the card style [cards].
  Future<ProviderContainer> pump(WidgetTester t, Widget home, {CardStyle cards = CardStyle.classic, List<Override> overrides = const []}) async {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await container.read(styleProvider.notifier).loaded;
    await container.read(styleProvider.notifier).setCards(cards);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: home,
      ),
    ));
    await t.pump();
    return container;
  }

  final tiles = [
    MenuTile(label: 'One', icon: Icons.download, onTap: () {}),
    MenuTile(label: 'Two', icon: Icons.dns, onTap: () {}),
  ];

  group('MenuGrid', () {
    testWidgets('Classic builds its own grid', (t) async {
      await pump(t, Scaffold(body: MenuGrid(tiles: tiles)));
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-menu')), findsNothing);
    });

    testWidgets("another style builds its kit's menu list, with MenuGrid's options", (t) async {
      await pump(t, Scaffold(body: MenuGrid(tiles: tiles, shrinkWrap: true, autofocusFirst: false)), cards: CardStyle.vita);
      expect(find.byKey(const ValueKey('fake-menu')), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(fake.menuCalls.last, ('One, Two', true, false));
    });
  });

  group('ConsoleGridScreen', () {
    List<Override> consoles(ViewMode mode) => [
          appStateProvider.overrideWith((ref) => _FakeApp(AppState(consoles: const {'snes': _snes, 'gba': _gba}, consoleViewMode: mode))),
        ];

    testWidgets('Classic: the view mode picks the list and the toggle shows', (t) async {
      await pump(t, const ConsoleGridScreen(), overrides: consoles(ViewMode.list));
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.byTooltip('Change view'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-menu')), findsNothing);
    });

    for (final mode in ViewMode.values) {
      testWidgets('another style: the kit lists the consoles in ${mode.name} mode, and no toggle', (t) async {
        await pump(t, const ConsoleGridScreen(), cards: CardStyle.wii, overrides: consoles(mode));
        expect(find.byKey(const ValueKey('fake-menu')), findsOneWidget);
        expect(find.text('fake SNES'), findsOneWidget);
        expect(find.text('fake GBA'), findsOneWidget);
        expect(find.byTooltip('Change view'), findsNothing);
        expect(fake.menuCalls.last, ('SNES, GBA', false, true));
      });
    }
  });

  group('HomeScreen', () {
    List<Override> home() => [
          appStateProvider.overrideWith((ref) => _FakeApp(const AppState(consoles: {'snes': _snes}, selectedConsole: _snes))),
          catalogProvider.overrideWith((ref) => _FakeCatalog()),
          settingsProvider.overrideWith((ref) => _FakeSettings()),
          gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
          downloadProvider.overrideWith((ref) => _FakeDownloads()),
        ];

    testWidgets('Classic: the game grid and the header toggle', (t) async {
      await t.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await pump(t, const HomeScreen(), overrides: home());
      expect(find.byType(GameGrid), findsOneWidget);
      expect(find.byTooltip('Change view'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-games')), findsNothing);
    });

    testWidgets("another style: the kit's game list under the letter jump, and no toggle", (t) async {
      await t.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await pump(t, const HomeScreen(), cards: CardStyle.switchStyle, overrides: home());
      expect(find.descendant(of: find.byType(LetterJump), matching: find.byKey(const ValueKey('fake-games'))), findsOneWidget);
      expect(find.byType(GameGrid), findsNothing);
      expect(find.byTooltip('Change view'), findsNothing);
      expect(find.byTooltip('Filters'), findsOneWidget, reason: 'only the view toggle goes');
    });
  });

  group('GameStateBadges', () {
    final g = _game(1);
    // Selection is drawn round the card by the style (SelectedMark), not here.
    for (final (status, badges) in [
      (GameStatus.ready, <String>[]),
      (GameStatus.downloading, ['badge-progress']),
      (GameStatus.extracting, ['badge-progress']),
      (GameStatus.downloaded, ['badge-done']),
      (GameStatus.extracted, ['badge-done']),
      (GameStatus.downloadFailed, ['badge-failed']),
      (GameStatus.extractionFailed, ['badge-failed']),
    ]) {
      testWidgets('${status.name}: ${badges.isEmpty ? 'none' : badges.join(', ')}', (t) async {
        await t.pumpWidget(MaterialApp(
          home: Scaffold(body: GameStateBadges(state: GameState(game: g, status: status, currentProgress: 0.4))),
        ));
        for (final k in ['badge-selected', 'badge-progress', 'badge-done', 'badge-failed']) {
          expect(find.byKey(ValueKey(k)), badges.contains(k) ? findsOneWidget : findsNothing, reason: k);
        }
      });
    }

    testWidgets('a done check takes the classic border colour of its state', (t) async {
      Color? doneColor(WidgetTester t) => t.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('badge-done')), matching: find.byType(Icon))).color;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: GameStateBadges(state: GameState(game: g, status: GameStatus.downloaded)))));
      final scheme = Theme.of(t.element(find.byType(GameStateBadges))).colorScheme;
      expect(doneColor(t), scheme.secondaryContainer);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: GameStateBadges(state: GameState(game: g, status: GameStatus.extracted)))));
      expect(doneColor(t), scheme.inversePrimary);
    });
  });

  group('StyledMenuCard', () {
    testWidgets('an arrow moves the focused look; enter runs the focused tile', (t) async {
      final tapped = <String>[];
      Widget card(String label, {bool autofocus = false}) => SizedBox(
            width: 120,
            height: 120,
            child: StyledMenuCard(
              tile: MenuTile(label: label, icon: Icons.star, onTap: () => tapped.add(label)),
              autofocus: autofocus,
              face: (context, focused) => Text('$label ${focused ? 'focused' : 'plain'}'),
            ),
          );
      await pump(t, Scaffold(body: Row(children: [card('One', autofocus: true), card('Two')])));
      // Focus without a key press yet is touch: no look.
      expect(find.text('One plain'), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(find.text('Two focused'), findsOneWidget);
      expect(find.text('One plain'), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(tapped, ['Two']);
    });
  });

  group('StyledGameCard', () {
    late _FakeCatalog catalog;
    List<Override> cards(List<Game> games) => [
          gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: GameStatus.ready, availableActions: const {GameAction.download})),
          gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
          favoritesProvider.overrideWith((ref) => _FakeFavorites()),
          catalogProvider.overrideWith(
              (ref) => catalog = _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: true))),
        ];
    Widget card(Game g, {bool autofocus = false}) => StyledGameCard(
          game: g,
          autofocus: autofocus,
          face: (context, state, selected, focused) => SizedBox(
            width: 200,
            height: 200,
            child: Text('${g.title} ${state.status.name}${selected ? ' selected' : ''}${focused ? ' focused' : ''}'),
          ),
        );

    testWidgets('X marks the focused card and its face shows it; enter opens the game', (t) async {
      final g = _game(1);
      await pump(t, Scaffold(body: Column(children: [TextButton(autofocus: true, onPressed: () {}, child: const Text('Above')), card(g)])),
          overrides: cards([g]));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(find.text('Game 01 ready focused'), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      await t.pump();
      expect(catalog.toggled, [g.gameId]);
      expect(find.text('Game 01 ready selected focused'), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.byType(GameDetailsPage), findsOneWidget);
    });

    testWidgets('a letter jump to a card not built yet scrolls to it and focuses it', (t) async {
      final games = [for (var i = 0; i < 30; i++) _game(i)];
      final c = await pump(
        t,
        Scaffold(
          body: StyledGameList(
            card: (context, g, {required autofocus}) => card(g, autofocus: autofocus),
            layout: (context, count, card, onNearEnd, controller) =>
                ListView.builder(controller: controller, itemExtent: 200, itemCount: count, itemBuilder: card),
          ),
        ),
        overrides: cards(games),
      );
      expect(find.text('Game 25 ready'), findsNothing);
      c.read(gameJumpProvider.notifier).state = games[25].gameId;
      await t.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus!.context!;
      // The card itself, not a scope above several cards.
      final under = find.descendant(of: find.byElementPredicate((e) => e == focused), matching: find.textContaining('Game '));
      expect(under, findsOneWidget);
      expect(t.widget<Text>(under).data, startsWith('Game 25'));
    });
  });

  group('StyledGameList', () {
    testWidgets('scrolling a horizontal layout to its end loads more', (t) async {
      final games = [for (var i = 0; i < 30; i++) _game(i)];
      final catalog = _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: true));
      VoidCallback? nearEnd;
      await pump(
        t,
        Scaffold(
          body: StyledGameList(
            card: (context, g, {required autofocus}) => Text(g.title),
            layout: (context, count, card, onNearEnd, controller) {
              nearEnd = onNearEnd;
              return ListView.builder(scrollDirection: Axis.horizontal, controller: controller, itemExtent: 150, itemCount: count, itemBuilder: card);
            },
          ),
        ),
        overrides: [catalogProvider.overrideWith((ref) => catalog)],
      );
      expect(catalog.loadMores, 0);
      await t.drag(find.byType(ListView), const Offset(-200, 0));
      await t.pump();
      expect(catalog.loadMores, 0, reason: 'far from the end');
      await t.drag(find.byType(ListView), const Offset(-4000, 0));
      await t.pump();
      expect(catalog.loadMores, greaterThan(0));

      // Layouts that page by focus call it themselves; nothing left, no callback.
      final before = catalog.loadMores;
      nearEnd!();
      expect(catalog.loadMores, before + 1);
      catalog.state = CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: false);
      await t.pump();
      expect(nearEnd, isNull);
    });
  });
}
