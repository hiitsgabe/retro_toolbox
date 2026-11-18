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
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps [home] with the Vita card style, under DpadScope as the app does.
  Future<void> pump(WidgetTester t, Widget home, {List<Override> overrides = const []}) async {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await container.read(styleProvider.notifier).loaded;
    await container.read(styleProvider.notifier).setCards(CardStyle.vita);
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
  }

  Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pumpAndSettle();
  }

  final tapped = <int>[];
  setUp(tapped.clear);

  // Six tiles: two rows, 4 then 3 places. The first is a console with its logo.
  List<MenuTile> tiles() => [
        MenuTile(
          label: 'SNES',
          icon: Icons.videogame_asset,
          assetPath: 'assets/console_art/snes_logo.svg',
          brandLogo: true,
          accentColor: const Color(0xFF6A4FB6),
          onTap: () => tapped.add(0),
        ),
        MenuTile(label: 'Servers', icon: Icons.dns, onTap: () => tapped.add(1)),
        for (var i = 2; i < 5; i++) MenuTile(label: 'Tile $i', icon: Icons.star, accentColor: Colors.teal, onTap: () => tapped.add(i)),
        // A logo that is not there: its icon instead.
        MenuTile(
          label: 'Gone',
          icon: Icons.help_outline,
          assetPath: '/nowhere/gone_logo.svg',
          brandLogo: true,
          onTap: () => tapped.add(5),
        ),
      ];

  Widget menu() => Scaffold(body: MenuGrid(tiles: tiles()));

  /// The style's game list, as HomeScreen gets it from the registry.
  Widget games() => Scaffold(
        body: Consumer(builder: (context, ref, _) => cardStyleKit(ref.watch(styleProvider).cards)!.gameList(context)),
      );

  late _FakeCatalog catalog;
  List<Override> catalogOf(List<Game> list) => [
        gameStateProvider.overrideWith((ref, g) => GameState(
              game: g,
              status: g.gameId == list[1].gameId ? GameStatus.downloading : GameStatus.ready,
              currentProgress: 0.4,
            )),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        catalogProvider.overrideWith((ref) => catalog = _FakeCatalog(
              CatalogState(games: list, cachedFilteredGames: list, cachedHasMore: true, selectedGames: {list[2].gameId}),
            )),
      ];
  final thirty = [for (var i = 0; i < 30; i++) _game(i)];

  /// The bubble (the art) of the tile or card that shows [text] under it.
  Finder bubbleOver(String text) => find.descendant(
        of: find.ancestor(of: find.text(text), matching: find.byKey(const ValueKey('vita-cell'))),
        matching: find.byType(ClipOval),
      );

  group('menu list', () {
    testWidgets('MenuGrid and the game list are the Vita layouts', (t) async {
      await pump(t, menu());
      expect(find.byKey(const ValueKey('vita-menu')), findsOneWidget);
      expect(find.byType(GridView), findsNothing);

      // Inside another scroll view (the Sports menus): all rows, no scrolling of its own.
      await pump(t, Scaffold(body: ListView(children: [MenuGrid(tiles: tiles(), shrinkWrap: true)])));
      expect(find.descendant(of: find.byKey(const ValueKey('vita-menu')), matching: find.byType(Scrollable)), findsNothing);
      expect(find.text('Gone'), findsOneWidget);

      await pump(t, games(), overrides: catalogOf(thirty));
      expect(find.byKey(const ValueKey('vita-games')), findsOneWidget);
      expect(find.text('Game 00'), findsOneWidget);
    });

    testWidgets('arrows move focus bubble to bubble along the rows; enter runs the focused tile', (t) async {
      await pump(t, menu());
      await key(t, LogicalKeyboardKey.arrowRight);
      await key(t, LogicalKeyboardKey.enter);
      expect(tapped, [1]);

      // Back to the first, down into the offset row of 3, then along it.
      await key(t, LogicalKeyboardKey.arrowLeft);
      await key(t, LogicalKeyboardKey.arrowDown);
      await key(t, LogicalKeyboardKey.arrowRight);
      await key(t, LogicalKeyboardKey.enter);
      expect(tapped, [1, 5]);
    });

    testWidgets('a brand logo is drawn white with no label in the art; a plain tile shows its icon', (t) async {
      await pump(t, menu());
      final logo = t.widget<SvgPicture>(find.byType(SvgPicture));
      expect(logo.colorFilter, const ColorFilter.mode(Colors.white, BlendMode.srcIn));
      final art = bubbleOver('SNES');
      expect(find.descendant(of: art, matching: find.byType(SvgPicture)), findsOneWidget);
      expect(find.descendant(of: art, matching: find.byType(Text)), findsNothing);

      final icon = find.descendant(of: bubbleOver('Servers'), matching: find.byIcon(Icons.dns));
      expect(icon, findsOneWidget);
      expect(t.widget<Icon>(icon).color, Colors.white);

      // A brand logo that is missing falls back to the tile's icon.
      expect(find.descendant(of: bubbleOver('Gone'), matching: find.byIcon(Icons.help_outline)), findsOneWidget);
    });
  });

  group('game list', () {
    testWidgets('a downloading game shows the progress badge, a selected one the check', (t) async {
      await pump(t, games(), overrides: catalogOf(thirty));
      Finder badge(int game, String k) =>
          find.descendant(of: find.byKey(ValueKey(thirty[game].gameId)), matching: find.byKey(ValueKey(k)));
      expect(badge(1, 'badge-progress'), findsOneWidget);
      expect(badge(2, 'badge-selected'), findsOneWidget);
      expect(badge(0, 'badge-progress'), findsNothing);
      expect(badge(0, 'badge-selected'), findsNothing);
    });

    testWidgets('scrolling to the end of the games loads more', (t) async {
      await pump(t, games(), overrides: catalogOf(thirty));
      final list = find.byKey(const ValueKey('vita-games'));
      await t.drag(list, const Offset(0, -100));
      await t.pump();
      expect(catalog.loadMores, 0, reason: 'far from the end');
      await t.drag(list, const Offset(0, -4000));
      await t.pump();
      expect(catalog.loadMores, greaterThan(0));
    });
  });

  group('Vita look', () {
    testWidgets('rows of 4 then 3 round bubbles, the label under each, the focused one at 1.08', (t) async {
      await pump(t, menu());
      Finder bubblesIn(int row) => find.descendant(of: find.byKey(ValueKey('vita-row-$row')), matching: find.byType(ClipOval));
      expect(bubblesIn(0), findsNWidgets(4));
      expect(bubblesIn(1), findsNWidgets(2), reason: 'six tiles: 4, then 2 of the 3 places');
      // The 3-row sits half a place in: its first bubble is between the first two above.
      final a = t.getCenter(bubbleOver('SNES')).dx, b = t.getCenter(bubbleOver('Servers')).dx;
      expect(t.getCenter(bubbleOver('Tile 4')).dx, moreOrLessEquals((a + b) / 2, epsilon: 1));

      // The label is centred under its bubble.
      final bubble = t.getRect(bubbleOver('Servers')), label = t.getRect(find.text('Servers'));
      expect(label.top, greaterThanOrEqualTo(bubble.bottom));
      expect(label.center.dx, moreOrLessEquals(bubble.center.dx, epsilon: 1));

      double scaleOf(String text) => t
          .widget<AnimatedScale>(find.ancestor(of: bubbleOver(text), matching: find.byKey(const ValueKey('vita-focus-scale'))))
          .scale;
      expect(scaleOf('SNES'), 1, reason: 'focus without a key press is touch: no look');
      await key(t, LogicalKeyboardKey.arrowRight);
      expect(scaleOf('Servers'), 1.08);
      expect(scaleOf('SNES'), 1);

      // Full rows keep alternating: 4, 3, 4.
      await pump(t, games(), overrides: catalogOf(thirty));
      expect([for (var r = 0; r < 3; r++) bubblesIn(r).evaluate().length], [4, 3, 4]);
      expect(find.descendant(of: find.byKey(const ValueKey('vita-row-1')), matching: find.text('Game 04')), findsOneWidget);
    });

    testWidgets('the art fills the whole bubble; a brand logo nearly spans it', (t) async {
      // Game 00 has box art (the test cannot fetch it: its error image), the others the placeholder.
      final list = [
        Game(title: 'Game 00', url: 'https://x/g0.zip', size: 1, consoleId: 'snes', details: const GameDetails(boxart: 'https://x/g0.png')),
        ...thirty.skip(1),
      ];
      await pump(t, games(), overrides: catalogOf(list));
      for (final title in ['Game 00', 'Game 03']) {
        final bubble = bubbleOver(title);
        expect(t.getSize(find.descendant(of: bubble, matching: find.byType(GameBoxart))), t.getSize(bubble), reason: title);
      }

      await pump(t, menu());
      final d = t.getSize(bubbleOver('SNES')).width;
      final logo = t.getSize(find.byType(SvgPicture));
      expect(logo.width, logo.height, reason: 'the logos are drawn on a square canvas');
      expect(logo.width, greaterThanOrEqualTo(d * 0.78));
      expect(logo.width, lessThan(d));
    });

    testWidgets('the dots on the right follow the scroll', (t) async {
      await pump(t, menu());
      expect(find.byKey(const ValueKey('vita-dots')), findsNothing, reason: 'six tiles fit: nothing to page');

      await pump(t, games(), overrides: catalogOf(thirty));
      final dots = find.byKey(const ValueKey('vita-dots'));
      expect(dots, findsOneWidget);
      expect(t.getRect(dots).center.dx, greaterThan(t.getRect(find.byKey(const ValueKey('vita-games'))).center.dx));
      int active() => t.widget<Column>(dots).children.indexWhere((d) => d.key == const ValueKey('vita-dot-active'));
      expect(active(), 0);
      await t.drag(find.byKey(const ValueKey('vita-games')), const Offset(0, -4000));
      await t.pumpAndSettle();
      expect(active(), t.widget<Column>(dots).children.length - 1);
    });
  });
}
