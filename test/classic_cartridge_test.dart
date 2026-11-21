import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/menu_grid_screen.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The text inside `MenuTile(...)`, for each construction in [source].
List<String> _menuTileCalls(String source) {
  final calls = <String>[];
  for (final m in RegExp(r'\bMenuTile\(').allMatches(source)) {
    var depth = 0;
    for (var i = m.end - 1; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')' && --depth == 0) {
        calls.add(source.substring(m.start, i + 1));
        break;
      }
    }
  }
  return calls;
}

void main() {
  test('every MenuTile in lib/ names its area and its pixel icon', () {
    // The scan must see a call that lacks them.
    expect(_menuTileCalls("MenuTile(label: 'x', icon: Icons.add, onTap: () => f(g()))"), hasLength(1));
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    final calls = <String, List<String>>{};
    for (final f in files) {
      final found = _menuTileCalls(f.readAsStringSync()).where((c) => !c.contains('this.label'));
      if (found.isNotEmpty) calls[f.path] = found.toList();
    }
    // Home with Servers and Tools, consoles, sports.
    expect(calls.keys.where((p) => p.endsWith('menu_screen.dart')), hasLength(1));
    expect(calls.values.expand((c) => c).length, greaterThanOrEqualTo(30));
    for (final MapEntry(key: path, value: list) in calls.entries) {
      for (final c in list) {
        expect(c, contains('area: AppArea.'), reason: '$path: $c');
        expect(c, contains('pixelIcon: '), reason: '$path: $c');
      }
    }
  });

  group('menu screen', () {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    late Directory support;
    late bool handheld;
    setUp(() {
      handheld = Handheld.current;
      support = Directory.systemTemp.createTempSync('classic_cartridge');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => support.path);
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({'generalSettings': {}, 'libraryEnabled': true, 'tinfoilEnabled': true, 'fbiEnabled': true, 'fpkgiEnabled': true}),
      });
      MenuScreen.saveSyncShownForTest = true;
    });
    tearDown(() {
      MenuScreen.saveSyncShownForTest = null;
      Handheld.current = handheld;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null);
      support.deleteSync(recursive: true);
    });

    Future<void> pump(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
      await t.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: MenuScreen())));
      await t.pump(const Duration(milliseconds: 300));
    }

    Future<List<MenuTile>> open(WidgetTester t, String label) async {
      await t.tap(find.byKey(ValueKey(label)));
      await t.pumpAndSettle();
      final tiles = t.widget<MenuGridScreen>(find.byType(MenuGridScreen)).tiles;
      t.state<NavigatorState>(find.byType(Navigator)).pop();
      await t.pumpAndSettle();
      return tiles;
    }

    for (final h in [false, true]) {
      testWidgets('${h ? 'handheld' : 'desktop'}: each tile has its area and a pixel icon, a submenu its parent\'s area', (t) async {
        Handheld.current = h;
        await pump(t);
        // The app's name keeps Chakra Petch while titles go condensed.
        expect(t.widget<Text>(find.text('Retro Toolbox')).style?.fontFamily, 'ChakraPetch');
        final home = t.widget<MenuGrid>(find.byType(MenuGrid)).tiles;
        expect({for (final tile in home) tile.label: tile.area}, {
          'Games Library': AppArea.games,
          'Save Sync': AppArea.saves,
          'Servers': AppArea.servers,
          'Tools': AppArea.tools,
          'Sports': AppArea.sports,
          'Settings': AppArea.settings,
          'About': AppArea.info,
        });
        final servers = await open(t, 'Servers');
        final tools = await open(t, 'Tools');
        expect(servers, isNotEmpty);
        expect(tools, isNotEmpty);
        for (final tile in servers) {
          expect(tile.area, AppArea.servers, reason: tile.label);
        }
        for (final tile in tools) {
          expect(tile.area, AppArea.tools, reason: tile.label);
        }
        for (final tile in [...home, ...servers, ...tools]) {
          expect(tile.pixelIcon, isNotNull, reason: tile.label);
        }
        // One drawing per tile: no two tiles of a menu look the same.
        for (final menu in [home, servers, tools]) {
          expect(menu.map((e) => e.pixelIcon).toSet(), hasLength(menu.length));
        }
      });
    }
  });

  group('cartridge', () {
    const magenta = Color(0xFFFF00FF);
    const tile = MenuTile(label: 'Servers', icon: Icons.dns, area: AppArea.servers, pixelIcon: PixelIcons.servers, accentColor: magenta, subtitle: '1 on');

    Iterable<Color> paintedColors(WidgetTester t) sync* {
      for (final box in t.widgetList<DecoratedBox>(find.descendant(of: find.byType(MenuTileFace), matching: find.byType(DecoratedBox)))) {
        final d = box.decoration;
        if (d is! BoxDecoration) continue;
        if (d.color != null) yield d.color!;
        yield* d.gradient?.colors ?? const <Color>[];
      }
    }

    testWidgets('Classic: area colour on the label, the pixel icon in ink, the name in caps; the accent is not used', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 120, height: 220, child: MenuTileFace(tile: tile))))));
      final area = StyleTokens.areaPalette[AppArea.servers]!;
      final label = t.widget<DecoratedBox>(find.byKey(const ValueKey('cartridge-label')));
      expect((label.decoration as BoxDecoration).color, area);
      final icon = t.widget<PixelIcon>(find.byType(PixelIcon));
      expect(icon.glyph, PixelIcons.servers);
      expect(icon.color, StyleTokens.classic.surface);
      expect(find.descendant(of: find.byKey(const ValueKey('cartridge-label')), matching: find.byType(PixelIcon)), findsOneWidget);
      expect(find.text('SERVERS'), findsOneWidget);
      expect(find.bySemanticsLabel('Servers'), findsOneWidget);
      // On the area-coloured card the subtitle is in ink, a little faded.
      expect(t.widget<Text>(find.text('1 on')).style?.color, StyleTokens.classic.surface.withValues(alpha: 0.8));
      expect(paintedColors(t), isNot(contains(magenta)));
      for (final c in paintedColors(t)) {
        final hsl = HSLColor.fromColor(c);
        expect(hsl.saturation > 0.3 && (hsl.hue - 300).abs() < 10, isFalse, reason: '$c reads as the accent');
      }
    });

    for (final cartridges in [true, false]) {
      testWidgets('Odin 2: six ${cartridges ? 'cartridges sit in two rows of three' : 'plain tiles keep one row'}', (t) async {
        t.view.physicalSize = const Size(731, 411) * 2.625;
        t.view.devicePixelRatio = 2.625;
        addTearDown(t.view.reset);
        final labels = ['A', 'B', 'C', 'D', 'E', 'F'];
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: MenuGrid(tiles: [
              for (final l in labels)
                MenuTile(label: l, icon: Icons.dns, area: cartridges ? AppArea.tools : null, pixelIcon: cartridges ? PixelIcons.tools : null),
            ]),
          ),
        ));
        final tops = labels.map((l) => t.getRect(find.byKey(ValueKey(l))).top).toList();
        expect(tops.toSet(), hasLength(cartridges ? 2 : 1));
        if (cartridges) expect(tops.sublist(0, 3).toSet(), hasLength(1));
      });
    }

    testWidgets('a tile with no area keeps the old face', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox(width: 160, height: 160, child: MenuTileFace(tile: MenuTile(label: 'Plain', icon: Icons.dns)))),
      ));
      expect(find.byKey(const ValueKey('cartridge-label')), findsNothing);
      expect(find.text('Plain'), findsOneWidget);
    });

    testWidgets('focus lifts the cartridge, and the ring DpadScope draws goes with it', (t) async {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: const Scaffold(
          body: MenuGrid(tiles: [tile, MenuTile(label: 'Tools', icon: Icons.build, area: AppArea.tools, pixelIcon: PixelIcons.tools)]),
        ),
      ));
      await t.pumpAndSettle();
      Rect laidOut(String label) => t.getRect(find.byKey(ValueKey(label)));
      final focused = FocusManager.instance.primaryFocus!.rect;
      expect(focused.width, moreOrLessEquals(laidOut('Servers').width, epsilon: 0.5));
      expect(focused.top, lessThan(laidOut('Servers').top - 4));
      // The other cartridge stays down.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus!.rect.top, lessThan(laidOut('Tools').top - 4));
      expect(t.getRect(find.byType(MenuTileFace).first).top, moreOrLessEquals(laidOut('Servers').top, epsilon: 0.5));
    });
  });
}
