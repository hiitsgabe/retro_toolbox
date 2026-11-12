import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/errors.dart';
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/glob.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/local_history.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/save_checks.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

typedef _Undo = Future<void> Function();

/// A unit [Puller.recover] left as it was; [message] is for the user and names [entry] when there is one.
class StuckUnit {
  const StuckUnit(this.unit, this.message, {this.entry});

  final String unit;
  final String message;

  /// The history entry holding the unit's files as recover found them.
  final String? entry;
}

class RecoverResult {
  const RecoverResult(this.recovered, this.stuck);

  final List<String> recovered;
  final List<StuckUnit> stuck;
}

/// Writes one gen into the game folder, keeping what it replaces.
class Puller {
  Puller({required this.fs, required this.hub, required this.history, required this.stagingRoot, Random? random}) : _random = random ?? Random.secure();

  final GameFs fs;
  final Hub hub;
  final LocalHistory history;
  final String stagingRoot;
  final Random _random;

  /// [expectedLocal] is the unit's hashes when the plan was made; the pull
  /// refuses if the files moved since.
  Future<void> pull({
    required Recipe recipe,
    required Binding binding,
    required String locationDir,
    required String unitKey,
    required GenMeta gen,
    required Map<String, String> expectedLocal,
  }) async {
    final staged = await _download(recipe, unitKey, gen);
    await _versionGate(recipe, binding, gen);
    if (await fs.running(binding.package)) throw SyncBlocked('${recipe.name} is running; close it first');
    if (!await fs.isDir(locationDir)) throw PullRefused('Open ${recipe.name} once so it creates its save folder, then try again');
    final units = await UnitScanner(fs).scan(recipe, locationDir);
    _checkBeforeRestore(recipe, unitKey, units.keys);
    final current = units[unitKey];
    if (current?.busy ?? false) throw SyncBlocked('$unitKey: a save is in progress');
    final before = current?.hashes ?? const <String, String>{};
    if (!sameFiles(before, expectedLocal)) throw SyncBlocked('$unitKey changed since the last check; refresh and try again');

    final stage = Directory(p.join(stagingRoot, 'pull-${_random.nextInt(1 << 32).toRadixString(16)}'));
    await stage.create(recursive: true);
    String entry;
    try {
      for (final e in staged.entries) {
        final f = File(p.join(stage.path, e.key));
        await f.parent.create(recursive: true);
        await f.writeAsBytes(e.value, flush: true);
      }
      entry = await history.newEntry(recipe.id, unitKey, 'before-${gen.gen}');
      await history.snapshot(entry, locationDir, before.keys);
      final copies = {for (final rel in before.keys) rel: p.join(entry, rel)};
      final got = await fs.sha256(copies.values.toList());
      if (before.keys.any((rel) => got[p.normalize(copies[rel]!)] != before[rel])) throw SyncBlocked('$unitKey changed while copying');
      // From here on the game folder changes: the journal lets [recover] undo a pull the app did not live to finish.
      final journal = _Journal(p.join(entry, _journalName), {
        'gen': gen.gen,
        'unit': unitKey,
        'locationDir': locationDir,
        'before': before,
        'genFiles': {for (final rel in gen.files.keys.toList()..sort()) rel: gen.files[rel]!.sha256},
        'aside': <String>[],
      });
      await journal.save();
      final undo = <_Undo>[];
      try {
        await _beforeRestore(recipe, unitKey, locationDir, entry, stage.path, undo, journal);
        if (recipe.unit == UnitKind.folder) {
          final unitDir = p.posix.join(locationDir, unitKey);
          if (!await fs.isDir(unitDir)) await fs.makeGameDir(unitDir);
        }
        for (final rel in gen.files.keys.toList()..sort()) {
          final target = p.posix.join(locationDir, rel);
          final had = before[rel];
          // Registered first: a reply lost after the command ran must still be undone.
          undo.add(had != null ? () => fs.replace(p.join(entry, rel), target, had) : () => fs.remove(target));
          await fs.replace(p.join(stage.path, rel), target, gen.files[rel]!.sha256);
        }
        for (final rel in before.keys.where((r) => !gen.files.containsKey(r))) {
          final target = p.posix.join(locationDir, rel), kept = p.join(entry, rel);
          undo.add(() async {
            if (await fs.exists(kept)) await fs.moveTo(kept, target);
          });
          await fs.moveTo(target, kept); // over its identical snapshot copy
        }
        // A game opened mid-pull may hold the old files in memory and write them back over the new ones.
        if (await fs.running(binding.package)) throw SyncBlocked('${recipe.name} started during the pull');
      } catch (e) {
        Object? rollbackError;
        for (final u in undo.reversed) {
          try {
            await u();
          } catch (err) {
            rollbackError ??= err;
          }
        }
        if (rollbackError == null) await journal.delete();
        throw PullRolledBack(e, entry, rollbackError: rollbackError);
      }
      await journal.delete();
    } finally {
      await stage.delete(recursive: true);
    }
    await history.trim(recipe.id, unitKey, except: entry);
  }

