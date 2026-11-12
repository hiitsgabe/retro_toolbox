import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';

/// Copies of saves this device replaced: `<root>/<recipe>/<unit>/<stamp>-<reason>/<relative paths>`.
/// The folder is the Toolbox's own, on shared storage, so a file manager can reach it.
class LocalHistory {
  LocalHistory(this.root, this.fs, {this.keep = 20});

  final String root;
  final GameFs fs;
  final int keep;

  String _unitDir(String recipe, String unit) => p.join(root, recipe, unit);

  Future<String> newEntry(String recipe, String unit, String reason, {DateTime? now}) async {
    final base = p.join(_unitDir(recipe, unit), '${utcStamp(now ?? DateTime.now())}-$reason');
    var dir = Directory(base);
    for (var n = 2; await dir.exists(); n++) {
      dir = Directory('$base-$n');
    }
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Copies [rels] (relative to [locationDir]) into [entry] through the privileged shell.
  Future<void> snapshot(String entry, String locationDir, Iterable<String> rels) async {
    for (final rel in rels) {
      final dst = p.join(entry, rel);
      await Directory(p.dirname(dst)).create(recursive: true);
      await fs.copyOut(p.posix.join(locationDir, rel), dst);
    }
  }

  /// Entry folder names, newest first.
  Future<List<String>> entries(String recipe, String unit) async {
    final d = Directory(_unitDir(recipe, unit));
    if (!await d.exists()) return const [];
    final names = [await for (final e in d.list()) if (e is Directory) p.basename(e.path)]..sort();
    return names.reversed.toList();
  }

  /// Deletes all but the newest [keep] entries, never [except] (the entry a
  /// pull just made: a clock that once ran ahead can make it sort as oldest).
  Future<void> trim(String recipe, String unit, {String? except}) async {
    for (final name in (await entries(recipe, unit)).skip(keep).where((n) => p.join(_unitDir(recipe, unit), n) != except)) {
      await Directory(p.join(_unitDir(recipe, unit), name)).delete(recursive: true);
    }
  }
}
