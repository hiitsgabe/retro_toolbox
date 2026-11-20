import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/card_styles/switch_style.dart';
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

const _cyan = Color(0xFF00C3E3);
const _blue = Color(0xFF2E7DFF);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps [home] at 1280x800 with the Switch card style, under DpadScope as
  /// the app does.
  Future<void> pump(WidgetTester t, Widget home, {List<Override> overrides = const []}) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await container.read(styleProvider.notifier).loaded;
    await container.read(styleProvider.notifier).setCards(CardStyle.switchStyle);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: home,
      ),
    ));
    // The focus frame animates forever: never pumpAndSettle.
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pump(const Duration(milliseconds: 300));
  }

  final tapped = <String>[];
  setUp(tapped.clear);
  List<MenuTile> tiles() => [
        for (final label in ['One', 'Two', 'Three', 'Four', 'Five', 'Six'])
          MenuTile(label: label, icon: Icons.star, accentColor: const Color(0xFF2E6DB4), onTap: () => tapped.add(label)),
      ];
  Widget menu(List<MenuTile> tiles) => Scaffold(body: MenuGrid(tiles: tiles));

  /// The art box of the menu tile [label].
  Finder art(String label) => find.byKey(ValueKey('switch-art-$label'));

  late _FakeCatalog catalog;
  List<Override> catalogOf(List<Game> games, {Set<String> selected = const {}, Map<String, GameStatus> status = const {}}) => [
        gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: status[g.gameId] ?? GameStatus.ready, currentProgress: 0.4)),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        catalogProvider.overrideWith((ref) => catalog =
            _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: true, selectedGames: selected))),
      ];
  final games = [for (var i = 0; i < 30; i++) _game(i)];
  Widget gameList() => Scaffold(body: Builder(builder: (c) => cardStyleKit(CardStyle.switchStyle)!.gameList(c)));

  /// The card of game [i] (StyledGameList keys each by its game id).
  Finder card(int i) => find.byKey(ValueKey(games[i].gameId));

  /// The game whose card holds focus.
  int focusedGame() {
    final ids = {for (final g in games) g.gameId};
    Object? id;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
      final k = e.widget.key;
      if (k is ValueKey<String> && ids.contains(k.value)) id = k.value;
      return id == null;
    });
    return games.indexWhere((g) => g.gameId == id);
  }

  group('layouts', () {
    testWidgets("the menu list is the Switch row", (t) async {
      await pump(t, menu(tiles()));
      expect(find.byKey(const ValueKey('switch-menu')), findsOneWidget);
      expect(find.byType(GridView), findsNothing, reason: 'not the classic grid');
    });

    testWidgets('inside another scroll view (Sports) the row has a fixed height', (t) async {
      await pump(t, Scaffold(body: ListView(children: [MenuGrid(tiles: tiles(), shrinkWrap: true, autofocusFirst: false), const Text('below')])));
      expect(t.takeException(), isNull);
      final row = t.getRect(find.byKey(const ValueKey('switch-menu')));
      expect(row.height, inInclusiveRange(150, 300));
      expect(t.getRect(find.text('below')).top, closeTo(row.bottom, 0.01));
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<MenuGrid>(), isNull, reason: 'no autofocus');
    });

    testWidgets('the game list is the Switch grid', (t) async {
      await pump(t, gameList(), overrides: catalogOf(games));
      expect(find.byKey(const ValueKey('switch-games')), findsOneWidget);
      expect(card(0), findsOneWidget);
    });
  });

  group('d-pad', () {
    testWidgets('the row moves sideways only, and enter runs the focused tile', (t) async {
      await pump(t, menu(tiles()));
      await key(t, LogicalKeyboardKey.arrowRight);
      await key(t, LogicalKeyboardKey.arrowRight);
      await key(t, LogicalKeyboardKey.arrowDown); // one row: nowhere to go
      await key(t, LogicalKeyboardKey.arrowLeft);
      await key(t, LogicalKeyboardKey.enter);
      expect(tapped, ['Two']);
    });

    testWidgets('the game grid moves right then down a row', (t) async {
      await pump(t, gameList(), overrides: catalogOf(games));
      expect(focusedGame(), 0);
      await key(t, LogicalKeyboardKey.arrowRight);
      expect(focusedGame(), 1);
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(focusedGame(), 7, reason: '6 columns at 1280 px');
    });
  });

  group('menu faces', () {
    testWidgets('a brand logo is drawn white with no label; a plain tile shows its icon', (t) async {
      await pump(
        t,
        menu([
          MenuTile(label: 'SNES', icon: Icons.videogame_asset, assetPath: 'assets/console_art/snes_logo.svg', brandLogo: true, accentColor: const Color(0xFF4F43AE)),
          const MenuTile(label: 'Tools', icon: Icons.build),
          const MenuTile(label: 'Lost', icon: Icons.memory, assetPath: '/nowhere/lost_logo.svg', brandLogo: true),
        ]),
      );
      final logo = find.descendant(of: art('SNES'), matching: find.byType(SvgPicture));
      expect(logo, findsOneWidget);
      expect(t.widget<SvgPicture>(logo).colorFilter, const ColorFilter.mode(Colors.white, BlendMode.srcIn));
      expect(find.descendant(of: art('SNES'), matching: find.text('SNES')), findsNothing);
      expect(t.getSize(logo).width, greaterThan(t.getSize(art('SNES')).width * 0.5), reason: 'the logo fills the art box');

      final icon = find.descendant(of: art('Tools'), matching: find.byIcon(Icons.build));
      expect(icon, findsOneWidget);
      expect(t.widget<Icon>(icon).color, Colors.white);

      // A missing logo falls back to the icon, and then the label shows.
      expect(find.descendant(of: art('Lost'), matching: find.byIcon(Icons.memory)), findsOneWidget);
      expect(find.descendant(of: art('Lost'), matching: find.byType(SvgPicture)), findsNothing);
      expect(find.descendant(of: art('Lost'), matching: find.text('Lost')), findsOneWidget);
    });
  });

  group('game faces', () {
    testWidgets('a downloading game shows the progress badge, a selected one the check', (t) async {
      await pump(t, gameList(),
          overrides: catalogOf(games, selected: {games[1].gameId}, status: {games[0].gameId: GameStatus.downloading}));
      Finder badge(int i, String k) => find.descendant(of: card(i), matching: find.byKey(ValueKey(k)));
      expect(badge(0, 'badge-progress'), findsOneWidget);
      expect(badge(0, 'badge-selected'), findsNothing);
      expect(badge(1, 'badge-selected'), findsOneWidget);
      expect(badge(1, 'badge-progress'), findsNothing);
      expect(badge(2, 'badge-selected'), findsNothing);
    });
  });

  group('art fills the card', () {
    testWidgets('a menu tile is its art, edge to edge; a logo takes nearly all of it', (t) async {
      await pump(
        t,
        menu([
          const MenuTile(label: 'SNES', icon: Icons.videogame_asset, assetPath: 'assets/console_art/snes_logo.svg', brandLogo: true, accentColor: Color(0xFF4F43AE)),
          const MenuTile(label: 'Tools', icon: Icons.build, accentColor: Color(0xFFE56717)),
        ]),
      );
      for (final l in ['SNES', 'Tools']) {
        expect(t.getRect(art(l)), t.getRect(find.byKey(ValueKey(l))), reason: '$l: the art is the card, not a card inside it');
      }
      final logo = t.getRect(find.descendant(of: art('SNES'), matching: find.byType(SvgPicture)));
      expect(logo.width, greaterThanOrEqualTo(t.getRect(art('SNES')).width * 0.85));
    });

    testWidgets('box art covers the whole square, and so does the placeholder', (t) async {
      final withArt = [
        Game(title: games[0].title, url: games[0].url, size: 1, consoleId: 'snes', details: const GameDetails(boxart: 'https://x/0.png')),
        ...games.skip(1),
      ];
      await pump(t, gameList(), overrides: catalogOf(withArt));
      final square = t.getRect(card(0));
      final cover = find.descendant(of: card(0), matching: find.byType(CachedNetworkImage));
      expect(t.widget<CachedNetworkImage>(cover).fit, BoxFit.cover);
      expect(t.getRect(cover), square);
      final placeholder = find.descendant(of: card(1), matching: find.byKey(const ValueKey('switch-placeholder')));
      expect(t.getRect(placeholder), t.getRect(card(1)));
    });
  });

  group('load more', () {
    testWidgets('scrolling the grid to its end loads more', (t) async {
      await pump(t, gameList(), overrides: catalogOf(games));
      expect(catalog.loadMores, 0);
      await t.drag(find.byKey(const ValueKey('switch-games')), const Offset(0, -6000));
      await t.pump(const Duration(milliseconds: 300));
      expect(catalog.loadMores, greaterThan(0));
    });
  });

  group('Switch', () {
    testWidgets('one horizontal row; the focused name sits above its tile and moves with focus', (t) async {
      await pump(t, menu(tiles()));
      final row = find.descendant(of: find.byKey(const ValueKey('switch-menu')), matching: find.byType(Scrollable)).first;
      expect(t.widget<Scrollable>(row).axisDirection, AxisDirection.right);
      final tops = {for (final l in ['One', 'Two', 'Three']) t.getRect(art(l)).top};
      expect(tops, hasLength(1), reason: 'one row');
      expect(t.getRect(art('One')).center.dy, closeTo(t.getRect(find.byKey(const ValueKey('switch-menu'))).center.dy, 1),
          reason: 'vertically centred');

      // Touch focus draws no name; the first key press does.
      expect(find.byKey(const ValueKey('switch-name')), findsNothing);
      Text name() => t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('switch-name')), matching: find.byType(Text), matchRoot: true));
      for (final (k, label) in [(LogicalKeyboardKey.arrowRight, 'Two'), (LogicalKeyboardKey.arrowRight, 'Three')]) {
        await key(t, k);
        expect(find.byKey(const ValueKey('switch-name')), findsOneWidget);
        expect(name().data, label);
        final at = t.getRect(find.byKey(const ValueKey('switch-name')));
        final tile = t.getRect(art(label));
        expect(at.bottom, lessThanOrEqualTo(tile.top), reason: 'above the tile');
        expect(at.center.dx, closeTo(tile.center.dx, 1), reason: 'centred on it');
      }
    });

    testWidgets('the row scrolls to keep the focused tile and its frame clear of the edges', (t) async {
      await pump(t, menu(tiles()));
      for (var i = 0; i < 4; i++) {
        await key(t, LogicalKeyboardKey.arrowRight);
      }
      final five = t.getRect(art('Five'));
      expect(five.right, lessThanOrEqualTo(1280 - 40), reason: 'scrolled in, with room for the frame');
      for (var i = 0; i < 4; i++) {
        await key(t, LogicalKeyboardKey.arrowLeft);
      }
      expect(t.getRect(art('One')).left, greaterThanOrEqualTo(40));
    });

    testWidgets('the focus frame animates from cyan to blue in 1 s', (t) async {
      await pump(t, menu(tiles()));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump(); // builds the frame
      await t.pump(); // its ticker's first tick
      Color frame() => ((t.widget<DecoratedBox>(find.byKey(const ValueKey('switch-frame'))).decoration as BoxDecoration).border as Border).top.color;
      expect(find.byKey(const ValueKey('switch-frame')), findsOneWidget);
      expect(frame(), _cyan);
      await t.pump(const Duration(milliseconds: 1000));
      expect(frame(), _blue);
      await t.pump(const Duration(milliseconds: 1000));
      expect(frame(), _cyan);
      expect((t.widget<DecoratedBox>(find.byKey(const ValueKey('switch-frame'))).decoration as BoxDecoration).border!.top.width, 4);
    });

    testWidgets('a tap opens a tile, and the frame and the name move to it', (t) async {
      await pump(t, menu(tiles()));
      final frame = find.byKey(const ValueKey('switch-frame'));
      expect(frame, findsNothing, reason: 'touch focus is not drawn before a tap');

      final opened = <String>[];
      for (final label in ['Three', 'Two']) {
        await t.tap(art(label));
        await t.pump(const Duration(milliseconds: 300));
        expect(tapped, opened..add(label), reason: 'one tap opens');
        expect(frame, findsOneWidget);
        expect(t.widget<SwitchMenuFace>(find.ancestor(of: frame, matching: find.byType(SwitchMenuFace))).tile.label, label);
        expect(find.byKey(const ValueKey('switch-name')), findsOneWidget);
        expect(t.widget<Text>(find.byKey(const ValueKey('switch-name'))).data, label);
      }
    });

    testWidgets('a tap opens a game, and the frame and the name move to it', (t) async {
      await pump(t, gameList(), overrides: catalogOf(games));
      final frame = find.byKey(const ValueKey('switch-frame'));
      expect(frame, findsNothing);
      await t.tap(card(3));
      // The page's first frame is offstage (the hero pass): pump twice.
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(GameDetailsPage), findsOneWidget, reason: 'one tap opens');
      Navigator.of(t.element(find.byType(GameDetailsPage))).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(GameDetailsPage), findsNothing);
      expect(frame, findsOneWidget);
      expect(t.widget<SwitchGameFace>(find.ancestor(of: frame, matching: find.byType(SwitchGameFace))).game, games[3]);
      expect(find.descendant(of: card(3), matching: find.byKey(const ValueKey('switch-name'))), findsOneWidget);
    });

    testWidgets('the game list is a vertical grid of squares', (t) async {
      await pump(t, gameList(), overrides: catalogOf(games));
      final grid = find.descendant(of: find.byKey(const ValueKey('switch-games')), matching: find.byType(Scrollable)).first;
      expect(t.widget<Scrollable>(grid).axisDirection, AxisDirection.down);
      final a = t.getRect(card(0)), b = t.getRect(card(1)), below = t.getRect(card(6));
      expect(a.width, closeTo(a.height, 0.01), reason: 'square');
      expect(b.top, a.top, reason: 'side by side');
      expect(below.left, a.left, reason: 'a grid: the 7th starts the next row');
      expect(below.top, greaterThan(a.bottom));
    });
  });
}
