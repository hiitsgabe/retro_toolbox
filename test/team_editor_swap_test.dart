import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';

RosterTeam _team() => RosterTeam(
      teamRaw: {'id': 1, 'name': 'Team'},
      // Negative ids: no headshot URL, so nothing reaches the network.
      players: [for (final n in ['Ann', 'Ben', 'Cal', 'Dan']) RosterPlayer(raw: {'id': -n.codeUnitAt(0), 'name': n, 'position': 'F'})],
      statsRaw: {},
      extraRaw: {},
    );

void main() {
  testWidgets('swap trades two players and leaves the rest in place', (tester) async {
    final team = _team();
    await tester.pumpWidget(MaterialApp(home: TeamEditorScreen(team: team, gameId: 'nbalive95-genesis', sport: 'basketball')));

    await tester.tap(find.byIcon(Icons.swap_vert).at(3)); // pick Dan
    await tester.pump();
    expect(find.textContaining('swap with Dan'), findsOneWidget);
    // Swap mode shows only the players: no row actions.
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await tester.tap(find.text('Ann'));
    await tester.pump();

    expect(team.players.map((p) => p.name), ['Dan', 'Ben', 'Cal', 'Ann']);
    expect(find.byIcon(Icons.delete_outline), findsWidgets); // back to normal
  });

  testWidgets('tapping the picked player again cancels without changes', (tester) async {
    final team = _team();
    await tester.pumpWidget(MaterialApp(home: TeamEditorScreen(team: team, gameId: 'nbalive95-genesis', sport: 'basketball')));

    await tester.tap(find.byIcon(Icons.swap_vert).at(1));
    await tester.pump();
    await tester.tap(find.text('Ben'));
    await tester.pump();

    expect(team.players.map((p) => p.name), ['Ann', 'Ben', 'Cal', 'Dan']);
  });
}
