import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';

void main() {
  /// A stand-in route: its name, and buttons that pop it with each answer.
  Widget stub(String name) => Builder(
        builder: (c) => Scaffold(
          body: Column(children: [
            Text(name),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text('$name: yes')),
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('$name: no')),
          ]),
        ),
      );

  Future<void> pump(WidgetTester t, {required bool seen}) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => enterGamesLibrary(
            Navigator.of(c),
            seen: seen,
            setup: (_) => stub('setup'),
            launcher: (_) => stub('launcher'),
            grid: (_) => const Text('grid'),
          ),
          child: const Text('enter'),
        ),
      ),
    ));
    await t.tap(find.text('enter'));
    await t.pumpAndSettle();
  }

  testWidgets('once the setup was seen, straight to the console grid', (t) async {
    await pump(t, seen: true);
    expect(find.text('grid'), findsOneWidget);
    expect(find.text('setup'), findsNothing);
  });

  testWidgets('a setup finished without launcher mode goes on to the grid', (t) async {
    await pump(t, seen: false);
    expect(find.text('grid'), findsNothing);
    await t.tap(find.text('setup: no'));
    await t.pumpAndSettle();
    expect(find.text('launcher'), findsNothing);
    expect(find.text('grid'), findsOneWidget);
  });

  testWidgets('Finish with launcher mode on opens the launcher wizard, then the console grid', (t) async {
    await pump(t, seen: false);
    await t.tap(find.text('setup: yes'));
    await t.pumpAndSettle();
    expect(find.text('launcher'), findsOneWidget);
    expect(find.text('grid'), findsNothing, reason: 'the grid waits for the launcher wizard');
    await t.tap(find.text('launcher: no'));
    await t.pumpAndSettle();
    expect(find.text('grid'), findsOneWidget);
  });
}
