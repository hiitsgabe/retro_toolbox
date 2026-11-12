import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';

class HubTooNew implements Exception {
  HubTooNew(this.format);

  final int format;

  @override
  String toString() => 'This hub was made by a newer Retro Toolbox (format $format); update the app.';
}

class PayloadCorrupt implements Exception {
  PayloadCorrupt(this.gen);

  final String gen;

  @override
  String toString() => 'The hub copy of $gen is damaged (hash mismatch).';
}

/// A recipe some device published to the hub.
class HubRecipe {
  const HubRecipe({required this.source, required this.device, required this.publishedAt, required this.recipe});

  final String source;
  final String device;
  final DateTime publishedAt;
  final Map<String, dynamic> recipe;
}

/// The append-only store: every file is written once by one device, except
/// `devices/<id>.json` (one writer) and `README.txt` (derived, last writer wins).
class Hub {
  Hub(this.backend);

  final HubBackend backend;

  static const format = 1;
  static final _genFile = RegExp(r'^(\d{8}T\d{6}Z-[a-z0-9-]{1,24}-[0-9a-f]{8})\.(json|zip)$');
  static final _recipeId = RegExp(r'^[a-z0-9][a-z0-9-]{1,63}$');
  static final _deviceFile = RegExp(r'^([a-z0-9-]{1,24})\.json$');

  final _metaCache = <String, GenMeta>{};

  String _instanceId = '';

  /// The random id in hub.json; '' for a hub written before ids existed.
  String get instanceId => _instanceId;

  /// Where bases are kept: a hub recreated at the same path is another hub.
  String get key => '${backend.id}#$instanceId';

  /// A unit key that is safe as one folder name.
  static bool isUnitKey(String key) => PathGuard.isSafeRelative(key) && !key.contains('/') && !key.startsWith('.');

