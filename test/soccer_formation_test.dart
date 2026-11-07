import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/models/soccer_formation.dart';

/// The soccer rules the team editor shares with the library (`sports/lineup.py`).
void main() {
  const iss2000 = ['4-4-2', '4-5-1', '4-3-3', '3-5-2', '3-6-1', '3-4-3', '5-3-2'];

  test('parseShape reads three lines of ten, folding longer ones', () {
    expect(parseShape('4-3-3'), (4, 3, 3));
    expect(parseShape(' 4-4-2 '), (4, 4, 2));
    expect(parseShape('4-2-3-1'), (4, 3, 3));
    expect(parseShape('3-4-2-1'), (3, 4, 3));
    expect(parseShape('4-4-1-1'), (4, 4, 2));
    expect(parseShape('4-1-4-1'), (4, 5, 1));
    for (final bad in ['4-4-3', '4-6', '', 'abc']) {
      expect(parseShape(bad), isNull, reason: bad);
    }
  });

  test('nearestShape: smallest line difference, then nearest defenders, then first listed', () {
    expect(nearestShape('4-4-2', iss2000), '4-4-2');
    expect(nearestShape('4-2-4', iss2000), '4-3-3');
    expect(nearestShape('5-4-1', iss2000), '5-3-2'); // a back five stays a back five
    expect(nearestShape('5-3-2', ['4-4-2', '4-3-3', '5-4-1']), '5-4-1');
    expect(nearestShape('4-4-2', ['4-3-3', '4-5-1']), '4-3-3');
    expect(nearestShape('4-4-2', ['4-5-1', '4-3-3']), '4-5-1');
    expect(nearestShape('junk', ['4-5-1', '4-4-2']), '4-5-1');
  });

  test('shownFormation: own, else lineup shape, else 4-4-2, as the nearest option', () {
    expect(
        shownFormation({
          'formation': '4-3-3',
          'lineup': {'shape': '3-5-2'}
        }, iss2000),
        '4-3-3');
    expect(
        shownFormation({
          'lineup': {'shape': '3-5-2'}
        }, iss2000),
        '3-5-2');
    expect(
        shownFormation({
          'formation': 'junk',
          'lineup': {'shape': '3-5-2'}
        }, iss2000),
        '3-5-2');
    expect(shownFormation({}, iss2000), '4-4-2');
    expect(shownFormation({'formation': '4-2-4'}, iss2000), '4-3-3');
    expect(shownFormation({}, ['4-5-1', '4-3-3']), '4-5-1');
  });

  test('slotLines: the keeper, the formation lines by order, then the bench', () {
    const k = SoccerLine.keeper, d = SoccerLine.defence, m = SoccerLine.midfield, f = SoccerLine.attack, b = SoccerLine.bench;
    expect(slotLines('4-3-3', 13), [k, d, d, d, d, m, m, m, f, f, f, b, b]);
    expect(slotLines('5-4-1', 3), [k, d, d]);
  });

  test('teamSheet: the first keeper listed, the first ten others who are not keepers, then the rest', () {
    RosterPlayer p(String n, String pos) => RosterPlayer(raw: {'id': n.hashCode, 'name': n, 'position': pos});
    final list = [
      p('D1', 'Defender'),
      p('K1', 'Goalkeeper'),
      for (var i = 1; i <= 9; i++) p('M$i', 'Midfielder'),
      p('K2', 'Goalkeeper'),
      p('S1', 'Attacker'),
    ];
    // K2 sits 12th; move him to 4th: one keeper starts, so he still sits out.
    list.insert(3, list.removeAt(11));
    expect([for (final x in teamSheet(list)) x.name], ['K1', 'D1', 'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'K2', 'S1']);
    final noKeeper = [p('A', 'Defender'), p('B', 'Attacker')];
    expect(teamSheet(noKeeper), noKeeper);
  });

  test('roleGroup and setRole: a new role sets its group, the same role changes nothing', () {
    expect([for (final r in soccerRoles) roleGroup(r)], [
      'Goalkeeper',
      for (var i = 0; i < 5; i++) 'Defender',
      for (var i = 0; i < 5; i++) 'Midfielder',
      for (var i = 0; i < 3; i++) 'Attacker',
    ]);
    final p = RosterPlayer(raw: {'id': 1, 'role': 'CDM', 'position': 'Defender'});
    setRole(p, 'CDM');
    expect(p.position, 'Defender'); // the provider's group stays: ratings do not move
    setRole(p, 'CAM');
    expect([p.role, p.position], ['CAM', 'Midfielder']);
    expect(RosterPlayer(raw: {'id': 2}).role, '');
  });
}
