// The soccer rules the team editor shares with the library (`sports/lineup.py`
// and the soccer patchers): roles and their groups, reading a formation, the
// nearest one a game has, the line each starting slot plays, and the order the
// games field a list in.

import 'dart:ui' show Color;

import 'package:retro_toolbox/models/roster_doc.dart';

/// The roles a soccer player's `role` holds (the library's `ROLES`).
const soccerRoles = ['GK', 'RB', 'CB', 'LB', 'RWB', 'LWB', 'CDM', 'CM', 'CAM', 'RM', 'LM', 'RW', 'LW', 'ST'];

const _groups = {
  'GK': 'Goalkeeper',
  'RB': 'Defender', 'CB': 'Defender', 'LB': 'Defender', 'RWB': 'Defender', 'LWB': 'Defender',
  'CDM': 'Midfielder', 'CM': 'Midfielder', 'CAM': 'Midfielder', 'RM': 'Midfielder', 'LM': 'Midfielder',
  'RW': 'Attacker', 'LW': 'Attacker', 'ST': 'Attacker',
};

/// The squad group (the player's `position`) a role plays in.
String roleGroup(String role) => _groups[role]!;

/// The formations to offer when the game lists none (an older library).
const commonFormations = ['4-4-2', '4-3-3', '4-5-1', '3-5-2', '3-4-3', '3-6-1', '5-3-2', '5-4-1'];

/// The players per line of "4-2-3-1": three lines or more of ten outfield
/// players, else empty.
List<int> _counts(String text) {
  if (!RegExp(r'^\d+(-\d+){2,}$').hasMatch(text)) return const [];
  final counts = [for (final n in text.split('-')) int.parse(n)];
  return counts.fold(0, (a, b) => a + b) == 10 ? counts : const [];
}

/// [text] cut to three lines, as the library folds it: everything between the
/// back and front lines is midfield, except that a lone striker is joined by
/// the line behind him when it has one or two players, by its two wide ones
/// when it has three.
String _fold(String text) {
  final counts = _counts(text);
  if (counts.length < 4) return text;
  final middle = counts.sublist(1, counts.length - 1);
  var front = counts.last;
  if (front == 1) {
    final behind = middle.last;
    if (behind <= 2) {
      front += behind;
      middle.removeLast();
    } else if (behind == 3) {
      front += 2;
      middle.last = 1;
    }
  }
  return '${counts.first}-${middle.fold(0, (a, b) => a + b)}-$front';
}

/// (defenders, midfielders, forwards) of [text], four lines or more folded to
/// three; null when it is not ten outfield players in three lines or more.
(int, int, int)? parseShape(String text) {
  final c = _counts(_fold(text.trim()));
  return c.length == 3 ? (c[0], c[1], c[2]) : null;
}

/// The shape of [offered] nearest [shape]: the smallest sum of differences in
/// players per line, then the nearest number of defenders, then the first
/// listed. [offered]'s first when [shape] does not read.
String nearestShape(String shape, List<String> offered) {
  final want = parseShape(shape);
  if (want == null) return offered.first;
  // The line difference, then the defender difference (at most 10), as one number.
  int distance(String candidate) {
    final have = parseShape(candidate);
    if (have == null) return 1 << 20;
    final back = (want.$1 - have.$1).abs();
    return (back + (want.$2 - have.$2).abs() + (want.$3 - have.$3).abs()) * 100 + back;
  }

  // reduce keeps the earlier one on a tie: the first listed wins.
  return offered.reduce((best, c) => distance(c) < distance(best) ? c : best);
}

/// The formation the editor shows for a team's `extra`: its own, else its
/// lineup's shape, else 4-4-2 (each only when it reads), as the nearest of
/// [options].
String shownFormation(Map<String, dynamic> extra, List<String> options) {
  final lineup = extra['lineup'];
  final texts = [extra['formation'], if (lineup is Map) lineup['shape']].map((t) => '${t ?? ''}');
  return nearestShape(texts.firstWhere((t) => parseShape(t) != null, orElse: () => '4-4-2'), options);
}

/// The line a slot of the list plays, with the colour and the name the editor
/// gives it.
enum SoccerLine {
  keeper('Goalkeeper', Color(0xFFFFB300)),
  defence('Defence', Color(0xFF66BB6A)),
  midfield('Midfield', Color(0xFF42A5F5)),
  attack('Attack', Color(0xFFEF5350)),
  bench('Bench', Color(0xFF9E9E9E));

  const SoccerLine(this.label, this.color);
  final String label;
  final Color color;
}

/// The line of each of the first [count] slots under [formation], a shape
/// [parseShape] reads: the keeper, then its lines in order, then the bench.
List<SoccerLine> slotLines(String formation, int count) {
  final (d, m, f) = parseShape(formation)!;
  final eleven = [
    SoccerLine.keeper,
    for (var i = 0; i < d; i++) SoccerLine.defence,
    for (var i = 0; i < m; i++) SoccerLine.midfield,
    for (var i = 0; i < f; i++) SoccerLine.attack,
  ];
  return [for (var i = 0; i < count; i++) i < eleven.length ? eleven[i] : SoccerLine.bench];
}

/// [players] in the order every soccer game fields them: the first goalkeeper
/// listed in goal, then the first ten who are not goalkeepers, then everyone
/// else (a second keeper among them), each in the order given. A list with no
/// goalkeeper is fielded as given.
List<RosterPlayer> teamSheet(List<RosterPlayer> players) {
  bool keeper(RosterPlayer p) => p.position == 'Goalkeeper';
  final goal = players.where(keeper).take(1);
  if (goal.isEmpty) return players;
  final eleven = [...goal, ...players.where((p) => !keeper(p)).take(10)];
  return {...eleven, ...players}.toList();
}

/// Gives [p] a new [role] and his position its group, as an edit does; the
/// role he already has changes nothing, so a fetched player keeps the
/// provider's group and his ratings do not move.
void setRole(RosterPlayer p, String role) {
  if (role == p.role) return;
  p.role = role;
  p.position = roleGroup(role);
}
