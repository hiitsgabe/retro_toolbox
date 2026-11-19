import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'package:retro_toolbox/services/jksv_source.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';

/// Serves one Save Sync recipe (Eden, Yuzu: a folder unit per title id) to
/// JKSV, and files what JKSV uploads as a new gen the emulator pulls next time.
class HubJksvSource implements JksvSource {
  HubJksvSource({
    required this.hub,
    required this.recipe,
    required this.deviceId,
    required this.deviceName,
    this.nameFor,
    DateTime Function()? clock,
    this.cacheFor = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

  final Hub hub;
  final String recipe;
  final String deviceId;
  final String deviceName;
  final String Function(String titleId)? nameFor;
  final DateTime Function() _clock;

  /// JKSV lists, then fetches each title right after: one hub read serves both.
  final Duration cacheFor;

  static final _titleIdRe = RegExp(r'^01[0-9A-F]{14}$', caseSensitive: false);

  /// Upper-case title id to the unit key as the hub spells it.
  ({DateTime at, Map<String, String> keys})? _units;
  final _zips = <String, ({DateTime at, List<int> zip})>{};

  bool _fresh(DateTime at) => _clock().difference(at) < cacheFor;

  Future<Map<String, String>> _unitKeys() async {
    final cached = _units;
    if (cached != null && _fresh(cached.at)) return cached.keys;
    final keys = {
      for (final u in await hub.units(recipe))
        if (_titleIdRe.hasMatch(u)) u.toUpperCase(): u,
    };
    _units = (at: _clock(), keys: keys);
    return keys;
  }

  @override
  Future<List<String>> titleIds() async => (await _unitKeys()).keys.toList()..sort();

  @override
  String displayName(String titleId) => jksvSafeName(nameFor?.call(titleId) ?? titleId);

  @override
  Future<List<int>> backupZip(String titleId) async {
    final id = titleId.toUpperCase();
    final cached = _zips[id];
    if (cached != null && _fresh(cached.at)) return cached.zip;
    final unit = (await _unitKeys())[id] ?? id;
    final heads = headsOf(await hub.gens(recipe, unit));
    if (heads.isEmpty) throw StateError('No save for $id in the hub');
    final zip = exportToJksv(id, await hub.payload(heads.first));
    _zips[id] = (at: _clock(), zip: zip);
    return zip;
  }

  /// A new gen over every current head, so it wins without a conflict. The
  /// hub keeps the older gens, so [timestamp] names nothing here.
  @override
  Future<void> applyIncoming(String titleId, List<int> jksvZip, {required String timestamp}) async {
    final id = titleId.toUpperCase();
    final unit = (await _unitKeys())[id] ?? id;
    final files = jksvToExportFiles(unit, jksvZip);
    final paths = files.keys.toList()..sort();
    final archive = Archive();
    for (final path in paths) {
      archive.addFile(ArchiveFile.bytes(path, files[path]!));
    }
    final zip = ZipEncoder().encodeBytes(archive);
    final payloadSha = sha256.convert(zip).toString();
    final heads = headsOf(await hub.gens(recipe, unit));
    final now = _clock().toUtc();
    await hub.put(
      GenMeta(
        gen: makeGenId(now, deviceId, payloadSha),
        parents: [for (final g in heads) g.gen],
        kind: 'save',
        recipe: recipe,
        unit: unit,
        device: deviceId,
        deviceName: deviceName,
        createdAt: now,
        package: 'jksv',
        packageVersion: null,
        gameVersion: null,
        files: {for (final path in paths) path: GenFile(sha256.convert(files[path]!).toString(), files[path]!.length)},
        payloadSha256: payloadSha,
      ),
      zip,
    );
    // A title new to the hub must show up in the listing too.
    _zips.remove(id);
    _units = null;
  }
}
