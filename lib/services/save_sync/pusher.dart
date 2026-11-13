import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/errors.dart';
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/glob.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/save_checks.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

/// Uploads one unit as a new gen. Nothing on the device changes.
class Pusher {
  Pusher({
    required this.fs,
    required this.hub,
    required this.stagingRoot,
    required this.deviceId,
    required this.deviceName,
    DateTime Function()? clock,
    Random? random,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final GameFs fs;
  final Hub hub;
  final String stagingRoot;
  final String deviceId;
  final String deviceName;
  final DateTime Function() _clock;
  final Random _random;

  /// Packs the unit and writes it to the hub as a generation.
  Future<GenMeta> push({
    required Recipe recipe,
    required Binding binding,
    required String locationDir,
    required LocalUnit unit,
    required List<GenMeta> parents,
    String kind = 'save',
  }) async {
    final (meta, zip) = await pack(
      recipe: recipe,
      binding: binding,
      locationDir: locationDir,
      unit: unit,
      parents: parents,
      kind: kind,
    );
    await hub.put(meta, zip);
    return meta;
  }

  /// Reads the unit, verifies every file against what was scanned, runs the
  /// recipe's checks and returns the archive with its description. Separate
  /// from writing it, because a backup is packed exactly like a generation
  /// and then filed somewhere a generation must never go.
  Future<(GenMeta, List<int>)> pack({
    required Recipe recipe,
    required Binding binding,
    required String locationDir,
    required LocalUnit unit,
    List<GenMeta> parents = const [],
    String kind = 'save',
  }) async {
    if (unit.busy) throw SyncBlocked('${unit.key}: a save is in progress; open and close the game, then try again');
    if (await fs.running(binding.package)) throw SyncBlocked('${recipe.name} is running; close it first');
    if (recipe.unit == UnitKind.folder && parents.isNotEmpty) {
      // A file every parent had and the unit lacks: an interrupted write or pull, not a deletion to spread.
      final common = parents.skip(1).fold(parents.first.files.keys.toSet(), (Set<String> a, x) => a.intersection(x.files.keys.toSet()));
      final missing = common.where((rel) => !unit.files.containsKey(rel)).toList()..sort();
      if (missing.isNotEmpty) throw SyncBlocked('${unit.key}: ${missing.join(', ')} is missing here but every earlier version has it');
    }
    final stage = Directory(p.join(stagingRoot, 'push-${_random.nextInt(1 << 32).toRadixString(16)}'));
    await stage.create(recursive: true);
    try {
      final rels = unit.files.keys.toList()..sort();
      final staged = <String, List<int>>{};
      final archive = Archive();
      for (final rel in rels) {
        final dst = p.join(stage.path, rel);
        await Directory(p.dirname(dst)).create(recursive: true);
        await fs.copyOut(p.posix.join(locationDir, rel), dst);
        final bytes = await File(dst).readAsBytes();
        if (sha256.convert(bytes).toString() != unit.files[rel]!.sha256) throw SyncBlocked('${unit.key}: $rel changed while reading; try again');
        for (final c in recipe.checks) {
          if (!Glob(expandPlaceholders(c.file, unit.key)).matches(rel)) continue;
          final why = failedCheck(c, bytes);
          if (why != null) throw SyncBlocked('${unit.key}: $why');
        }
        staged[rel] = bytes;
        archive.addFile(ArchiveFile.bytes(rel, bytes));
      }
      final zip = ZipEncoder().encodeBytes(archive);
      final payloadSha = sha256.convert(zip).toString();
      final packageVersion = await fs.versionName(binding.package);
      final gameVersion = gameVersionOf(recipe, unit.key, staged);
      final v = recipe.version;
      if (v != null && (v.fromPackage ? packageVersion : gameVersion) == null) throw SyncBlocked('${unit.key}: cannot read the save version');
      final now = _clock().toUtc();
      final meta = GenMeta(
        gen: makeGenId(now, deviceId, payloadSha),
        parents: [for (final x in parents) x.gen],
        kind: kind,
        recipe: recipe.id,
        unit: unit.key,
        device: deviceId,
        deviceName: deviceName,
        createdAt: now,
        package: binding.package,
        packageVersion: packageVersion,
        gameVersion: gameVersion,
        files: {for (final rel in rels) rel: GenFile(unit.files[rel]!.sha256, staged[rel]!.length)},
        payloadSha256: payloadSha,
      );
      return (meta, zip);
    } finally {
      await stage.delete(recursive: true);
    }
  }
}

/// The version a save file records (Stardew's `<gameVersion>`), when the recipe says where to find it.
String? gameVersionOf(Recipe r, String unitKey, Map<String, List<int>> files) {
  final v = r.version;
  if (v == null || v.fromPackage || v.file == null || v.xmlTag == null) return null;
  final g = Glob(expandPlaceholders(v.file!, unitKey));
  for (final e in files.entries) {
    if (g.matches(e.key)) return xmlTagText(e.value, v.xmlTag!);
  }
  return null;
}