  static const _journalName = '.pull.json';

  /// Puts back the unit of every pull whose journal is still in history: the
  /// app died mid-pull, or the rollback failed. It first copies the unit's
  /// files as they are now into a `<stamp>-before-recover` entry. When a file
  /// is in neither its old state nor the gen's (the game saved after the
  /// interruption), or anything fails, the unit stays as it is, keeps its
  /// journal and is reported stuck. Safe to repeat. Call it only while the
  /// game is not running.
  Future<RecoverResult> recover(Recipe recipe) async {
    final journals = <(String, File)>[];
    final root = Directory(p.join(history.root, recipe.id));
    if (await root.exists()) {
      await for (final unitDir in root.list()) {
        if (unitDir is! Directory) continue;
        await for (final e in unitDir.list()) {
          final f = File(p.join(e.path, _journalName));
          if (e is Directory && await f.exists()) journals.add((p.basename(unitDir.path), f));
        }
      }
    }
    journals.sort((a, b) => a.$2.path.compareTo(b.$2.path));
    final recovered = <String>[], stuck = <StuckUnit>[];
    for (final (unit, f) in journals) {
      final s = await _recoverOne(recipe, unit, f);
      if (s == null) {
        recovered.add(unit);
      } else {
        stuck.add(s);
      }
    }
    return RecoverResult(recovered..sort(), stuck);
  }

  /// Null when [unit] was put back.
  Future<StuckUnit?> _recoverOne(Recipe recipe, String unit, File file) async {
    String? kept;
    Map<String, dynamic>? j;
    Map<String, String>? now;
    try {
      j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (j['unit'] != unit) throw FormatException('${file.path} names unit ${j['unit']}');
      final entry = file.parent.path;
      final dir = j['locationDir'] as String;
      final before = (j['before'] as Map).cast<String, String>();
      final genFiles = (j['genFiles'] as Map).cast<String, String>();
      final aside = (j['aside'] as List).cast<String>();
      final all = {...before.keys, ...genFiles.keys, ...aside};
      for (final rel in all) {
        if (!PathGuard.isSafeRelative(rel)) throw PullRefused('Unsafe path in $entry: $rel');
      }
      final present = [for (final rel in all) if (await fs.exists(p.posix.join(dir, rel))) rel];
      final hashed = await fs.sha256([for (final rel in present) p.posix.join(dir, rel)]);
      now = {for (final rel in present) rel: hashed[p.posix.normalize(p.posix.join(dir, rel))]!};
      kept = await _keepAsIs(recipe.id, unit, dir, now, j);

      final asideCopies = {for (final rel in aside) if (await fs.exists(p.join(entry, rel))) rel};
      bool expected(String rel) {
        final h = now![rel];
        if (before.containsKey(rel)) return h == null || h == before[rel] || h == genFiles[rel];
        if (genFiles.containsKey(rel)) return h == null || h == genFiles[rel];
        // Aside: moved away, or back at its place with no copy left (the move never happened, or a recover already put it back).
        return h == null || !asideCopies.contains(rel);
      }

      if (!all.every(expected)) {
        j['recoverEntry'] = kept;
        j['recoverHashes'] = now;
        await _Journal(file.path, j).save();
        return StuckUnit(unit, 'an interrupted pull could not be undone because the files changed since; both versions are kept in $kept', entry: kept);
      }
      // Every copy the restore reads from is checked first, so a missing one leaves the unit untouched rather than half restored.
      final restore = [for (final e in before.entries) if (now[e.key] != e.value) e.key];
      final putBack = [for (final rel in aside) if (!now.containsKey(rel) && !before.containsKey(rel)) rel];
      for (final rel in [...restore, ...putBack]) {
        if (!await fs.exists(p.join(entry, rel))) throw GameFsError('the copy of $rel is missing from $entry');
      }
      for (final rel in restore) {
        if (!await _holds(entry, {rel: before[rel]!})) throw GameFsError('the copy of $rel in $entry does not match what it held before the pull');
      }
      for (final rel in restore) {
        await fs.replace(p.join(entry, rel), p.posix.join(dir, rel), before[rel]!);
      }
      for (final rel in genFiles.keys.where((r) => !before.containsKey(r))) {
        await fs.remove(p.posix.join(dir, rel));
      }
      for (final rel in putBack) {
        await fs.moveTo(p.join(entry, rel), p.posix.join(dir, rel));
      }
      await file.delete();
      return null;
    } catch (e) {
      if (kept == null) return StuckUnit(unit, 'an interrupted pull could not be undone: $e');
      // Recorded as for changed files, so the next recover reuses [kept] while the unit and its copy still match.
      try {
        j!['recoverEntry'] = kept;
        j['recoverHashes'] = now;
        await _Journal(file.path, j).save();
      } catch (_) {}
      return StuckUnit(unit, 'an interrupted pull could not be undone ($e); the files as they are now are kept in $kept', entry: kept);
    }
  }

