import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_list.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_menu_card.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

Game _game(int i) => Game(title: 'Game ${i.toString().padLeft(2, '0')}', url: 'https://x/g$i.zip', size: 1, consoleId: 'snes');

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog(super.state);
  int loadMores = 0;

  @override
  bool get groupsVersions => false;

  @override
  Future<void> loadMoreItems() async => loadMores++;

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

const _cyan = Color(0xFF3FC7F0);

// The focus border pulses for ever: pump a fixed time, never pumpAndSettle.
const _frame = Duration(milliseconds: 300);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps [home] under the 3DS card style at [size].
  Future<void> pump(WidgetTester t, Widget home, {Size size = const Size(1280, 800), List<Override> overrides = const []}) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await container.read(styleProvider.notifier).loaded;
    await container.read(styleProvider.notifier).setCards(CardStyle.threeDs);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: home,
      ),
    ));
    await t.pump(_frame);
  }

  Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pump(_frame);
  }

  /// The name the top strip shows.
  String? stripName(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('3ds-strip-name'))).data;

  Finder menuCard(String label) => find.byWidgetPredicate((w) => w is StyledMenuCard && w.tile.label == label);

  group('menu list', () {
    final taps = <int>[];
    late List<MenuTile> tiles;
    setUp(() {
      taps.clear();
      tiles = [
        for (var i = 0; i < 6; i++)
          MenuTile(
            label: 'Tile $i',
            icon: i == 1 ? Icons.dns : Icons.download,
            accentColor: i.isEven ? Colors.red : null,
            assetPath: switch (i) { 0 => 'assets/console_art/snes_logo.svg', 2 => '/no/such/logo.svg', _ => null },
            brandLogo: i == 0 || i == 2,
            onTap: () => taps.add(i),
          ),
      ];
    });

    testWidgets('is the 3DS layout, scrolling sideways', (t) async {
      await pump(t, Scaffold(body: MenuGrid(tiles: tiles)));
      final root = find.byKey(const ValueKey('3ds-menu'));
      expect(root, findsOneWidget);
      final scrollable = find.descendant(of: root, matching: find.byType(Scrollable)).first;
      expect(axisDirectionToAxis(t.widget<Scrollable>(scrollable).axisDirection), Axis.horizontal);
      for (var i = 0; i < 6; i++) {
        expect(menuCard('Tile $i'), findsOneWidget);
      }
    });

    testWidgets('right moves a column, down a row; enter runs the focused tile and the strip names it', (t) async {
      await pump(t, Scaffold(body: MenuGrid(tiles: tiles)), size: const Size(900, 520));
      // Column-major: the rows are the tiles sharing the first one's x.
      final x0 = t.getTopLeft(menuCard('Tile 0')).dx;
      final rows = [for (var i = 0; i < 6; i++) t.getTopLeft(menuCard('Tile $i')).dx].where((x) => x == x0).length;
      expect(rows, inInclusiveRange(2, 4), reason: 'the test needs a second column with two tiles');
      expect(stripName(t), 'Tile 0', reason: 'the first tile has focus');

      await key(t, LogicalKeyboardKey.arrowRight);
      expect(stripName(t), 'Tile $rows');
      await key(t, LogicalKeyboardKey.enter);
      expect(taps, [rows]);

      await key(t, LogicalKeyboardKey.arrowDown);
      expect(stripName(t), 'Tile ${rows + 1}');
      await key(t, LogicalKeyboardKey.enter);
      expect(taps, [rows, rows + 1]);
    });

    testWidgets('touch has no hover: a tap selects a slot (the strip names it), a tap on the selected slot opens it', (t) async {
      await pump(t, Scaffold(body: MenuGrid(tiles: tiles)), size: const Size(900, 520));
      final focus = find.byKey(const ValueKey('3ds-focus'));
      expect(stripName(t), 'Tile 0');
      expect(focus, findsNothing, reason: 'touch focus is not drawn before a tap');

      await t.tap(menuCard('Tile 3'));
      await t.pump(_frame);
      expect(taps, isEmpty, reason: 'the first tap only selects');
      expect(stripName(t), 'Tile 3');
      expect(find.descendant(of: menuCard('Tile 3'), matching: focus), findsOneWidget, reason: 'the tapped slot shows it is the one');

      await t.tap(menuCard('Tile 3'));
      await t.pump(_frame);
      expect(taps, [3]);

      await t.tap(menuCard('Tile 1'));
      await t.pump(_frame);
      expect(taps, [3], reason: 'another slot is selected first again');
      expect(stripName(t), 'Tile 1');
      expect(find.descendant(of: menuCard('Tile 1'), matching: focus), findsOneWidget);
      expect(focus, findsOneWidget, reason: 'one slot is the selected one');
    });

    testWidgets('a brand logo is drawn white with no label in the art; a plain tile or a missing logo shows the icon', (t) async {
      await pump(t, Scaffold(body: MenuGrid(tiles: tiles)));
      final logo = find.descendant(of: menuCard('Tile 0'), matching: find.byType(SvgPicture));
      expect(logo, findsOneWidget);
      expect(t.widget<SvgPicture>(logo).colorFilter, const ColorFilter.mode(Colors.white, BlendMode.srcIn));
      expect(find.descendant(of: menuCard('Tile 0'), matching: find.byType(Text)), findsNothing);
      expect(find.descendant(of: menuCard('Tile 0'), matching: find.byType(Icon)), findsNothing);

      final icon = find.descendant(of: menuCard('Tile 1'), matching: find.byIcon(Icons.dns));
      expect(icon, findsOneWidget);
      expect(t.widget<Icon>(icon).color, Colors.white);

      expect(find.descendant(of: menuCard('Tile 2'), matching: find.byType(SvgPicture)), findsNothing);
      expect(find.descendant(of: menuCard('Tile 2'), matching: find.byIcon(Icons.download)), findsOneWidget);
    });
  });

  group('game list', () {
    final games = [for (var i = 0; i < 30; i++) _game(i)];
    late _FakeCatalog catalog;

    List<Override> overrides({Set<String> selected = const {}, bool hasMore = true}) {
      final c = catalog = _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: hasMore, selectedGames: selected));
      return [
        gameStateProvider.overrideWith((ref, g) => GameState(
              game: g,
              status: g.gameId == games[1].gameId ? GameStatus.downloading : GameStatus.ready,
              currentProgress: 0.4,
              availableActions: const {GameAction.download},
            )),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        downloadProvider.overrideWith((ref) => _FakeDownloads()),
        catalogProvider.overrideWith((ref) => c),
      ];
    }

    Widget gameList() => Scaffold(body: Builder(builder: (c) => cardStyleKit(CardStyle.threeDs)!.gameList(c)));

    testWidgets('a downloading game shows the progress badge and a selected one the check', (t) async {
      await pump(t, gameList(), overrides: overrides(selected: {games[2].gameId}));
      expect(find.byKey(const ValueKey('3ds-games')), findsOneWidget);
      expect(find.byType(StyledGameList), findsOneWidget);
      Finder badge(int i, String k) => find.descendant(of: find.byKey(ValueKey(games[i].gameId)), matching: find.byKey(ValueKey(k)));
      expect(badge(1, 'badge-progress'), findsOneWidget);
      expect(badge(1, 'badge-selected'), findsNothing);
      expect(badge(2, 'badge-selected'), findsOneWidget);
      expect(badge(0, 'badge-progress'), findsNothing);
      expect(badge(0, 'badge-selected'), findsNothing);
    });

    testWidgets('a tap on a game selects it for the strip, a tap on the selected one opens it', (t) async {
      await pump(t, gameList(), overrides: overrides());
      expect(stripName(t), isNot(games[4].title));
      await t.tap(find.byKey(ValueKey(games[4].gameId)));
      await t.pump(_frame);
      expect(stripName(t), games[4].title);
      expect(find.byType(GameDetailsPage), findsNothing, reason: 'the first tap only selects');

      await t.tap(find.byKey(ValueKey(games[4].gameId)));
      // The page's first frame is offstage (the hero pass): pump twice.
      await t.pump();
      await t.pump(_frame);
      expect(find.byType(GameDetailsPage), findsOneWidget);
    });

    testWidgets('scrolling to the end loads more', (t) async {
      await pump(t, gameList(), size: const Size(500, 420), overrides: overrides());
      final grid = find.descendant(of: find.byKey(const ValueKey('3ds-games')), matching: find.byType(Scrollable)).first;
      expect(catalog.loadMores, 0);
      await t.drag(grid, const Offset(-100, 0));
      await t.pump(_frame);
      expect(catalog.loadMores, 0, reason: 'far from the end');
      await t.drag(grid, const Offset(-4000, 0));
      await t.pump(_frame);
      expect(catalog.loadMores, greaterThan(0));
    });

    testWidgets('a page that ends on screen loads more without a scroll', (t) async {
      await pump(t, gameList(), overrides: overrides(hasMore: false));
      expect(catalog.loadMores, 0, reason: 'nothing left to load');
      await pump(t, gameList(), overrides: overrides());
      expect(
          t
              .widget<Scrollable>(find.descendant(of: find.byKey(const ValueKey('3ds-games')), matching: find.byType(Scrollable)).first)
              .controller!
              .position
              .maxScrollExtent,
          lessThan(500),
          reason: 'the 30 games end within reach');
      expect(catalog.loadMores, greaterThan(0));
    });
  });

  group('3DS', () {
    final games = [for (var i = 0; i < 30; i++) _game(i)];
    List<Override> overrides() => [
          gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: GameStatus.ready, availableActions: const {GameAction.download})),
          gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
          favoritesProvider.overrideWith((ref) => _FakeFavorites()),
          settingsProvider.overrideWith((ref) => _FakeSettings()),
          downloadProvider.overrideWith((ref) => _FakeDownloads()),
          catalogProvider.overrideWith((ref) => _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: true))),
        ];

    testWidgets('the games scroll sideways; the top strip follows focus and the focused slot pulses cyan', (t) async {
      await pump(t, Scaffold(body: Builder(builder: (c) => cardStyleKit(CardStyle.threeDs)!.gameList(c))), overrides: overrides());
      final root = find.byKey(const ValueKey('3ds-games'));
      final scrollable = find.descendant(of: root, matching: find.byType(Scrollable)).first;
      expect(axisDirectionToAxis(t.widget<Scrollable>(scrollable).axisDirection), Axis.horizontal);

      Finder card(int i) => find.byKey(ValueKey(games[i].gameId));
      final x0 = t.getTopLeft(card(0)).dx;
      final rows = [for (var i = 0; i < 10; i++) t.getTopLeft(card(i)).dx].where((x) => x == x0).length;
      expect(rows, greaterThan(1));
      expect(stripName(t), 'Game 00');
      expect(find.byKey(const ValueKey('3ds-focus')), findsNothing, reason: 'touch focus is not drawn');

      await key(t, LogicalKeyboardKey.arrowRight);
      expect(stripName(t), games[rows].title);
      final border = find.byKey(const ValueKey('3ds-focus'));
      expect(border, findsOneWidget);
      expect(find.descendant(of: card(rows), matching: border), findsOneWidget);
      final box = t.widget<DecoratedBox>(find.descendant(of: border, matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
      expect(box.border, Border.all(color: _cyan, width: 3));

      // It pulses between 0.55 and 1.
      double opacity() => t.widget<FadeTransition>(find.ancestor(of: border, matching: find.byType(FadeTransition)).first).opacity.value;
      final seen = <double>{};
      for (var i = 0; i < 8; i++) {
        seen.add(opacity());
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(seen.every((o) => o >= 0.55 && o <= 1), isTrue, reason: '$seen');
      expect(seen.reduce((a, b) => a > b ? a : b) - seen.reduce((a, b) => a < b ? a : b), greaterThan(0.3), reason: '$seen');
    });
  });

  group('art fills its square', () {
    // The slot's frame is the bezel; inside it, no smaller card: the art is the whole square.
    Size square(WidgetTester t, Finder of) => t.getSize(find.descendant(of: of, matching: find.byKey(const ValueKey('3ds-art'))));

    testWidgets('box art and the no-art placeholder fill the card and the top strip', (t) async {
      final games = [
        const Game(title: 'Cover', url: 'https://x/c.zip', size: 1, consoleId: 'snes', details: GameDetails(boxart: 'https://x/c.png')),
        _game(1),
      ];
      await pump(
        t,
        Scaffold(body: Builder(builder: (c) => cardStyleKit(CardStyle.threeDs)!.gameList(c))),
        overrides: [
          gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: GameStatus.ready)),
          gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
          favoritesProvider.overrideWith((ref) => _FakeFavorites()),
          settingsProvider.overrideWith((ref) => _FakeSettings()),
          downloadProvider.overrideWith((ref) => _FakeDownloads()),
          catalogProvider.overrideWith((ref) => _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games))),
        ],
      );
      final cover = find.byKey(ValueKey(games[0].gameId));
      final plain = find.byKey(ValueKey(games[1].gameId));
      final strip = find.byKey(const ValueKey('3ds-strip'));
      expect(stripName(t), 'Cover', reason: 'the strip shows the box art too');
      for (final (name, of) in [('card', cover), ('strip', strip)]) {
        final art = find.descendant(of: of, matching: find.byType(CachedNetworkImage));
        expect(art, findsOneWidget, reason: name);
        expect(t.getSize(art), square(t, of), reason: '$name box art');
      }
      expect(t.getSize(find.descendant(of: plain, matching: find.byKey(const ValueKey('3ds-placeholder')))), square(t, plain));
    });

    testWidgets('a brand logo gets the whole square', (t) async {
      final logo =
          MenuTile(label: 'SNES', icon: Icons.videogame_asset, assetPath: 'assets/console_art/snes_logo.svg', brandLogo: true, accentColor: Colors.purple);
      await pump(t, Scaffold(body: MenuGrid(tiles: [logo, MenuTile(label: 'Other', icon: Icons.star)])));
      final card = menuCard('SNES');
      expect(t.getSize(find.descendant(of: card, matching: find.byType(SvgPicture))), square(t, card));
      final strip = find.byKey(const ValueKey('3ds-strip'));
      expect(t.getSize(find.descendant(of: strip, matching: find.byType(SvgPicture))), square(t, strip));
    });
  });
}
