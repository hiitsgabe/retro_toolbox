import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
}
