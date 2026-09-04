import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/menu_grid/menu_grid.dart';

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
}
