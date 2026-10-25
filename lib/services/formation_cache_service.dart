import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists "saved formations" for sports teams: the ordered list of player ids
/// (ESPN athlete ids) the user set in the team editor, keyed by the team's
/// ESPN id. Applied automatically to a freshly fetched roster of the same club
/// in any game of the same sport when the `autoApplyFormations` setting is on.
class FormationCacheService {
  static const _file = 'sports_formations.json';

  static Future<File> _fileHandle() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _file));
  }

  static Future<Map<int, List<int>>> load() async {
    try {
      final f = await _fileHandle();
      if (!await f.exists()) return {};
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map) return {};
      final out = <int, List<int>>{};
      for (final e in (decoded['formations'] as Map? ?? {}).entries) {
        final id = int.tryParse('${e.key}');
        if (id == null) continue;
        final ids = (e.value is Map ? (e.value as Map)['playerIds'] : null);
        if (ids is List) {
          out[id] = [for (final x in ids) (x as num).toInt()];
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(int teamId, List<int> playerIds) async {
    final current = await load();
    current[teamId] = playerIds;
    final f = await _fileHandle();
    await f.writeAsString(jsonEncode({
      'version': 1,
      'formations': {
        for (final e in current.entries) '${e.key}': {'playerIds': e.value},
      },
    }));
  }

  static Future<void> remove(int teamId) async {
    final current = await load();
    current.remove(teamId);
    final f = await _fileHandle();
    await f.writeAsString(jsonEncode({
      'version': 1,
      'formations': {
        for (final e in current.entries) '${e.key}': {'playerIds': e.value},
      },
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