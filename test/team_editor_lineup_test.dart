import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';
import 'package:retro_toolbox/widgets/menu_grid/sport_slug.dart';

// Negative ids: no headshot URL, so nothing reaches the network.
RosterPlayer _p(String name, String position) => RosterPlayer(raw: {'id': -name.hashCode.abs() - 1, 'name': name, 'position': position});

RosterTeam _team(List<RosterPlayer> players, [Map<String, dynamic>? extra]) =>
    RosterTeam(teamRaw: {'id': 1, 'name': 'Team'}, players: players, statsRaw: {}, extraRaw: extra ?? {});

List<String> _names(RosterTeam t) => [for (final p in t.players) p.name];

void main() {
  test('hockey starts six; WE2002 stores 23', () {
    for (final g in ['nhl94-genesis', 'nhl94-snes', 'nhl05-ps2', 'nhl07-psp']) {
      expect(gameRoster(g).starters, 6, reason: g);
    }
    expect(gameRoster('we2002').rosterSize, 23);
  });

  group('lineupWarnings', () {
    final xi = ['Goalkeeper', for (var i = 0; i < 10; i++) 'Defender'];

    test('a short list leaves the game\'s old players in the lineup', () {
      expect(lineupWarnings('nbalive95-genesis', ['F', 'F', 'F'], 5).single, contains('Only 3 players'));
      expect(lineupWarnings('nbalive95-genesis', ['F', 'F', 'F', 'F', 'F'], 5), isEmpty);
    });

    test('a short WE2002 list is filled with blank PLAYER records', () {
      final w = lineupWarnings('we2002', ['Goalkeeper', 'Defender'], 11).single;
      expect(w, contains("'PLAYER' records"));
      expect(w, isNot(contains('old players')));
    });

    test('baseball counts only position players against the lineup', () {
      final squad = [for (var i = 0; i < 7; i++) 'SS', for (var i = 0; i < 13; i++) 'SP'];
      expect(lineupWarnings('kgj-mlb-snes', squad, 9).single, contains('Only 7 position players: pitchers past the first 10'));
      expect(lineupWarnings('mvp-psp', squad, 9).single, 'Only 7 position players: the batting order is 2 short.');
      // A short list says it once, by position players.
      expect(lineupWarnings('mvp-psp', ['SS', 'SS'], 9).single, contains('Only 2 position players'));
      final nine = [for (var i = 0; i < 9; i++) 'SS', 'SP'];
      expect(lineupWarnings('kgj-mlb-snes', nine, 9), isEmpty);
      expect(lineupWarnings('mvp-psp', nine, 9), isEmpty);
    });

    test('ISS and WE2002 put the first player in goal', () {
      for (final g in ['iss-snes', 'we2002']) {
        expect(lineupWarnings(g, xi, 11), isEmpty, reason: g);
        expect(lineupWarnings(g, xi.reversed.toList(), 11).single, contains('in goal'), reason: g);
      }
    });

    test('PES needs exactly one keeper in the first 11', () {
      expect(lineupWarnings('pes2013-ps2', [...xi, 'Goalkeeper'], 11), isEmpty);
      expect(lineupWarnings('pes2013-ps2', ['Goalkeeper', ...xi.skip(2), 'Goalkeeper'], 11).single, contains('one goalkeeper'));
      expect(lineupWarnings('pes2013-ps2', [...xi.skip(1), 'Midfielder', 'Goalkeeper'], 11).single, contains('one goalkeeper'));
    });

    test('NHL 05 and 07 start a G, C, LW, RW and two D', () {
      for (final g in ['nhl05-ps2', 'nhl07-psp']) {
        expect(lineupWarnings(g, ['D', 'RW', 'G', 'LW', 'D', 'C', 'C'], 6), isEmpty, reason: g);
        expect(lineupWarnings(g, ['G', 'C', 'C', 'RW', 'D', 'D', 'LW'], 6).single, contains('C, LW, RW'), reason: g);
      }
    });

    test('NHL 94 starts a G, three forwards and two D', () {
      expect(lineupWarnings('nhl94-snes', ['G', 'C', 'C', 'LW', 'D', 'D', 'G'], 6), isEmpty);
      expect(lineupWarnings('nhl94-snes', ['G', 'G', 'C', 'LW', 'D', 'D'], 6).single, contains('three forwards'));
    });

    test('NHL 94 needs two goalies: Genesis stops, SNES keeps the cartridge team', () {
      const one = ['G', 'C', 'C', 'LW', 'D', 'D', 'RW'];
      expect(lineupWarnings('nhl94-genesis', one, 6).single, 'NHL 94 needs two goalies: add one, or the patch stops.');
      expect(lineupWarnings('nhl94-snes', one, 6).single, "NHL 94 needs two goalies: add one, or the slot keeps the cartridge's team.");
      for (final g in ['nhl94-genesis', 'nhl94-snes']) {
        expect(lineupWarnings(g, ['G', 'C', 'C', 'LW', 'D', 'D', 'G'], 6), isEmpty, reason: g);
      }
    });
  });

  test('splitPitchers: 15 position players, 10 pitchers, then the rest', () {
    final players = [
      _p('P1', 'SP'),
      for (var i = 1; i <= 17; i++) _p('B$i', 'SS'),
      for (var i = 2; i <= 11; i++) _p('P$i', 'RP'),
    ];
    expect([for (final p in splitPitchers(players)) p.name], [
      for (var i = 1; i <= 15; i++) 'B$i',
      for (var i = 1; i <= 10; i++) 'P$i',
      'B16',
      'B17',
      'P11',
    ]);
  });

  Future<void> pump(WidgetTester t, RosterTeam team, String gameId, String sport) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 4000); // every row built
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: TeamEditorScreen(team: team, gameId: gameId, sport: sport)));
  }

  /// [label] (its last occurrence) sits right above the row named [below].
  void labelAbove(WidgetTester t, String label, String above, String below) {
    final y = t.getTopLeft(find.text(label).last).dy;
    expect(y, greaterThan(t.getTopLeft(find.text(above)).dy), reason: '$label after $above');
    expect(y, lessThan(t.getTopLeft(find.text(below)).dy), reason: '$label before $below');
  }

  testWidgets('baseball shows what the game writes, and an NL club bats 8', (t) async {
    // 17 position players and 8 pitchers: the two batters past 15 top up the
    // short pitching block, so all 25 are stored.
    final team = _team([
      for (var i = 1; i <= 17; i++) _p('B$i', 'SS'),
      for (var i = 1; i <= 8; i++) _p('P$i', 'SP'),
    ], {'lineup_size': 8});
    await pump(t, team, 'kgj-mlb-snes', 'baseball');

    final order = [for (var i = 1; i <= 15; i++) 'B$i', for (var i = 1; i <= 8; i++) 'P$i', 'B16', 'B17'];
    expect(_names(team), order);
    expect(find.textContaining('first 8 start'), findsOneWidget);
    labelAbove(t, 'BENCH', 'B8', 'B9');
    labelAbove(t, 'ROTATION', 'B15', 'P1');
    labelAbove(t, 'BULLPEN', 'P5', 'P6');
    expect(find.text('EXTRA (NOT STORED BY THIS GAME)'), findsNothing);

    // A pitcher swapped into the lineup goes back to the pitchers; the batter
    // he traded with ends the position players.
    await t.tap(find.byIcon(Icons.swap_vert).at(15)); // P1
    await t.pump();
    await t.tap(find.text('B1'));
    await t.pump();
    expect(_names(team), [for (var i = 2; i <= 15; i++) 'B$i', 'B1', for (var i = 1; i <= 8; i++) 'P$i', 'B16', 'B17']);

    // Dragging a pitcher to the top makes him the first starter instead.
    // ignore: deprecated_member_use
    t.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorder!(17, 0); // P3
    await t.pump();
    expect(_names(team).sublist(15, 18), ['P3', 'P1', 'P2']);
  });

  testWidgets('baseball names the section its leftovers go to', (t) async {
    // KGJ, 13 batters and 13 pitchers: P11 and P12 bat on the bench.
    final kgj = _team([for (var i = 1; i <= 13; i++) _p('B$i', 'SS'), for (var i = 1; i <= 13; i++) _p('P$i', 'SP')]);
    await pump(t, kgj, 'kgj-mlb-snes', 'baseball');
    labelAbove(t, 'BENCH (BATS)', 'P10', 'P11');
  });

  testWidgets('MVP benches its spare batters and notes the NL lineup', (t) async {
    // 17 batters and 8 pitchers: B16 and B17 sit on the bench.
    final mvp = _team([for (var i = 1; i <= 17; i++) _p('B$i', 'SS'), for (var i = 1; i <= 8; i++) _p('P$i', 'SP')]);
    await pump(t, mvp, 'mvp-psp', 'baseball');
    labelAbove(t, 'BENCH', 'P8', 'B16');
    expect(find.textContaining('At NL parks the DH sits'), findsOneWidget);
  });

  testWidgets('baseball without pitchers draws no rotation', (t) async {
    final team = _team([for (var i = 1; i <= 16; i++) _p('B$i', 'SS')]);
    await pump(t, team, 'mvp-psp', 'baseball');
    expect(find.text('ROTATION'), findsNothing);
  });

  testWidgets('NHL 94 marks the rows it stores by position', (t) async {
    // A third goalie in the middle is not stored; the defencemen after him are.
    final team = _team([
      _p('G1', 'G'),
      _p('G2', 'G'),
      for (var i = 1; i <= 3; i++) _p('F$i', 'C'),
      _p('G3', 'G'),
      for (var i = 1; i <= 2; i++) _p('D$i', 'D'),
    ]);
    await pump(t, team, 'nhl94-snes', 'hockey');
    // Each left-out row says so itself: no heading with stored rows under it.
    expect(find.text('EXTRA (NOT STORED BY THIS GAME)'), findsNothing);
    expect(find.textContaining('not stored'), findsOneWidget);
    expect(find.text('G · not stored'), findsOneWidget);
    final dimmed = t.widget<Opacity>(find.ancestor(of: find.text('G3'), matching: find.byType(Opacity)).first);
    expect(dimmed.opacity, 0.5);
    final kept = t.widget<Opacity>(find.ancestor(of: find.text('D2'), matching: find.byType(Opacity)).first);
    expect(kept.opacity, 1);
  });

  testWidgets('baseball stores 25: the 26th is the first extra', (t) async {
    final team = _team([
      for (var i = 1; i <= 17; i++) _p('B$i', 'SS'),
      for (var i = 1; i <= 9; i++) _p('P$i', 'SP'),
    ]);
    await pump(t, team, 'mvp-psp', 'baseball');
    expect(_names(team)[25], 'B17');
    labelAbove(t, 'EXTRA (NOT STORED BY THIS GAME)', 'B16', 'B17');
  });

  testWidgets('removing a player regroups the list', (t) async {
    final team = _team([
      for (var i = 1; i <= 16; i++) _p('B$i', 'SS'),
      for (var i = 1; i <= 10; i++) _p('P$i', 'SP'),
    ]);
    await pump(t, team, 'kgj-mlb-snes', 'baseball');
    await t.tap(find.byIcon(Icons.delete_outline).at(2)); // B3
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();

    expect(_names(team), [for (var i = 1; i <= 16; i++) if (i != 3) 'B$i', for (var i = 1; i <= 10; i++) 'P$i']);
    labelAbove(t, 'ROTATION', 'B16', 'P1');
  });

  testWidgets('ISS warns while the keeper is not first', (t) async {
    final team = _team([_p('Def', 'Defender'), _p('Keeper', 'Goalkeeper'), for (var i = 0; i < 9; i++) _p('M$i', 'Midfielder')]);
    await pump(t, team, 'iss-snes', 'soccer');
    expect(find.textContaining('in goal'), findsOneWidget);

    await t.tap(find.byIcon(Icons.swap_vert).at(1));
    await t.pump();
    await t.tap(find.text('Def'));
    await t.pump();
    expect(_names(team).first, 'Keeper');
    expect(find.textContaining('in goal'), findsNothing);
  });

  testWidgets('a WE2002 Master League slot marks the rows only its national team keeps', (t) async {
    expect([for (final s in [0, 17, 18, 31, 32, null]) masterLeagueSize('we2002', s)], [14, 14, 15, 15, null, null]);
    expect(masterLeagueSize('iss-snes', 0), isNull);
    final team = _team([_p('Keeper', 'Goalkeeper'), for (var i = 1; i < 23; i++) _p('M$i', 'Midfielder')]);
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 4000);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: TeamEditorScreen(team: team, gameId: 'we2002', sport: 'soccer', slot: 5)));
    expect(find.textContaining('ROM uses 23, Master League 14'), findsOneWidget);
    labelAbove(t, 'NATIONAL TEAM ONLY (NOT IN THE MASTER LEAGUE)', 'M13', 'M14');
    expect(find.text('EXTRA (NOT STORED BY THIS GAME)'), findsNothing);
  });

  test('nhl94StoredRows keeps 2 goalies, 14 forwards and 7 defencemen in list order', () {
    final positions = ['G', 'G', 'G', for (var i = 0; i < 15; i++) 'LW', for (var i = 0; i < 8; i++) 'D'];
    final kept = nhl94StoredRows(positions);
    expect(kept.length, 23);
    expect(kept.contains(2), isFalse); // the third goalie
    expect(kept.contains(17), isFalse); // the 15th forward
    expect(kept.contains(25), isFalse); // the 8th defenceman
  });

  test("nhl94StoredRows takes the slot's own counts", () {
    final positions = ['G', 'G', for (var i = 0; i < 12; i++) 'C', for (var i = 0; i < 8; i++) 'D'];
    final kept = nhl94StoredRows(positions, [2, 9, 7]);
    expect(kept.length, 18);
    expect(kept.contains(10), isTrue); // the 9th forward
    expect(kept.contains(11), isFalse); // the 10th
    expect(kept.contains(21), isFalse); // the 8th defenceman
  });

  testWidgets("NHL 94 marks the extras from the slot's counts", (t) async {
    final team = _team([_p('G1', 'G'), _p('G2', 'G'), for (var i = 1; i <= 10; i++) _p('F$i', 'C'), for (var i = 1; i <= 7; i++) _p('D$i', 'D')]);
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 3000);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: TeamEditorScreen(team: team, gameId: 'nhl94-snes', sport: 'hockey', slot: 3, rosterCounts: const [2, 9, 7])));
    expect(find.textContaining('ROM uses 2 G, 9 F, 7 D'), findsOneWidget);
    // F10 is left out; the seven D after him are all stored, under no Extra heading.
    expect(find.text('EXTRA (NOT STORED BY THIS GAME)'), findsNothing);
    expect(find.textContaining('not stored'), findsOneWidget);
    expect(find.text('C · not stored'), findsOneWidget);
    expect(find.textContaining('counts are not known'), findsNothing);
    // Without the slot's counts it says it is guessing.
    await t.pumpWidget(MaterialApp(home: TeamEditorScreen(team: team, gameId: 'nhl94-snes', sport: 'hockey', slot: 3)));
    expect(find.textContaining("This slot's own counts are not known"), findsOneWidget);
  });

  testWidgets('KGJ names its lineup the batting order', (t) async {
    await pump(t, _team([for (var i = 1; i <= 9; i++) _p('B$i', 'SS'), _p('P1', 'SP')]), 'kgj-mlb-snes', 'baseball');
    expect(find.text('BATTING ORDER'), findsOneWidget);
    expect(find.textContaining('bats in this order'), findsOneWidget);
    await pump(t, _team([_p('G1', 'G'), _p('G2', 'G')]), 'nhl94-snes', 'hockey');
    expect(find.text('STARTING LINEUP'), findsOneWidget);
  });

  test('NHL 94 Genesis drops the six-starters claim until a cartridge confirms it', () {
    final wrong = ['G', 'G', 'C', 'LW', 'RW', 'D', 'D'];
    expect(lineupWarnings('nhl94-snes', wrong, 6), hasLength(1));
    expect(lineupWarnings('nhl94-genesis', wrong, 6), isEmpty);
    expect(lineupNotes('nhl94-genesis').single, contains('Genesis cartridge'));
    expect(lineupWarnings('nhl94-genesis', ['G', 'C', 'C', 'C', 'D', 'D'], 6).single, contains('two goalies'));
  });
}
