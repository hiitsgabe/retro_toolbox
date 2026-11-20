import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/menu_order_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_reorder.dart';
import 'package:retro_toolbox/widgets/settings/style_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('order', () {
    test('a saved order applies; unknown ids are skipped, missing ones follow in default order', () {
      expect(applyMenuOrder(['a', 'b', 'c', 'd'], null), ['a', 'b', 'c', 'd']);
      expect(applyMenuOrder(['a', 'b', 'c', 'd'], ['c', 'gone', 'a']), ['c', 'a', 'b', 'd']);
      expect(applyMenuOrder(['a', 'b'], ['b', 'b', 'a']), ['b', 'a']);
    });

    test('a hidden tile keeps its slot through a move, and is back there when shown again', () {
      final saved = mergeMenuOrder(['a', 'h', 'b', 'c'], ['c', 'a', 'b']);
      expect(saved, ['c', 'h', 'a', 'b']);
      expect(applyMenuOrder(['a', 'h', 'b', 'c'], saved), ['c', 'h', 'a', 'b']);
    });

    test('tiles new to the saved order are saved too', () {
      expect(mergeMenuOrder(null, ['b', 'a']), ['b', 'a']);
      expect(mergeMenuOrder(['a'], ['n', 'a']), ['n', 'a']);
    });

    test('the order is saved per menu and read back; reset forgets every menu', () async {
      final first = MenuOrderNotifier();
      await first.loaded;
      await first.save('home', ['b', 'a']);
      await first.save('tools', ['y', 'x']);
      final again = MenuOrderNotifier();
      await again.loaded;
      expect(again.state, {
        'home': ['b', 'a'],
        'tools': ['y', 'x'],
      });
      await again.reset();
      expect(again.state, isEmpty);
      expect((await SharedPreferences.getInstance()).getString('menu_order'), isNull);
    });
  });

  group('layout index math', () {
    const l = TraversalDirection.left, r = TraversalDirection.right, u = TraversalDirection.up, d = TraversalDirection.down;

    test('grid: rows of 3', () {
      const m = MenuMove.grid(3);
      expect(m.target(2, r, 7), 3);
      expect(m.target(1, d, 7), 4);
      expect(m.target(4, d, 7), 6, reason: 'the short last row: its last tile');
      expect(m.target(6, d, 7), isNull);
      expect(m.target(1, u, 7), isNull);
    });

    test('columns: the 3DS shelf, 3 rows', () {
      const m = MenuMove.columns(3);
      expect(m.target(0, d, 7), 1);
      expect(m.target(1, r, 7), 4);
      expect(m.target(4, r, 7), 6);
      expect(m.target(1, l, 7), isNull);
    });

    test('vita: rows of 4 and 3', () {
      const m = MenuMove.vita(4);
      expect(m.target(1, d, 9), 5);
      expect(m.target(3, d, 9), 6);
      expect(m.target(5, d, 9), 8);
      expect(m.target(6, d, 9), 8);
      expect(m.target(4, u, 9), 0);
      expect(m.target(0, u, 9), isNull);
    });

    test('row: left and right only', () {
      const m = MenuMove.row();
      expect(m.target(0, r, 3), 1);
      expect(m.target(2, r, 3), isNull);
      expect(m.target(1, d, 3), isNull);
    });
  });

  final taps = <String>[];
  setUp(taps.clear);

  List<MenuTile> tiles(int n, {bool tasks = false}) => [
        if (tasks) MenuTile(id: MenuTile.tasksId, label: 'Tasks (1)', icon: Icons.sync, onTap: () => taps.add(MenuTile.tasksId)),
        for (final id in 'abcdef'.split('').take(n)) MenuTile(id: id, label: 'Tile $id', icon: Icons.star, onTap: () => taps.add(id)),
      ];

  Widget menu(List<MenuTile> tiles) => Scaffold(body: MenuGrid(menuId: 'test', tiles: tiles));

  Future<ProviderContainer> pump(WidgetTester t, Widget home, {CardStyle cards = CardStyle.classic, InputMode input = InputMode.gamepad}) async {
    final container = ProviderContainer(overrides: [inputModeProvider.overrideWith((ref) => input)]);
    addTearDown(container.dispose);
    await container.read(styleProvider.notifier).loaded;
    await container.read(menuOrderProvider.notifier).loaded;
    if (cards != CardStyle.classic) await container.read(styleProvider.notifier).setCards(cards);
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

  // The Vita's lifted bubble rocks for as long as it is lifted: no settling.
  Future<void> press(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  Future<void> holdA(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 600));
    await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  /// The tiles on screen, first to last.
  List<String> shown(WidgetTester t) => [for (final w in t.widgetList<MenuReorderTarget>(find.byType(MenuReorderTarget))) w.tile.id];

  /// Where each place of the layout is on screen, by index.
  List<Offset> slots(WidgetTester t) => [
        for (final e in find.byType(MenuReorderTarget).evaluate())
          if (e.renderObject case final RenderBox box) box.localToGlobal(box.size.center(Offset.zero)),
      ];

  final hint = find.byKey(const ValueKey('menu-move-hint'));

  testWidgets('Classic grid: a short A runs the tile; holding A lifts it, shows the hint, the arrows move it and A drops it', (t) async {
    final container = await pump(t, menu(tiles(6)));
    await press(t, LogicalKeyboardKey.enter);
    expect(taps, ['a']);
    expect(hint, findsNothing);

    final before = slots(t);
    await holdA(t);
    expect(hint, findsOneWidget);
    expect(find.text('◀▶ move'), findsOneWidget);
    expect(taps, ['a'], reason: 'the hold lifts, it does not run the tile');

    await press(t, LogicalKeyboardKey.arrowRight);
    expect(shown(t).take(3), ['b', 'a', 'c']);
    await press(t, LogicalKeyboardKey.arrowDown);
    final at = shown(t).indexOf('a');
    expect(before[at].dy, greaterThan(before[1].dy + 1), reason: 'down is the slot under it');
    expect(container.read(menuOrderProvider)['test'], isNull, reason: 'nothing is saved before the drop');

    await press(t, LogicalKeyboardKey.enter);
    expect(hint, findsNothing);
    expect(container.read(menuOrderProvider)['test'], shown(t));
    expect(taps, ['a'], reason: 'the drop runs nothing');
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('menu_order')!), {'test': shown(t)});
  });

  for (final (cards, name, down) in [
    (CardStyle.classic, 'Classic grid', true),
    (CardStyle.vita, 'Vita rows', true),
    (CardStyle.threeDs, '3DS columns', true),
    (CardStyle.wii, 'Wii', true),
    (CardStyle.switchStyle, 'Switch row', false),
  ]) {
    testWidgets('$name: right takes the lifted tile to the next place across, down to the one under it', (t) async {
      final container = await pump(t, menu(tiles(6)), cards: cards);
      final before = slots(t);
      final width = t.getSize(find.byType(MenuReorderTarget).first).width;
      await holdA(t);
      expect(hint, findsOneWidget);

      await press(t, LogicalKeyboardKey.arrowRight);
      final across = shown(t).indexOf('a');
      expect(across, greaterThan(0));
      expect(before[across].dx, greaterThan(before[0].dx + 1));
      expect((before[across].dy - before[0].dy).abs(), lessThan(1), reason: 'same row');

      await press(t, LogicalKeyboardKey.arrowDown);
      final under = shown(t).indexOf('a');
      if (down) {
        expect(before[under].dy, greaterThan(before[across].dy + 1));
        expect((before[under].dx - before[across].dx).abs(), lessThan(width), reason: 'under it, not elsewhere');
      } else {
        expect(under, across, reason: 'one row: down leaves it there');
      }

      await press(t, LogicalKeyboardKey.enter);
      final saved = container.read(menuOrderProvider)['test']!;
      expect(saved.indexOf('a'), under);
      expect(saved.toSet(), {'a', 'b', 'c', 'd', 'e', 'f'});
    });
  }

  testWidgets('B puts the tile back where it was and does not leave the menu', (t) async {
    final container = await pump(t, const Scaffold(body: Text('below')));
    Navigator.of(t.element(find.text('below'))).push(MaterialPageRoute(builder: (_) => menu(tiles(4))));
    await t.pumpAndSettle();
    await holdA(t);
    await press(t, LogicalKeyboardKey.arrowRight);
    expect(shown(t), ['b', 'a', 'c', 'd']);

    await press(t, LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(shown(t), ['a', 'b', 'c', 'd']);
    expect(hint, findsNothing);
    expect(find.byType(MenuGrid), findsOneWidget);
    expect(container.read(menuOrderProvider)['test'], isNull);
  });

  testWidgets('touch: a long press lifts, a drag moves, the release drops; no hint without a pad', (t) async {
    final container = await pump(t, menu(tiles(4)), input: InputMode.touch);
    final target = t.getCenter(find.byKey(const ValueKey('Tile c')));
    final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('Tile a'))));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump();
    expect(hint, findsNothing);
    await g.moveTo(target);
    await t.pump();
    expect(shown(t), ['b', 'c', 'a', 'd']);
    await g.up();
    await t.pumpAndSettle();
    expect(container.read(menuOrderProvider)['test'], ['b', 'c', 'a', 'd']);
    expect(taps, isEmpty);
  });

  testWidgets('the Tasks tile stays first: it cannot be lifted, and nothing moves ahead of it', (t) async {
    final container = await pump(t, menu(tiles(3, tasks: true)));
    await holdA(t);
    expect(hint, findsNothing);
    await t.longPress(find.byKey(const ValueKey('Tasks (1)')));
    await t.pumpAndSettle();
    expect(hint, findsNothing);

    await press(t, LogicalKeyboardKey.arrowRight);
    await holdA(t);
    expect(hint, findsOneWidget);
    await press(t, LogicalKeyboardKey.arrowLeft);
    expect(shown(t), [MenuTile.tasksId, 'a', 'b', 'c']);
    await press(t, LogicalKeyboardKey.enter);
    expect(container.read(menuOrderProvider)['test'], isNull, reason: 'an unchanged order is not saved');
  });

  testWidgets('a saved order is what the menu shows; ids it does not know are skipped', (t) async {
    SharedPreferences.setMockInitialValues({
      'menu_order': jsonEncode({
        'test': ['c', 'gone', 'a'],
      }),
    });
    await pump(t, menu(tiles(4)));
    expect(shown(t), ['c', 'a', 'b', 'd']);
  });

  testWidgets('holding A on a game card still opens its box art', (t) async {
    const game = Game(title: 'Art', url: 'https://example.com/files/art.zip', size: 1, consoleId: 'con', details: GameDetails(boxart: 'https://example.com/art.png'));
    final opened = <Game>[];
    debugShowBoxart = (_, g) => opened.add(g);
    addTearDown(() => debugShowBoxart = null);
    await pump(
      t,
      Scaffold(
        body: Column(children: [
          Expanded(child: MenuGrid(menuId: 'test', tiles: tiles(3), autofocusFirst: false)),
          GameCardActions(game: game, selectable: false, child: TextButton(autofocus: true, onPressed: () {}, child: const Text('card'))),
        ]),
      ),
    );
    await holdA(t);
    expect(opened, [game]);
    expect(hint, findsNothing);
  });

  testWidgets('Settings > Style resets every menu order', (t) async {
    SharedPreferences.setMockInitialValues({
      'menu_order': jsonEncode({
        'home': ['b', 'a'],
      }),
    });
    final container = await pump(t, Scaffold(body: ListView(children: const [StyleSettingRows()])));
    await t.ensureVisible(find.text('Reset menu order'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reset menu order'));
    await t.pumpAndSettle();
    expect(container.read(menuOrderProvider), isEmpty);
  });
}
