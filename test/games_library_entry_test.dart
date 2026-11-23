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

  group('a Home press', () {
    final nav = GlobalKey<NavigatorState>();

    /// The menu, with [above] pushed over it in order.
    Future<void> open(WidgetTester t, List<String> above) async {
      await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Text('menu')));
      for (final name in above) {
        if (name == 'grid') {
          enterGamesLibrary(nav.currentState!, seen: true, grid: (_) => const Text('grid'));
        } else {
          nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => Text(name)));
        }
        await t.pumpAndSettle();
      }
    }

    Future<void> home(WidgetTester t) async {
      goToLibraryRoot(nav.currentState!, grid: (_) => const Text('new grid'));
      await t.pumpAndSettle();
    }

    testWidgets('closes everything over the console grid', (t) async {
      await open(t, ['grid', 'console', 'details']);
      await home(t);
      expect(find.text('grid'), findsOneWidget);
      expect(find.text('details'), findsNothing);
      expect(find.text('new grid'), findsNothing);
    });

    testWidgets('on the console grid itself changes nothing', (t) async {
      await open(t, ['grid']);
      await home(t);
      expect(find.text('grid'), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('menu'), findsOneWidget, reason: 'no second grid was pushed');
    });

    testWidgets('with no console grid open, closes what is open and opens one over the menu', (t) async {
      await open(t, ['settings']);
      await home(t);
      expect(find.text('new grid'), findsOneWidget);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('menu'), findsOneWidget);
    });
  });

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
