import 'dart:io';

import 'package:path/path.dart' as p;

/// A multi-disc game and its disc files, ordered by disc number.
typedef DiscSet = ({String base, List<String> discs});

/// Generates .m3u playlists for multi-disc games so emulators (RetroArch,
/// DuckStation) and scanning frontends treat the set as one entry with
/// in-game disc swapping. Ported in spirit from the console_utilities utils.
class M3uService {
  /// Disc-image types worth listing in a playlist (raw .bin tracks are
  /// referenced by their .cue, so they are excluded).
  static const discExtensions = {'.cue', '.chd', '.iso', '.gdi', '.pbp'};

  static final _discToken = RegExp(r'\((?:disc|disk|cd)\s*(\d+)[^)]*\)', caseSensitive: false);
  static final _ws = RegExp(r'\s+');

  /// Groups [filenames] into multi-disc sets, keyed by the title with its
  /// disc token stripped. Only sets with two or more discs are returned, each
  /// ordered by disc number.
  static List<DiscSet> detectDiscSets(List<String> filenames) {
    final groups = <String, List<({int n, String file})>>{};
    for (final f in filenames) {
      if (!discExtensions.contains(p.extension(f).toLowerCase())) continue;
      final m = _discToken.firstMatch(f);
      if (m == null) continue;
      final n = int.tryParse(m.group(1)!) ?? 0;
      final base = p.basenameWithoutExtension(f).replaceAll(_discToken, '').replaceAll(_ws, ' ').trim();
      if (base.isEmpty) continue;
      groups.putIfAbsent(base, () => []).add((n: n, file: f));
    }
    final sets = <DiscSet>[];
    for (final e in groups.entries) {
      if (e.value.length < 2) continue;
      final ordered = [...e.value]..sort((a, b) => a.n.compareTo(b.n));
      sets.add((base: e.key, discs: ordered.map((d) => d.file).toList()));
    }
    sets.sort((a, b) => a.base.compareTo(b.base));
    return sets;
  }

  /// Scans [dir] (flat) for multi-disc sets.
  List<DiscSet> scanDiscSets(Directory dir) {
    final names = dir.listSync(followLinks: false).whereType<File>().map((f) => p.basename(f.path)).toList();
    return detectDiscSets(names);
  }

  /// Writes `<base>.m3u` into [dir], one disc basename per line. Overwrites.
  File writeM3u(Directory dir, DiscSet set) {
    final file = File(p.join(dir.path, '${set.base}.m3u'));
    file.writeAsStringSync('${set.discs.join('\n')}\n');
    return file;
  }
}
