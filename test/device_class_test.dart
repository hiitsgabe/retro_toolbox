import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog(super.state);

  @override
  bool get groupsVersions => false;

  @override
  Future<void> loadMoreItems() async {}

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

/// The reference devices: logical size and device pixel ratio.
const _odin2 = (Size(731, 411), 2.625);
const _phone = (Size(412, 915), 2.625);
const _linux640 = (Size(640, 480), 1.0);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => Handheld.framebuffer = false);

  group('detection', () {
    test('the three reference devices', () {
      expect(DeviceClass.from(_odin2.$1, _odin2.$2), DeviceClass.landscapeLow);
      expect(DeviceClass.from(_phone.$1, _phone.$2), DeviceClass.portrait);
      expect(DeviceClass.from(_linux640.$1, _linux640.$2), DeviceClass.pixel);
    });

    test('the framebuffer build is pixel at any size; big screens are roomy', () {
      expect(DeviceClass.from(const Size(800, 600), 2, framebuffer: true), DeviceClass.pixel);
      expect(DeviceClass.from(const Size(1280, 800), 1.5), DeviceClass.roomy);
      expect(DeviceClass.from(const Size(800, 1280), 2), DeviceClass.roomy, reason: 'a tablet held upright');
      expect(DeviceClass.from(const Size(915, 412), 2.625), DeviceClass.landscapeLow, reason: 'a phone on its side');
    });

    testWidgets('of(context) reads the screen and the framebuffer flag', (t) async {
      DeviceClass? seen;
      Future<void> at((Size, double) device) async {
        t.view.devicePixelRatio = device.$2;
        t.view.physicalSize = device.$1 * device.$2;
        addTearDown(t.view.reset);
        await t.pumpWidget(Builder(builder: (context) {
          seen = DeviceClass.of(context);
          return const SizedBox();
        }));
      }

      await at(_odin2);
      expect(seen, DeviceClass.landscapeLow);
      await at(_phone);
      expect(seen, DeviceClass.portrait);
      await at(_linux640);
      expect(seen, DeviceClass.pixel);
      Handheld.framebuffer = true;
      await at((const Size(800, 600), 2));
      expect(seen, DeviceClass.pixel);
    });
  });

  test('menus: one row up to 6 and two up to 12 on a low screen, 2 columns on a phone, 3 on pixel', () {
    expect(DeviceClass.landscapeLow.menuFit(6), const MenuFit(6, 1));
    expect(DeviceClass.landscapeLow.menuFit(9), const MenuFit(5, 2));
    expect(DeviceClass.landscapeLow.menuFit(12), const MenuFit(6, 2));
    expect(DeviceClass.landscapeLow.menuFit(20), const MenuFit(6, 2), reason: 'two rows on screen, the rest scrolls');
    expect(DeviceClass.portrait.menuFit(6), const MenuFit(2, 3));
    expect(DeviceClass.pixel.menuFit(9), const MenuFit(3, 3));
    expect(DeviceClass.roomy.menuFit(6), isNull);
  });

  test('game grid columns per class', () {
    expect(DeviceClass.landscapeLow.gameColumns(731), 6);
    expect(DeviceClass.landscapeLow.gameColumns(640), 5);
    expect(DeviceClass.portrait.gameColumns(412), 3);
    expect(DeviceClass.pixel.gameColumns(640), 4);
    expect(DeviceClass.roomy.gameColumns(1280), isNull);
  });

  test('largestFit picks the columns with the widest cells', () {
    final fit = largestFit(6, const Size(700, 300), [1, 2, 3, 6], aspect: 16 / 9, gap: 10)!;
    expect(fit.columns, 3, reason: '3 x 2 channels beat 6 small ones in a row');
    expect(largestFit(40, const Size(300, 200), [2], aspect: 1, minWidth: 48), isNull);
  });

  testWidgets('theme text styles are clamped to 13 on pixel and 12 elsewhere', (t) async {
    TextTheme? text;
    Future<void> at((Size, double) device) async {
      t.view.devicePixelRatio = device.$2;
      t.view.physicalSize = device.$1 * device.$2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (context, child) => TextFloor(child: child!),
        home: Builder(builder: (context) {
          text = Theme.of(context).textTheme;
          return const SizedBox();
        }),
      ));
    }

    await at(_linux640);
    expect(text!.labelSmall!.fontSize, 13);
    expect(text!.bodySmall!.fontSize, 13);
    expect(text!.titleLarge!.fontSize, 22, reason: 'larger styles keep their size');
    await at(_odin2);
    expect(text!.labelSmall!.fontSize, 12);
    expect(text!.bodySmall!.fontSize, 12);
  });

  /// Pumps [home] under [style] at [device], as the app does.
  Future<void> pump(WidgetTester t, Widget home, (Size, double) device, CardStyle style, {List<Override> overrides = const []}) async {
    t.view.devicePixelRatio = device.$2;
    t.view.physicalSize = device.$1 * device.$2;
    addTearDown(t.view.reset);
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await container.read(styleProvider.notifier).loaded;
    await container.read(styleProvider.notifier).setCards(style);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: home)));
    await t.pump();
  }

  final six = [for (var i = 0; i < 6; i++) MenuTile(label: 'Tile $i', icon: Icons.star, accentColor: Colors.teal)];
  final nine = [for (var i = 0; i < 9; i++) MenuTile(label: 'Tile $i', icon: Icons.star, accentColor: Colors.teal)];

  // Six is the home menu, nine about Tools; Switch keeps its one row, which
  // scrolls past six (see below).
  for (final (style, tiles) in [for (final s in CardStyle.values) (s, six), for (final s in CardStyle.values) if (s != CardStyle.switchStyle) (s, nine)]) {
    testWidgets('${style.name}: a ${tiles.length} tile menu fits the Odin 2 without scrolling', (t) async {
      await pump(t, Scaffold(appBar: AppBar(title: const Text('Home')), body: MenuGrid(tiles: tiles)), _odin2, style);
      final screen = Offset.zero & _odin2.$1;
      for (final tile in tiles) {
        final card = find.byKey(ValueKey(tile.label));
        expect(card, findsOneWidget, reason: tile.label);
        final rect = t.getRect(card);
        expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight - const Offset(0.01, 0.01)), isTrue, reason: '${tile.label} at $rect');
      }
      for (final s in t.stateList<ScrollableState>(find.byType(Scrollable))) {
        expect(s.position.maxScrollExtent, lessThan(0.5), reason: 'nothing to scroll to');
      }
    });
  }

  group('game grids', () {
    final games = [for (var i = 0; i < 30; i++) Game(title: 'Game $i', url: 'https://x/g$i.zip', size: 1, consoleId: 'snes')];
    final overrides = [
      gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: GameStatus.ready)),
      gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
      favoritesProvider.overrideWith((ref) => _FakeFavorites()),
      catalogProvider.overrideWith((ref) => _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: false))),
    ];

    /// Cards whose top is the first card's: the columns.
    int columns(WidgetTester t, Finder card) {
      final cards = card.evaluate().toList();
      final top = t.getTopLeft(find.byWidget(cards.first.widget)).dy;
      return cards.where((c) => t.getTopLeft(find.byWidget(c.widget)).dy == top).length;
    }

    // Switch's frames and names take room: one column fewer on the Odin 2.
    for (final (device, name, want, switchWant) in [(_odin2, 'Odin 2', 6, 5), (_phone, 'phone', 3, 3), (_linux640, 'pixel', 4, 4)]) {
      testWidgets('Classic has $want columns on the $name', (t) async {
        await pump(t, const Scaffold(body: GameGrid()), device, CardStyle.classic, overrides: overrides);
        expect(columns(t, find.byType(GameGridItem)), want);
      });

      testWidgets('Switch has $switchWant columns on the $name', (t) async {
        await pump(t, Scaffold(body: Builder(builder: (c) => cardStyleKit(CardStyle.switchStyle)!.gameList(c))), device, CardStyle.switchStyle,
            overrides: overrides);
        expect(columns(t, find.byKey(const ValueKey('switch-placeholder'))), switchWant);
      });
    }
  });

  group('each style keeps its layout, sized from the class', () {
    Widget menu(List<MenuTile> tiles) => Scaffold(appBar: AppBar(title: const Text('Home')), body: MenuGrid(tiles: tiles));

    /// Distinct left edges of [labels]' cards: the columns in use.
    int columnsOf(WidgetTester t, List<MenuTile> tiles) => {for (final tile in tiles) t.getTopLeft(find.byKey(ValueKey(tile.label))).dx.round()}.length;

    testWidgets('3DS on a phone: more than one column, so right moves', (t) async {
      await pump(t, menu(six), _phone, CardStyle.threeDs);
      expect(columnsOf(t, six), greaterThan(1));
    });

    testWidgets('3DS on the Odin 2: the top strip takes at most 22% of the height', (t) async {
      await pump(t, menu(six), _odin2, CardStyle.threeDs);
      expect(t.getSize(find.byKey(const ValueKey('3ds-strip'))).height, lessThanOrEqualTo(_odin2.$1.height * 0.22));
    });

    testWidgets('3DS on pixel: one name line in the strip', (t) async {
      await pump(t, menu(six), _linux640, CardStyle.threeDs);
      expect(t.widget<Text>(find.byKey(const ValueKey('3ds-strip-name'))).maxLines, 1);
    });

    testWidgets('Switch on a phone: two columns instead of one row', (t) async {
      await pump(t, menu(nine), _phone, CardStyle.switchStyle);
      expect(columnsOf(t, nine.take(4).toList()), 2);
      final rows = {for (final tile in nine.take(4)) t.getTopLeft(find.byKey(ValueKey(tile.label))).dy.round()};
      expect(rows, hasLength(2));
    });

    testWidgets('Switch on the Odin 2: no card cut at the screen edge', (t) async {
      final many = [for (var i = 0; i < 12; i++) MenuTile(label: 'Tile $i', icon: Icons.star, accentColor: Colors.teal)];
      await pump(t, menu(many), _odin2, CardStyle.switchStyle);
      final width = _odin2.$1.width;
      for (final tile in many) {
        final card = find.byKey(ValueKey(tile.label));
        if (card.evaluate().isEmpty) continue;
        final r = t.getRect(card);
        expect(r.right <= width || r.left >= width, isTrue, reason: '${tile.label} at $r');
      }
    });

    // Six cards in the row, as the spec has it, but six small ones read as
    // a strip: the edges and gaps keep only the focus frame's room.
    testWidgets('Switch on the Odin 2: the six home cards take most of the width', (t) async {
      await pump(t, menu(six), _odin2, CardStyle.switchStyle);
      final widths = [for (final tile in six) t.getSize(find.byKey(ValueKey(tile.label))).width];
      expect(widths.reduce((a, b) => a + b), greaterThan(_odin2.$1.width * 0.84));
    });

    // On a phone the menu took two bubbles across, half as large again as
    // the games after it.
    for (final (device, name) in [(_phone, 'phone'), (_odin2, 'Odin 2'), (_linux640, 'pixel')]) {
      testWidgets('Vita on the $name: home bubbles no larger than game bubbles', (t) async {
        final games = [for (var i = 0; i < 12; i++) Game(title: 'Game $i', url: 'https://x/g$i.zip', size: 1, consoleId: 'snes')];
        final overrides = [
          gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: GameStatus.ready)),
          gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
          favoritesProvider.overrideWith((ref) => _FakeFavorites()),
          catalogProvider.overrideWith((ref) => _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: false))),
        ];
        await pump(t, menu(six), device, CardStyle.vita);
        final menuBubble = t.getSize(find.byType(ClipOval).first).width;
        await pump(t, Scaffold(body: Builder(builder: (c) => cardStyleKit(CardStyle.vita)!.gameList(c))), device, CardStyle.vita, overrides: overrides);
        expect(menuBubble, lessThanOrEqualTo(t.getSize(find.byType(ClipOval).first).width + 0.5));
      });
    }

    testWidgets('Vita: game bubbles are larger than menu bubbles on the Odin 2', (t) async {
      final games = [for (var i = 0; i < 12; i++) Game(title: 'Game $i', url: 'https://x/g$i.zip', size: 1, consoleId: 'snes')];
      final overrides = [
        gameStateProvider.overrideWith((ref, g) => GameState(game: g, status: GameStatus.ready)),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        catalogProvider.overrideWith((ref) => _FakeCatalog(CatalogState(games: games, cachedFilteredGames: games, cachedHasMore: false))),
      ];
      await pump(t, menu(nine), _odin2, CardStyle.vita);
      final menuBubble = t.getSize(find.byType(ClipOval).first).width;
      await pump(t, Scaffold(body: Builder(builder: (c) => cardStyleKit(CardStyle.vita)!.gameList(c))), _odin2, CardStyle.vita, overrides: overrides);
      expect(t.getSize(find.byType(ClipOval).first).width, greaterThan(menuBubble));
    });
  });
}
