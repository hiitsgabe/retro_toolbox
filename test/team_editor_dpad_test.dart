import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

RosterTeam _team() => RosterTeam(
      teamRaw: {'id': 1, 'name': 'Team', 'color': '000000'},
      players: [for (final n in ['Ann', 'Ben', 'Cal']) RosterPlayer(raw: {'id': -n.codeUnitAt(0), 'name': n, 'position': 'F'})],
      statsRaw: {},
      extraRaw: {},
    );

void main() {
  final saved = Handheld.current;
  tearDown(() => Handheld.current = saved);

  Future<RosterTeam> pump(WidgetTester t, {String gameId = 'nbalive95-genesis'}) async {
    final team = _team();
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: key,
      builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(
            MaterialPageRoute<void>(builder: (_) => TeamEditorScreen(team: team, gameId: gameId, sport: 'basketball')),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return team;
  }

  testWidgets('colour swatches are focusable and Enter picks one', (t) async {
    final team = await pump(t, gameId: 'iss-snes');
    await t.tap(find.text('Primary'));
    await t.pumpAndSettle();
    expect(find.text('Team color'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // second swatch (first is autofocused)
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Team color'), findsNothing);
    expect(team.color, 'C2185B');
  });

  testWidgets('B while swapping cancels the swap and stays on the screen', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pump();
    expect(find.textContaining('swap with Ann'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.textContaining('swap with'), findsNothing);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.byType(TeamEditorScreen), findsOneWidget);
  });

  testWidgets('swapping moves focus to the picked row, so Down + Enter swaps', (t) async {
    final team = await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(team.players.map((p) => p.name), ['Ben', 'Ann', 'Cal']);
  });

  testWidgets('removing a player asks first; Cancel is focused and keeps them', (t) async {
    final team = await pump(t);
    await t.tap(find.byIcon(Icons.delete_outline).first);
    await t.pumpAndSettle();
    expect(find.text('Remove player?'), findsOneWidget);
    expect(team.players.length, 3);
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // Cancel has focus
    await t.pumpAndSettle();
    expect(team.players.length, 3);

    await t.tap(find.byIcon(Icons.delete_outline).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(team.players.map((p) => p.name), ['Ben', 'Cal']);
    var inRow = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
      inRow = e.widget is ListTile;
      return !inRow;
    });
    expect(inRow, isTrue);
  });

  testWidgets('drag handles are hidden on handhelds', (t) async {
    Handheld.current = true;
    await pump(t);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });
}
