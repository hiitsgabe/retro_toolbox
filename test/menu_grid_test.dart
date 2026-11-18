import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

void main() {
  testWidgets('renders a tile per spec and fires onTap of the tapped tile', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuGrid(
            tiles: [
              MenuTile(label: 'Baixar Jogos', icon: Icons.download, onTap: () => tapped.add('games')),
              MenuTile(label: 'Servers', icon: Icons.dns, onTap: () => tapped.add('servers')),
              MenuTile(label: 'Settings', icon: Icons.settings, onTap: () => tapped.add('settings')),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Baixar Jogos'), findsOneWidget);
    expect(find.text('Servers'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Servers'));
    await tester.pump();

    expect(tapped, ['servers']);
  });

  testWidgets('d-pad: first tile autofocused, arrowRight + Enter activates the second', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: Scaffold(
          body: MenuGrid(
            tiles: [
              MenuTile(label: 'One', icon: Icons.download, onTap: () => tapped.add('one')),
              MenuTile(label: 'Two', icon: Icons.dns, onTap: () => tapped.add('two')),
              MenuTile(label: 'Three', icon: Icons.settings, onTap: () => tapped.add('three')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final focused = find.byWidget(FocusManager.instance.primaryFocus!.context!.widget);
    expect(find.descendant(of: focused, matching: find.text('One')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tapped, ['two']);
  });
  for (final traditional in [false, true]) {
    testWidgets('autofocused first tile ${traditional ? 'has' : 'lacks'} the focused look in ${traditional ? 'traditional' : 'touch'} mode', (tester) async {
      FocusManager.instance.highlightStrategy =
          traditional ? FocusHighlightStrategy.alwaysTraditional : FocusHighlightStrategy.alwaysTouch;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuGrid(tiles: [MenuTile(label: 'One', icon: Icons.download, onTap: () {})]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      // Check that no DecoratedBox with a 3px focus border exists inside the tile
      final tileKey = find.byKey(const ValueKey('One'));
      final focusBorderInTile = find.descendant(
        of: tileKey,
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && (w.decoration as BoxDecoration?)?.border?.top.width == 3,
        ),
      );
      expect(scale, traditional ? 1.05 : 1);
      expect(focusBorderInTile, findsNothing);
    });
  }

  testWidgets('focused look appears when highlight mode flips to traditional', (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuGrid(tiles: [MenuTile(label: 'One', icon: Icons.download, onTap: () {})]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.05);
  });

  group('brand logo tiles', () {
    Future<void> pumpFace(WidgetTester tester, MenuTile tile) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SizedBox(width: 180, height: 180, child: MenuTileFace(tile: tile)))),
        );

    ColorFilter? filterOf(WidgetTester tester) => tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter;

    testWidgets('a console logo drops the label and is drawn white on the accent', (tester) async {
      await pumpFace(
        tester,
        const MenuTile(label: 'Nintendo Wii', icon: Icons.videogame_asset, assetPath: 'assets/console_art/wii_logo.svg', accentColor: Colors.blue, brandLogo: true),
      );

      expect(find.text('Nintendo Wii'), findsNothing);
      expect(filterOf(tester), const ColorFilter.mode(Colors.white, BlendMode.srcIn));
    });

    testWidgets('a console logo fills its box even when the SVG declares a smaller size', (tester) async {
      // xbox360_logo.svg declares 123 x 123, under the box: (180 less the 1 px
      // border and 18 px padding a side) = 142.
      await pumpFace(
        tester,
        const MenuTile(label: 'Xbox 360', icon: Icons.videogame_asset, assetPath: 'assets/console_art/xbox360_logo.svg', accentColor: Colors.green, brandLogo: true),
      );

      expect(tester.getSize(find.byType(SvgPicture)), const Size(142, 142));
    });

    testWidgets('without an accent the logo takes the text color', (tester) async {
      await pumpFace(
        tester,
        const MenuTile(label: 'Nintendo Wii', icon: Icons.videogame_asset, assetPath: 'assets/console_art/wii_logo.svg', brandLogo: true),
      );

      final onSurface = Theme.of(tester.element(find.byType(MenuTileFace))).colorScheme.onSurface;
      expect(filterOf(tester), ColorFilter.mode(onSurface, BlendMode.srcIn));
    });

    testWidgets('a console with no bundled logo keeps its name under the icon', (tester) async {
      await pumpFace(tester, const MenuTile(label: 'Odyssey 2', icon: Icons.videogame_asset, accentColor: Colors.blue, brandLogo: true));

      expect(find.text('Odyssey 2'), findsOneWidget);
    });

    testWidgets('other tiles keep their label and their own colors', (tester) async {
      await pumpFace(
        tester,
        const MenuTile(label: 'Sports', icon: Icons.sports, assetPath: 'assets/console_art/wii_logo.svg', accentColor: Colors.blue),
      );

      expect(find.text('Sports'), findsOneWidget);
      expect(filterOf(tester), isNull);
    });
  });
}