  /// A history entry holding [now] (the unit's files as they are): the one an
  /// earlier recover of this journal made when it still holds exactly them, else a new one.
  Future<String> _keepAsIs(String recipeId, String unit, String dir, Map<String, String> now, Map<String, dynamic> j) async {
    final last = j['recoverEntry'], lastHashes = j['recoverHashes'];
    if (last is String && p.isWithin(history.root, last) && lastHashes is Map && mapEquals(lastHashes.cast<String, String>(), now) && await _holds(last, now)) {
      return last;
    }
    final entry = await history.newEntry(recipeId, unit, 'before-recover');
    await history.snapshot(entry, dir, now.keys);
    if (!await _holds(entry, now)) {
      // An unverified copy is no copy: remove it, so a unit that stays stuck does not grow history on every recover.
      await Directory(entry).delete(recursive: true);
      throw SyncBlocked('the copy of $unit made before recovering does not match its files');
    }
    return entry;
  }

  Future<bool> _holds(String entry, Map<String, String> hashes) async {
    final copies = {for (final rel in hashes.keys) rel: p.join(entry, rel)};
    for (final c in copies.values) {
      if (!await fs.exists(c)) return false;
    }
    final got = await fs.sha256(copies.values.toList());
    return hashes.keys.every((rel) => got[p.normalize(copies[rel]!)] == hashes[rel]);
  }

