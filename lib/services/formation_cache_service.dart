import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/models/soccer_formation.dart';

/// What the editor saved for one team: the player order (ESPN athlete ids)
/// and, for soccer, the formation and each player's role and position.
class SavedFormation {
  final List<int> playerIds;
  final String? formation;
  final Map<int, String> roles;

  /// The position each role was saved with: restored with it, so a fetched
  /// player keeps the group his ratings came from.
  final Map<int, String> positions;
  const SavedFormation(this.playerIds, {this.formation, this.roles = const {}, this.positions = const {}});

  /// The team as the editor shows it: its players with an ESPN id, its
  /// formation and the roles they have.
  factory SavedFormation.of(RosterTeam team) {
    final formation = team.extraRaw['formation'];
    return SavedFormation(
      [for (final p in team.players) if (p.id > 0) p.id],
      formation: formation is String ? formation : null,
      roles: {for (final p in team.players) if (p.id > 0 && p.role.isNotEmpty) p.id: p.role},
      positions: {for (final p in team.players) if (p.id > 0 && p.role.isNotEmpty) p.id: p.position},
    );
  }

  /// An entry saved before formations holds only `playerIds`.
  factory SavedFormation.fromJson(Map j) {
    final formation = j['formation'];
    Map<int, String> byId(Object? m) => {
          for (final e in ((m as Map?) ?? const {}).entries)
            if (int.tryParse('${e.key}') != null && e.value is String) int.parse('${e.key}'): e.value as String,
        };
    return SavedFormation(
      [for (final x in j['playerIds'] as List) (x as num).toInt()],
      formation: formation is String ? formation : null,
      roles: byId(j['roles']),
      positions: byId(j['positions']),
    );
  }

  /// Ids alone are written as before, so an older app reads the file too.
  Map<String, dynamic> toJson() => {
        'playerIds': playerIds,
        if (formation != null) 'formation': formation,
        if (roles.isNotEmpty) 'roles': {for (final e in roles.entries) '${e.key}': e.value},
        if (positions.isNotEmpty) 'positions': {for (final e in positions.entries) '${e.key}': e.value},
      };

  /// Puts the saved players first, in order, then the rest as they were;
  /// restores the formation and each listed role with the position saved
  /// beside it (without one, a new role moves the position to its group, as
  /// an edit does).
  void applyTo(RosterTeam team) {
    final byId = {for (final p in team.players) p.id: p};
    // A set keeps each player's first place and drops repeats.
    final ordered = {
      for (final id in playerIds)
        if (byId[id] case final p?) p,
      ...team.players,
    }.toList();
    team.players
      ..clear()
      ..addAll(ordered);
    if (formation != null) team.extraRaw['formation'] = formation;
    for (final p in team.players) {
      final role = roles[p.id];
      if (role == null || !soccerRoles.contains(role)) continue;
      setRole(p, role);
      if (positions[p.id] case final position?) p.position = position;
    }
  }
}

/// Persists "saved formations" for sports teams, keyed by the team's ESPN id.
/// Applied automatically to a freshly fetched roster of the same club in any
/// game of the same sport when the `autoApplyFormations` setting is on.
class FormationCacheService {
  static const _file = 'sports_formations.json';

  static Future<File> _fileHandle() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _file));
  }

  static Future<Map<int, SavedFormation>> load() async {
    try {
      final f = await _fileHandle();
      if (!await f.exists()) return {};
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return {};
      final out = <int, SavedFormation>{};
      for (final e in (decoded['formations'] as Map? ?? {}).entries) {
        final id = int.tryParse('${e.key}');
        if (id == null) continue;
        if (e.value is Map && (e.value as Map)['playerIds'] is List) {
          out[id] = SavedFormation.fromJson(e.value as Map);
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(int teamId, SavedFormation saved) async {
    final current = await load();
    current[teamId] = saved;
    await _write(current);
  }

  static Future<void> remove(int teamId) async {
    final current = await load();
    current.remove(teamId);
    await _write(current);
  }

  static Future<void> _write(Map<int, SavedFormation> all) async {
    final f = await _fileHandle();
    await f.writeAsString(jsonEncode({
      'version': 1,
      'formations': {for (final e in all.entries) '${e.key}': e.value.toJson()},
    }));
  }

  static Future<void> clearAll() async {
    try {
      final f = await _fileHandle();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    try {
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'rrp_cache'));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
