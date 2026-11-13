import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/glob.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/save_checks.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

enum CheckLevel { ok, warn, fail }

class CheckLine {
  const CheckLine(this.level, this.title, this.detail);

  final CheckLevel level;
  final String title;
  final String detail;
}

/// The Check button: what is installed, where the saves are, whether they
/// and the hub copies are intact. Writes nothing to the game folder or the hub.
class GameChecker {
  GameChecker({required this.fs, required this.hub, required this.paths, required this.privilege, required this.stagingRoot, Random? random})
      : _random = random ?? Random.secure();

  final GameFs fs;
  final Hub hub;
  final DevicePaths paths;
  final Privilege privilege;
  final String stagingRoot;
  final Random _random;

  Future<List<CheckLine>> check(Recipe r, {required String source, Binding? binding}) async {
    final out = <CheckLine>[];
    void add(CheckLevel level, String title, String detail) => out.add(CheckLine(level, title, detail));

    add(CheckLevel.ok, 'Recipe', '${r.name}: ${r.status.name} recipe from $source');

    final installed = <String, String?>{};
    for (final pkg in r.packages) {
      if (await fs.installed(pkg)) installed[pkg] = await fs.versionName(pkg);
    }
    if (installed.isEmpty) {
      add(CheckLevel.fail, 'App', 'Not installed (${r.packages.join(', ')})');
      return out;
    }
    for (final e in installed.entries) {
      add(CheckLevel.ok, 'App', '${e.key} ${e.value ?? '(version unknown)'}');
    }

    var b = binding;
    if (b == null) {
      switch (await RecipeBinder(fs, paths, privilege: privilege).bind(r)) {
        case Bound(:final binding):
          b = binding;
        case NeedsConfirm(:final binding, :final files):
          b = binding;
          add(CheckLevel.warn, 'Save folder', 'Found ${files.length} save file(s) in ${binding.dir(paths)}; confirm this place on the Save Sync screen');
        case NotInstalled():
          add(CheckLevel.fail, 'App', 'Not installed');
          return out;
        case NeedsRoot(:final binding, :final reason):
          add(CheckLevel.fail, 'Access', '${binding.dir(paths)}: $reason, so this needs root');
          return out;
        case FolderMissing(:final binding):
          add(CheckLevel.fail, 'Save folder', '${binding.dir(paths)} does not exist yet; open the game once');
          return out;
        case NeedsDiscovery(:final reason):
          add(CheckLevel.fail, 'Save folder', 'Unknown: $reason');
          return out;
      }
    }
    final dir = b.dir(paths);
    if (b.area == Area.internal && privilege != Privilege.root) {
      add(CheckLevel.fail, 'Access', '$dir needs root');
      return out;
    }
    add(CheckLevel.ok, 'Access', privilege == Privilege.root ? 'root' : 'Shizuku (shell)');
    if (!await fs.isDir(dir)) {
      add(CheckLevel.fail, 'Save folder', '$dir does not exist; open the game once');
      return out;
    }
    add(CheckLevel.ok, 'Save folder', dir);
    if (await fs.running(b.package)) add(CheckLevel.warn, 'Game', '${r.name} is running; Push and Pull wait until it is closed');

    final rels = [for (final e in await fs.listFiles(dir)) p.posix.relative(e.path, from: dir)];
    final units = await UnitScanner(fs).scan(r, dir);
    if (units.isEmpty) add(CheckLevel.warn, 'Saves here', 'No saves on this device yet');

    final stage = Directory(p.join(stagingRoot, 'check-${_random.nextInt(1 << 32).toRadixString(16)}'));
    await stage.create(recursive: true);
    try {
      for (final u in units.values) {
        if (u.busy) {
          add(CheckLevel.warn, u.key, 'A save is in progress or was interrupted');
          continue;
        }
        final problems = <String>[];
        for (final rel in u.files.keys) {
          final applicable = r.checks.where((c) => Glob(expandPlaceholders(c.file, u.key)).matches(rel)).toList();
          if (applicable.isEmpty) continue;
          final dst = p.join(stage.path, rel);
          await Directory(p.dirname(dst)).create(recursive: true);
          await fs.copyOut(p.posix.join(dir, rel), dst);
          final bytes = await File(dst).readAsBytes();
          for (final c in applicable) {
            final why = failedCheck(c, bytes);
            if (why != null) problems.add(why);
          }
        }
        add(problems.isEmpty ? CheckLevel.ok : CheckLevel.fail, u.key, problems.isEmpty ? '${u.files.length} file(s), checks pass' : problems.join('; '));
      }
      final stays = [
        for (final rel in rels)
          if (r.deviceLocal.any((g) => Glob(expandPlaceholders(g, _keyFor(r, rel))).matches(rel))) rel,
      ];
      if (stays.isNotEmpty) add(CheckLevel.ok, 'Stays on this device', stays.join(', '));

      final hubUnits = await hub.units(r.id);
      if (hubUnits.isEmpty) add(CheckLevel.warn, 'Hub', 'No saves of ${r.name} in the hub yet');
      for (final key in hubUnits) {
        final heads = headsOf(await hub.gens(r.id, key));
        if (heads.isEmpty) {
          add(CheckLevel.warn, 'Hub $key', 'No finished versions');
          continue;
        }
        if (heads.length > 1) add(CheckLevel.warn, 'Hub $key', '${heads.length} versions diverged; choose one on the Save Sync screen');
        final newest = heads.first;
        try {
          final archive = ZipDecoder().decodeBytes(await hub.payload(newest));
          final files = {for (final f in archive) if (f.isFile) f.name: sha256.convert(f.content).toString()};
          if (!mapEquals(files, newest.hashes)) {
            add(CheckLevel.fail, 'Hub $key', '${newest.gen} does not match its metadata');
            continue;
          }
        } catch (e) {
          add(CheckLevel.fail, 'Hub $key', '$e');
          continue;
        }
        final refused = versionRefusal(r, newest, installed[b.package]);
        if (refused != null) {
          add(CheckLevel.warn, 'Hub $key', 'Newest (${newest.gen}): $refused');
          continue;
        }
        add(CheckLevel.ok, 'Hub $key', 'Newest ${newest.gen} by ${newest.deviceName}, intact');
      }
    } finally {
      await stage.delete(recursive: true);
    }
    return out;
  }

  static String _keyFor(Recipe r, String rel) => switch (r.unit) {
        UnitKind.folder => rel.split('/').first,
        UnitKind.file => rel,
        UnitKind.all => 'all',
      };
}