  Future<Map<String, List<int>>> _download(Recipe recipe, String unitKey, GenMeta gen) async {
    final archive = ZipDecoder().decodeBytes(await hub.payload(gen));
    final staged = <String, List<int>>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      if (!PathGuard.isSafeRelative(f.name) || !gen.files.containsKey(f.name)) throw PullRefused('${gen.gen} holds an unexpected file: ${f.name}');
      staged[f.name] = f.content;
    }
    if (!setEquals(staged.keys.toSet(), gen.files.keys.toSet())) throw PullRefused('${gen.gen} is incomplete');
    final groups = groupUnits(recipe, staged.keys);
    if (groups.length != 1 || groups[unitKey]?.length != staged.length) throw PullRefused('${gen.gen} holds files that are not part of $unitKey');
    for (final e in staged.entries) {
      if (sha256.convert(e.value).toString() != gen.files[e.key]!.sha256) throw PullRefused('${e.key} in ${gen.gen} does not match its hash');
      for (final c in recipe.checks) {
        if (!Glob(expandPlaceholders(c.file, unitKey)).matches(e.key)) continue;
        final why = failedCheck(c, e.value);
        if (why != null) throw PullRefused('${gen.gen}: $why');
      }
    }
    return staged;
  }

  Future<void> _versionGate(Recipe recipe, Binding binding, GenMeta gen) async {
    if (recipe.version == null) return;
    final refused = versionRefusal(recipe, gen, await fs.versionName(binding.package));
    if (refused != null) throw PullRefused(refused);
  }

  Future<void> _beforeRestore(Recipe recipe, String unitKey, String locationDir, String entry, String stage, List<_Undo> undo, _Journal journal) async {
    for (final step in recipe.beforeRestore) {
      switch (step) {
        case MoveAside(:final paths):
          for (final x in paths) {
            await _aside(_literal(x, unitKey), locationDir, entry, undo, journal);
          }
        case MoveAsideIfFirstStringIs(:final value, :final file):
          final rel = _literal(file, unitKey);
          final abs = p.posix.join(locationDir, rel);
          if (!await fs.exists(abs)) continue;
          final peek = p.join(stage, '.peek');
          await fs.copyOut(abs, peek);
          if (readDotnetString(await File(peek).readAsBytes()) == _literal(value, unitKey)) {
            await _aside(rel, locationDir, entry, undo, journal);
          }
      }
    }
  }

  /// Refuses, before anything is written, a beforeRestore path that belongs to another unit: for a folder unit any path
  /// with a `/` outside `<unitKey>/`; for file and all units a path another unit's files or [onDisk] keys' deviceLocal patterns claim.
  static void _checkBeforeRestore(Recipe recipe, String unitKey, Iterable<String> onDisk) {
    for (final step in recipe.beforeRestore) {
      final rels = switch (step) {
        MoveAside(:final paths) => paths,
        MoveAsideIfFirstStringIs(:final file) => [file],
      };
      for (final x in rels) {
        final rel = _literal(x, unitKey);
        if (recipe.unit == UnitKind.folder) {
          if (rel.contains('/') && !rel.startsWith('$unitKey/')) throw PullRefused('beforeRestore reaches into ${rel.substring(0, rel.indexOf('/'))}');
          if (!rel.contains('/') && (rel == unitKey || onDisk.contains(rel))) throw PullRefused('beforeRestore names the folder of $rel');
          continue;
        }
        final g = groupUnits(recipe, [rel]);
        if (g.isNotEmpty && !g.containsKey(unitKey)) throw PullRefused('beforeRestore reaches into ${g.keys.first}');
        for (final other in onDisk.where((k) => k != unitKey)) {
          if (recipe.deviceLocal.any((d) => Glob(expandPlaceholders(d, other)).matches(rel))) throw PullRefused('beforeRestore reaches into $other');
        }
      }
    }
  }

  Future<void> _aside(String rel, String locationDir, String entry, List<_Undo> undo, _Journal journal) async {
    final src = p.posix.join(locationDir, rel);
    if (!await fs.exists(src)) return;
    // Only files are moved aside: a folder could be a whole save.
    if (await fs.isDir(src)) throw PullRefused('beforeRestore names a folder: $rel');
    final dst = p.join(entry, rel);
    await Directory(p.dirname(dst)).create(recursive: true);
    // Journaled before the move, so a kill between the two is still recovered.
    (journal.data['aside'] as List<String>).add(rel);
    await journal.save();
    undo.add(() async {
      if (await fs.exists(dst)) await fs.moveTo(dst, src);
    });
    await fs.moveTo(src, dst);
  }

  /// A recipe path with the unit key put in literally.
  static String _literal(String s, String key) {
    final out = s.replaceAll('{folder}', key).replaceAll('{file}', key);
    if (!PathGuard.isSafeRelative(out)) throw PullRefused('Unsafe path in the recipe: $out');
    return out;
  }
}

/// `<entry>/.pull.json`: what a pull in progress changed, written whole through a temp file.
class _Journal {
  _Journal(this.path, this.data);

  final String path;
  final Map<String, dynamic> data;

  Future<void> save() async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(path);
  }

  Future<void> delete() async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
