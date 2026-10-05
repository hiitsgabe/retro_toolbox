import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

void main() {
  final saved = Handheld.current;
  tearDown(() => Handheld.current = saved);

  late RosterDoc doc;

  Future<void> pump(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 900);
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    doc = RosterDoc(
      leagueRaw: {'name': 'L'},
      teams: [
        for (final (i, n) in ['One', 'Two', 'Three'].indexed)
          RosterTeam(teamRaw: {'id': i + 1, 'name': 'Team $n'}, players: [], statsRaw: {}, extraRaw: {}),
      ],
    );
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => SportPatcherWizardScreen(
                info: const PatcherInfo(gameId: 'g', platform: 'p', sport: 's', requiresSlotMapping: false, providers: ['x']),
                initialDoc: doc,
                initialStep: 1,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  List<String> names() => doc.teams.map((e) => e.name).toList();

  testWidgets('swap reorders two teams by keyboard', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(names(), ['Team Three', 'Team Two', 'Team One']);
  });

  testWidgets('B cancels a swap without leaving the step', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(names(), ['Team One', 'Team Two', 'Team Three']);
    expect(find.text('Team One'), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsWidgets); // back to normal rows
  });

  bool focusInRow() {
    var inRow = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
      inRow = e.widget is ListTile;
      return !inRow;
    });
    return inRow;
  }

  testWidgets('Y on a team row starts a swap', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first); // lands focus on a row
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape); // back to normal, focus stays on the row
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.swap_vert), findsWidgets);
    await t.sendKeyEvent(LogicalKeyboardKey.f3);
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.swap_vert), findsNothing); // swap mode hides row actions
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(names(), ['Team Two', 'Team One', 'Team Three']);
  });

  testWidgets('changing step drops an armed swap, so B steps back at once', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.f5); // Start: on to the ROM step
    await t.pumpAndSettle();
    expect(find.text('Add team'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Add team'), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsWidgets); // not armed
  });

  testWidgets('deleting a team asks first', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.delete_outline).first);
    await t.pumpAndSettle();
    expect(find.text('Remove team?'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // Cancel is focused
    await t.pumpAndSettle();
    expect(doc.teams.length, 3);
    await t.tap(find.byIcon(Icons.delete_outline).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(names(), ['Team Two', 'Team Three']);
    expect(focusInRow(), isTrue);
  });

  testWidgets('drag handles are hidden on handhelds', (t) async {
    Handheld.current = true;
    await pump(t);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });
}
