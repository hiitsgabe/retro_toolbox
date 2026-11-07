import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/services/formation_cache_service.dart';

/// A saved formation keeps the order, the formation and the roles; an entry
/// saved before formations (ids only) still applies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('formations');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  RosterPlayer pl(int id, String role, String position) => RosterPlayer(raw: {'id': id, 'name': 'P$id', 'role': role, 'position': position});
  RosterTeam team(List<RosterPlayer> players, {Map<String, dynamic>? extra}) =>
      RosterTeam(teamRaw: {'id': 7, 'name': 'Club'}, players: players, statsRaw: {}, extraRaw: extra ?? {});
  List<int> ids(RosterTeam t) => [for (final p in t.players) p.id];
  List<String> roles(RosterTeam t) => [for (final p in t.players) p.role];

  test('a saved formation round-trips ids, formation and roles', () async {
    await FormationCacheService.save(7, const SavedFormation([3, 1, 2], formation: '4-3-3', roles: {3: 'GK', 1: 'RW'}, positions: {3: 'Goalkeeper'}));
    final s = (await FormationCacheService.load())[7]!;
    expect(s.positions, {3: 'Goalkeeper'});
    expect(s.playerIds, [3, 1, 2]);
    expect(s.formation, '4-3-3');
    expect(s.roles, {3: 'GK', 1: 'RW'});
  });

  test('an entry saved before formations still applies its order', () async {
    File('${tmp.path}/sports_formations.json').writeAsStringSync(jsonEncode({
      'version': 1,
      'formations': {
        '7': {
          'playerIds': [2, 1]
        }
      },
    }));
    final t = team([pl(1, 'ST', 'Attacker'), pl(2, 'CB', 'Defender')], extra: {'formation': '3-5-2'});
    (await FormationCacheService.load())[7]!.applyTo(t);
    expect(ids(t), [2, 1]);
    expect(t.extraRaw['formation'], '3-5-2');
    expect(roles(t), ['CB', 'ST']);
  });

  test('applying restores order, formation and roles; a changed role moves its group', () {
    final t = team([pl(1, 'ST', 'Attacker'), pl(2, 'CB', 'Defender'), pl(3, 'CM', 'Midfielder')]);
    const SavedFormation([2, 1], formation: '5-3-2', roles: {1: 'RW', 2: 'CB', 3: 'CDM'}).applyTo(t);
    expect(ids(t), [2, 1, 3]);
    expect(t.extraRaw['formation'], '5-3-2');
    expect([for (final p in t.players) '${p.role} ${p.position}'], ['CB Defender', 'RW Attacker', 'CDM Midfielder']);
  });

  test('applying restores a role with the position saved beside it', () {
    // Saved untouched (ESPN's Defender playing CDM); the next fetch reads him CB.
    final t = team([pl(1, 'CB', 'Defender')]);
    const SavedFormation([1], roles: {1: 'CDM'}, positions: {1: 'Defender'}).applyTo(t);
    expect('${t.players.single.role} ${t.players.single.position}', 'CDM Defender');
  });

  test('SavedFormation.of keeps what the editor shows', () {
    final t = team([pl(5, 'GK', 'Goalkeeper'), pl(-1, '', 'Defender')], extra: {'formation': '4-4-2'});
    final s = SavedFormation.of(t);
    expect(s.playerIds, [5]);
    expect(s.formation, '4-4-2');
    expect(s.roles, {5: 'GK'});
    expect(s.positions, {5: 'Goalkeeper'});
  });
}
