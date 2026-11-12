import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/glob.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';

bool _any(List<String> patterns, String key, String rel) => patterns.any((g) => Glob(expandPlaceholders(g, key)).matches(rel));

/// Unit key to the sorted relative paths that travel for it. A folder unit
/// only looks inside its own folder; file and all units look at every file.
Map<String, List<String>> groupUnits(Recipe r, Iterable<String> rels) {
  final out = <String, List<String>>{};
  void add(String key, String rel) => (out[key] ??= []).add(rel);
  switch (r.unit) {
    case UnitKind.folder:
      for (final rel in rels) {
        final slash = rel.indexOf('/');
        if (slash <= 0) continue;
        final key = rel.substring(0, slash);
        if (_any(r.include, key, rel) && !_any(r.deviceLocal, key, rel)) add(key, rel);
      }
    case UnitKind.file:
      for (final rel in rels) {
        if (_any(r.include, rel, rel) && !_any(r.deviceLocal, rel, rel)) add(rel, rel);
      }
    case UnitKind.all:
      for (final rel in rels) {
        if (_any(r.include, 'all', rel) && !_any(r.deviceLocal, 'all', rel)) add('all', rel);
      }
  }
  for (final v in out.values) {
    v.sort();
  }
  return out;
}

/// Units with an `inProgress` match: a folder unit inside its folder, other units anywhere under the root.
Set<String> busyUnits(Recipe r, Iterable<String> rels) {
  final keys = groupUnits(r, rels).keys;
  final busy = {
    for (final key in keys)
      if (rels.any((rel) => (r.unit != UnitKind.folder || rel.startsWith('$key/')) && _any(r.inProgress, key, rel))) key,
  };
  if (r.unit == UnitKind.folder) {
    // A folder holding only travelling leftovers (temp, _old) has no files in a group but is still mid-write.
    for (final rel in rels) {
      final slash = rel.indexOf('/');
      if (slash <= 0) continue;
      final key = rel.substring(0, slash);
      if (_any(r.inProgress, key, rel)) busy.add(key);
    }
  }
  return busy;
}

class LocalFile {
  const LocalFile(this.sha256, this.size);

  final String sha256;
  final int size;
}

class LocalUnit {
  const LocalUnit(this.key, this.files, {this.busy = false});

  final String key;

  /// Relative path (to the location root) to its hash and size.
  final Map<String, LocalFile> files;
  final bool busy;

  Map<String, String> get hashes => {for (final e in files.entries) e.key: e.value.sha256};
}

class UnitScanner {
  UnitScanner(this.fs);

  final GameFs fs;

  /// The units under [rootDir]. Files are hashed between two listings; a unit
  /// whose files changed size or time in between is busy (still being written).
  Future<Map<String, LocalUnit>> scan(Recipe recipe, String rootDir) async {
    final before = await fs.listFiles(rootDir);
    final rel = {for (final e in before) p.posix.relative(e.path, from: rootDir): e};
    final groups = groupUnits(recipe, rel.keys);
    final busy = busyUnits(recipe, rel.keys);
    final hashes = await fs.sha256([for (final g in groups.values) ...g.map((r) => rel[r]!.path)]);
    final after = {for (final e in await fs.listFiles(rootDir)) e.path: e};
    return {
      for (final key in busy)
        if (!groups.containsKey(key)) key: LocalUnit(key, const {}, busy: true),
      for (final g in groups.entries)
        g.key: LocalUnit(
          g.key,
          {for (final r in g.value) r: LocalFile(hashes[rel[r]!.path]!, rel[r]!.size)},
          busy: busy.contains(g.key) ||
              g.value.any((r) {
                final a = after[rel[r]!.path];
                return a == null || a.size != rel[r]!.size || a.mtime != rel[r]!.mtime;
              }),
        ),
    };
  }
}
