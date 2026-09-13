import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/menu_grid/menu_grid.dart';
import 'package:roms_downloader/screens/addons_screen.dart';
import 'package:roms_downloader/screens/menu_screen.dart';

void main() {
  testWidgets('renders a tile per spec and fires onTap of the tapped tile', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuGrid(
            tiles: [
              MenuTile(label: 'Download Games', icon: Icons.download, onTap: () => tapped.add('games')),
              MenuTile(label: 'Servers', icon: Icons.dns, onTap: () => tapped.add('servers')),
              MenuTile(label: 'Settings', icon: Icons.settings, onTap: () => tapped.add('settings')),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Download Games'), findsOneWidget);
    expect(find.text('Servers'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Servers'));
    await tester.pump();

    expect(tapped, ['servers']);
  });

  testWidgets('the Tools tiles open the Addons screen', (tester) async {
    final opened = <Type>[];
    final tiles = toolsTiles((screen) => opened.add(screen.runtimeType));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MenuGrid(tiles: tiles))));
    await tester.tap(find.text('Addons'));
    await tester.pump();

    expect(opened, [AddonsScreen]);
  });
}
