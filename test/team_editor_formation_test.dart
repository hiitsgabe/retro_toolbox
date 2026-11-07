import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/models/soccer_formation.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';

/// The soccer team editor's formation, its lines in colour, and the roles.
void main() {
  const iss = PatcherInfo(
    gameId: 'iss2000-n64',
    platform: 'n64',
    sport: 'soccer',
    requiresSlotMapping: true,
    providers: ['espn'],
    writesFormation: true,
    formations: ['4-4-2', '4-5-1', '4-3-3', '3-5-2', '3-6-1', '3-4-3', '5-3-2'],
  );
  // A library older than formations sends neither field.
  const olderLibrary = PatcherInfo(gameId: 'iss-snes', platform: 'snes', sport: 'soccer', requiresSlotMapping: true, providers: ['espn']);

  // Negative ids: no headshot URL, so nothing reaches the network.
  RosterPlayer player(String name, String position, [String role = '']) =>
      RosterPlayer(raw: {'id': -name.hashCode.abs() - 1, 'name': name, 'position': position, if (role.isNotEmpty) 'role': role});

  RosterTeam team(List<RosterPlayer> players, {Map<String, dynamic>? extra}) =>
      RosterTeam(teamRaw: {'id': 1, 'name': 'Club'}, players: players, statsRaw: {}, extraRaw: extra ?? {});

  /// A 4-4-2 club, keeper first: D1-D4, M1-M4, F1 and F2 start, S1-S4 sit.
  RosterTeam squad({Map<String, dynamic>? extra, void Function(List<RosterPlayer>)? order}) {
    final players = [
      player('Keeper', 'Goalkeeper', 'GK'),
      for (final (i, r) in ['RB', 'CB', 'CB', 'LB'].indexed) player('D${i + 1}', 'Defender', r),
      for (final (i, r) in ['RM', 'CM', 'CM', 'LM'].indexed) player('M${i + 1}', 'Midfielder', r),
      for (final i in [1, 2]) player('F$i', 'Attacker', 'ST'),
      for (final i in [1, 2, 3, 4]) player('S$i', 'Midfielder', 'CM'),
    ];
    order?.call(players);
    return team(players, extra: extra);
  }

  List<String> names(RosterTeam t) => [for (final p in t.players) p.name];

  Future<void> pump(WidgetTester t, RosterTeam tm, PatcherInfo info) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 4000); // every row built
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: TeamEditorScreen(key: UniqueKey(), team: tm, gameId: info.gameId, sport: info.sport, info: info)));
  }

  Future<void> pick(WidgetTester t, String formation) async {
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text(formation).last);
    await t.pumpAndSettle();
  }

  /// [label] (its last occurrence) sits right above the row named [below].
  void labelAbove(WidgetTester t, String label, String above, String below) {
    final y = t.getTopLeft(find.text(label).last).dy;
    expect(y, greaterThan(t.getTopLeft(find.text(above)).dy), reason: '$label after $above');
    expect(y, lessThan(t.getTopLeft(find.text(below)).dy), reason: '$label before $below');
  }

  Color? nameColor(WidgetTester t, String name) => t.widget<Text>(find.text(name)).style?.color;

  testWidgets('choosing a formation keeps the order and writes it', (t) async {
    final club = squad();
    final before = names(club);
    await pump(t, club, iss);
    expect(club.extraRaw['formation'], '4-4-2'); // the default is stored on open
    await pick(t, '4-3-3');
    expect(club.extraRaw['formation'], '4-3-3');
    expect(names(club), before);
  });

  testWidgets('opening shows and stores the nearest listed formation', (t) async {
    final club = squad(extra: {'formation': '4-2-4'});
    await pump(t, club, iss);
    expect(club.extraRaw['formation'], '4-3-3');
    expect(t.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).value, '4-3-3');
  });

  testWidgets("rows take their slot's line colour by order, with a label per line", (t) async {
    await pump(t, squad(), iss);
    expect(nameColor(t, 'Keeper'), SoccerLine.keeper.color);
    for (final n in ['D1', 'D2', 'D3', 'D4']) {
      expect(nameColor(t, n), SoccerLine.defence.color, reason: n);
    }
    for (final n in ['M1', 'M2', 'M3', 'M4']) {
      expect(nameColor(t, n), SoccerLine.midfield.color, reason: n);
    }
    for (final n in ['F1', 'F2']) {
      expect(nameColor(t, n), SoccerLine.attack.color, reason: n);
    }
    expect(nameColor(t, 'S1'), isNull);
    labelAbove(t, 'DEFENCE', 'Keeper', 'D1');
    labelAbove(t, 'MIDFIELD', 'D4', 'M1');
    labelAbove(t, 'ATTACK', 'M4', 'F1');
    labelAbove(t, 'BENCH', 'F2', 'S1');
    expect(find.text('STARTING LINEUP'), findsNothing);

    await pick(t, '4-3-3'); // the fourth midfielder now plays up front
    expect(nameColor(t, 'M4'), SoccerLine.attack.color);
    labelAbove(t, 'ATTACK', 'M3', 'M4');
  });

  testWidgets('the first goalkeeper listed plays in goal', (t) async {
    // D1 above the keeper, and a second keeper last.
    final club = squad(order: (l) => l..insert(0, l.removeAt(1))..add(player('Keeper 2', 'Goalkeeper')));
    await pump(t, club, iss);
    expect(names(club).take(2), ['Keeper', 'D1']);
    // Swap Keeper 2 (last row) with M1: one keeper starts, so he drops to the first bench place.
    await t.tap(find.byIcon(Icons.swap_vert).at(club.players.length - 1));
    await t.pump();
    await t.tap(find.text('M1'));
    await t.pump();
    expect(names(club).sublist(10, 12), ['S1', 'Keeper 2']);
  });

  testWidgets('the arrows step a starter past the bench keeper', (t) async {
    // Fetched lists put the second keeper first on the bench.
    final club = squad(order: (l) => l.insert(11, player('Keeper 2', 'Goalkeeper')));
    await pump(t, club, iss);
    await t.tap(find.byIcon(Icons.swap_vert).at(10)); // F2, the eleventh
    await t.pump();
    await t.tap(find.byTooltip('Move down'));
    await t.pump();
    expect(names(club).sublist(10, 13), ['S1', 'Keeper 2', 'F2']);
  });

  testWidgets('a squad short of eleven colours the slots it has', (t) async {
    await pump(t, team([player('Keeper', 'Goalkeeper'), player('D1', 'Defender')]), iss);
    expect(nameColor(t, 'D1'), SoccerLine.defence.color);
    expect(find.text('BENCH'), findsNothing);
  });

  testWidgets('the warning shows only when the game keeps its own formation', (t) async {
    const warning = 'This game keeps its own formation; the order and roles still apply.';
    await pump(t, squad(), iss);
    expect(find.text(warning), findsNothing);
    await pump(t, squad(), olderLibrary);
    expect(find.text(warning), findsOneWidget);
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    expect(find.text('5-4-1'), findsWidgets); // the common list
  });

  // -- The player dialog's Position --------------------------------------

  RosterPlayer byName(RosterTeam t, String name) => t.players.firstWhere((p) => p.name == name);

  Future<void> openPlayer(WidgetTester t, String name) async {
    await t.tap(find.text(name));
    await t.pumpAndSettle();
  }

  Future<void> pickRole(WidgetTester t, String role) async {
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text(role).last);
    await t.pumpAndSettle();
  }

  Future<void> save(WidgetTester t) async {
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
  }

  testWidgets('the position select writes the role and its group', (t) async {
    final club = squad();
    await pump(t, club, iss);
    await openPlayer(t, 'F1');
    await pickRole(t, 'RWB');
    await save(t);
    expect([byName(club, 'F1').role, byName(club, 'F1').position], ['RWB', 'Defender']);
    expect(find.text('RWB'), findsOneWidget); // the row shows the new role
  });

  testWidgets('saving untouched keeps role and position', (t) async {
    // A holding midfielder ESPN lists as a defender: his ratings must not move.
    final club = team([player('Keeper', 'Goalkeeper', 'GK'), player('Anchor', 'Defender', 'CDM')]);
    await pump(t, club, iss);
    await openPlayer(t, 'Anchor');
    await save(t);
    expect([byName(club, 'Anchor').role, byName(club, 'Anchor').position], ['CDM', 'Defender']);
  });

  testWidgets('a role outside the list shows and stays until a pick', (t) async {
    final club = team([player('Keeper', 'Goalkeeper', 'GK'), player('Odd', 'Midfielder', 'DM')]);
    await pump(t, club, iss);
    await openPlayer(t, 'Odd');
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('DM')), findsOneWidget);
    await save(t);
    expect(byName(club, 'Odd').role, 'DM');
  });

  testWidgets('other sports keep the free-text position', (t) async {
    const nhl = PatcherInfo(gameId: 'nhl94-snes', platform: 'snes', sport: 'hockey', requiresSlotMapping: false, providers: ['espn']);
    await pump(t, team([player('G1', 'G'), player('C1', 'C')]), nhl);
    expect(find.text('Formation'), findsNothing);
    await openPlayer(t, 'G1');
    expect(find.widgetWithText(TextField, 'Position'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });
}
