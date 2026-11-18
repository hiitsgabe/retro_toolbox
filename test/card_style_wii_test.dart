import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
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

  late _FakeCatalog catalog;
  final games = [for (var i = 0; i < 30; i++) _game(i)];

  /// Pumps [home] at [size] with the Wii style and a catalog of [games]
  /// (those in [selected] marked, those in [status] in that state).
  Future<void> pump(
    WidgetTester t,
    Widget home, {
    Size size = const Size(1200, 800),
    Set<String> selected = const {},
    Map<String, GameStatus> status = const {},
  }) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
      gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: status[g.gameId] ?? GameStatus.ready, availableActions: const {GameAction.download})),
      gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
      favoritesProvider.overrideWith((ref) => _FakeFavorites()),
      catalogProvider.overrideWith(
          (ref) => catalog = _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: true, selectedGames: selected))),
    ]);
    addTearDown(container.dispose);
    await container.read(styleProvider.notifier).loaded;
    await container.read(styleProvider.notifier).setCards(CardStyle.wii);
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

  final tapped = <int>[];
  setUp(tapped.clear);
  List<MenuTile> tiles() => [
        for (var i = 0; i < 6; i++)
          MenuTile(
            label: 'Tile $i',
            icon: Icons.star,
            accentColor: i.isEven ? Colors.teal : null,
            assetPath: i == 0 ? 'assets/console_art/snes_logo.svg' : null,
            brandLogo: i == 0,
            onTap: () => tapped.add(i),
          ),
      ];
  Widget menu() => Scaffold(body: MenuGrid(tiles: tiles()));
  Widget gameList() => Scaffold(body: Builder(builder: (c) => cardStyleKit(CardStyle.wii)!.gameList(c)));

  group('menu list', () {
    testWidgets('is the Wii layout', (t) async {
      await pump(t, menu());
      expect(find.byKey(const ValueKey('wii-menu')), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(MenuTileFace), findsNothing, reason: 'not the classic face');
    });

    testWidgets('arrows move focus along the grid and enter runs the focused tile', (t) async {
      await pump(t, menu());
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(tapped, [1]);

      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(tapped, [1, 5], reason: 'four columns: down from the second is the sixth');
    });

    testWidgets('a brand logo is drawn white with no label, a plain tile shows its icon and label', (t) async {
      await pump(t, menu());
      await t.pumpAndSettle();
      final logo = t.widget<SvgPicture>(find.byType(SvgPicture));
      expect(logo.colorFilter, const ColorFilter.mode(Colors.white, BlendMode.srcIn));
      expect(find.text('Tile 0'), findsNothing);

      // The logo canvas is square with the ink on its middle band: it must be
      // taller than the 16:9 art box so the ink fills most of the channel width.
      final channel = t.getSize(find.byKey(const ValueKey('wii-channel')).first);
      final artHeight = channel.height - 2 * 9; // 3 px border + 6 px inset
      final size = t.getSize(find.byType(SvgPicture));
      expect(size.width, size.height, reason: 'square canvas');
      expect(size.height, greaterThan(artHeight));
      expect(size.width, lessThanOrEqualTo(channel.width));

      expect(find.text('Tile 1'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(5));
    });

    testWidgets('a channel is 16:9, in 4 columns at 1200 px and 2 at 500 px', (t) async {
      await pump(t, menu());
      final cards = find.byKey(const ValueKey('wii-channel'));
      expect(cards, findsNWidgets(6));
      final xs = {for (var i = 0; i < 6; i++) t.getTopLeft(cards.at(i)).dx};
      expect(xs.length, 4);
      final s = t.getSize(cards.first);
      expect(s.width / s.height, closeTo(16 / 9, 0.01));

      await pump(t, menu(), size: const Size(500, 800));
      final narrow = find.byKey(const ValueKey('wii-channel'));
      expect({for (var i = 0; i < 6; i++) t.getTopLeft(narrow.at(i)).dx}.length, 2);
      final n = t.getSize(narrow.first);
      expect(n.width / n.height, closeTo(16 / 9, 0.01));
    });

    testWidgets('the focused channel has the blue border', (t) async {
      await pump(t, menu());
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      Color? border(int i) {
        final box = t.widget<AnimatedContainer>(find.byKey(const ValueKey('wii-channel')).at(i)).decoration as BoxDecoration;
        return (box.border as Border).top.color;
      }

      expect(border(1), const Color(0xFF34BEED));
      expect(border(0), isNot(const Color(0xFF34BEED)));
    });
  });

  group('game list', () {
    testWidgets('is the Wii layout', (t) async {
      await pump(t, gameList());
      expect(find.byKey(const ValueKey('wii-games')), findsOneWidget);
      expect(find.text('Game 00'), findsOneWidget, reason: 'the title sits under the art');
    });

    testWidgets('a downloading game shows its progress and a selected one its check', (t) async {
      final id0 = games[0].gameId, id1 = games[1].gameId;
      await pump(t, gameList(), selected: {id1}, status: {id0: GameStatus.downloading});
      expect(find.byKey(const ValueKey('badge-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-selected')), findsOneWidget);
      expect(find.descendant(of: find.byKey(ValueKey(id0)), matching: find.byKey(const ValueKey('badge-progress'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(ValueKey(id1)), matching: find.byKey(const ValueKey('badge-selected'))), findsOneWidget);
    });

    testWidgets('scrolling to the end loads more', (t) async {
      await pump(t, gameList());
      expect(catalog.loadMores, 0);
      await t.drag(find.byType(GridView), const Offset(0, -4000));
      await t.pump();
      expect(catalog.loadMores, greaterThan(0));
    });

    testWidgets('channels are 16:9, in 4 columns at 1200 px and 2 at 500 px', (t) async {
      await pump(t, gameList());
      final cards = find.byKey(const ValueKey('wii-channel'));
      expect({for (var i = 0; i < 8; i++) t.getTopLeft(cards.at(i)).dx}.length, 4);
      final s = t.getSize(cards.first);
      expect(s.width / s.height, closeTo(16 / 9, 0.01));

      await pump(t, gameList(), size: const Size(500, 800));
      final narrow = find.byKey(const ValueKey('wii-channel'));
      expect({for (var i = 0; i < 4; i++) t.getTopLeft(narrow.at(i)).dx}.length, 2);
    });
  });
}