  Future<void> open({required String deviceId, DateTime? now}) async {
    final top = await backend.list('');
    if (top.any((e) => e.name == 'hub.json' && !e.isDir)) {
      final j = jsonDecode(utf8.decode(await backend.read('hub.json')));
      final f = j is Map<String, dynamic> ? j['format'] : null;
      if (f is! int) throw const FormatException('hub.json has no format');
      if (f > format) throw HubTooNew(f);
      final id = (j as Map<String, dynamic>)['id'];
      _instanceId = id is String ? id : '';
      return;
    }
    final r = Random.secure();
    final id = [for (var i = 0; i < 2; i++) r.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')].join();
    await backend.write(
      'hub.json',
      utf8.encode(jsonEncode({'format': format, 'id': id, 'createdBy': deviceId, 'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String()})),
    );
    _instanceId = id;
  }

  Future<List<String>> units(String recipe) async => [
        for (final e in await backend.list('units/$recipe'))
          if (e.isDir && isUnitKey(e.name)) e.name,
      ];

  Future<List<GenMeta>> gens(String recipe, String unit) async {
    final dir = 'units/$recipe/$unit';
    final out = <GenMeta>[];
    for (final e in await backend.list(dir)) {
      final m = _genFile.firstMatch(e.name);
      if (e.isDir || m == null || m[2] != 'json') continue;
      final path = '$dir/${e.name}';
      var meta = _metaCache[path];
      if (meta == null) {
        final bytes = await backend.read(path);
        try {
          meta = GenMeta.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
        } catch (_) {
          continue; // unreadable or from a newer format: not ours to use
        }
        if (meta.gen != m[1] || meta.recipe != recipe || meta.unit != unit) continue;
        _metaCache[path] = meta;
      }
      out.add(meta);
    }
    return out;
  }

  /// Zip first, then metadata: a gen exists only once both are there.
  Future<void> put(GenMeta meta, List<int> zip) async {
    final dir = 'units/${meta.recipe}/${meta.unit}';
    await backend.write('$dir/${meta.gen}.zip', zip);
    await backend.write('$dir/${meta.gen}.json', utf8.encode(jsonEncode(meta.toJson())));
    _metaCache['$dir/${meta.gen}.json'] = meta;
  }

  Future<List<int>> payload(GenMeta g) async {
    final bytes = await backend.read('units/${g.recipe}/${g.unit}/${g.gen}.zip');
    if (sha256.convert(bytes).toString() != g.payloadSha256) throw PayloadCorrupt(g.gen);
    return bytes;
  }

  /// Deletes gens beyond the heads and the newest [keep] (metadata, then
  /// zip), and zips [deviceId] wrote that were left without metadata for
  /// over a day. Another device's zip may only be waiting for its metadata
  /// to sync. Returns how many gens and orphan zips were removed.
  Future<int> prune(String recipe, String unit, {required String deviceId, int keep = pruneKeep, DateTime? now}) async {
    final dir = 'units/$recipe/$unit';
    var removed = 0;
    for (final g in pruneCandidates(await gens(recipe, unit), keep: keep)) {
      await backend.delete('$dir/${g.gen}.json');
      _metaCache.remove('$dir/${g.gen}.json');
      await backend.delete('$dir/${g.gen}.zip');
      removed++;
    }
    final entries = await backend.list(dir);
    final committed = {
      for (final e in entries)
        if (_genFile.firstMatch(e.name) case final m? when m[2] == 'json') m[1],
    };
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(const Duration(hours: 24));
    for (final e in entries) {
      final m = _genFile.firstMatch(e.name);
      if (m == null || m[2] != 'zip' || committed.contains(m[1])) continue;
      if (m[1]!.substring(17, m[1]!.length - 9) != deviceId) continue; // <stamp>-<device>-<sha8>
      final t = genTime(m[1]!);
      if (t != null && t.isBefore(cutoff)) {
        await backend.delete('$dir/${e.name}');
        removed++;
      }
    }
    return removed;
  }

  /// Publishes [recipe] unless a copy with the same content is already there. True when written.
  Future<bool> publishRecipe(Map<String, dynamic> recipe, {required String source, required String deviceId, DateTime? now}) async {
    final id = recipe['id'];
    if (id is! String || !_recipeId.hasMatch(id)) throw ArgumentError.value(id, 'recipe id');
    final sha = sha256.convert(utf8.encode(jsonEncode(recipe))).toString();
    final dir = 'recipes/$id';
    if ((await backend.list(dir)).any((e) => e.name.endsWith('-${sha.substring(0, 8)}.json'))) return false;
    final t = (now ?? DateTime.now()).toUtc();
    await backend.write(
      '$dir/${makeGenId(t, deviceId, sha)}.json',
      utf8.encode(jsonEncode({'source': source, 'device': deviceId, 'publishedAt': t.toIso8601String(), 'recipe': recipe})),
    );
    return true;
  }

  /// The newest readable published copy of each recipe id.
  Future<Map<String, HubRecipe>> recipes() async {
    final out = <String, HubRecipe>{};
    for (final d in await backend.list('recipes')) {
      if (!d.isDir || !_recipeId.hasMatch(d.name)) continue;
      final files = (await backend.list('recipes/${d.name}')).where((e) => !e.isDir && _genFile.hasMatch(e.name)).toList()
        ..sort((a, b) => b.name.compareTo(a.name));
      for (final f in files) {
        try {
          final j = jsonDecode(utf8.decode(await backend.read('recipes/${d.name}/${f.name}'))) as Map<String, dynamic>;
          final recipe = j['recipe'] as Map<String, dynamic>;
          if (recipe['id'] != d.name) continue;
          out[d.name] = HubRecipe(
            source: j['source'] as String,
            device: j['device'] as String,
            publishedAt: DateTime.parse(j['publishedAt'] as String),
            recipe: recipe,
          );
          break;
        } catch (_) {
          continue;
        }
      }
    }
    return out;
  }

  Future<void> writeDevice(String deviceId, Map<String, dynamic> report) => backend.write('devices/$deviceId.json', utf8.encode(jsonEncode(report)));

  /// Every readable device file, sorted by id.
  Future<List<Map<String, dynamic>>> devices() async {
    final out = <Map<String, dynamic>>[];
    for (final e in await backend.list('devices')) {
      if (e.isDir || !_deviceFile.hasMatch(e.name)) continue;
      try {
        final j = jsonDecode(utf8.decode(await backend.read('devices/${e.name}')));
        if (j is Map<String, dynamic>) out.add(j);
      } catch (_) {
        continue;
      }
    }
    return out..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
  }

  Future<void> writeReadme(String text) => backend.write('README.txt', utf8.encode(text));
}
