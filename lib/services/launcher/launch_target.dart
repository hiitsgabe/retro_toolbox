import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/services/m3u_service.dart';

/// The disc types a launcher disc set may hold: the M3U screen's plus the
/// GameCube, Wii and PSP images it never lists.
const launchDiscExtensions = {...M3uService.discExtensions, '.rvz', '.gcz', '.wbfs', '.cso'};

const _multiFile = {'.m3u', '.cue', '.gdi'};

/// The file a launch opens, or why there is none.
class LaunchTarget {
  const LaunchTarget(String this.path, {this.discs = const []}) : unsupportedExtension = null;

  /// No candidate the preset system accepts; [unsupportedExtension] is the
  /// best candidate's (no dot), for "does not open .zip".
  const LaunchTarget.unsupported(this.unsupportedExtension)
      : path = null,
        discs = const [];

  final String? path;

  /// For an m3u, the absolute paths of the discs it lists.
  final List<String> discs;
  final String? unsupportedExtension;

  bool get supported => path != null;

  /// An m3u, cue or gdi: the emulator has to reach sibling files.
  bool get multiFile => path != null && _multiFile.contains(p.extension(path!).toLowerCase());
}

/// Picks the file of [game] that [system] opens. A disc of a set whose
/// `<set>.m3u` sits in the library dir launches the m3u; otherwise the order
/// is m3u, then cue/gdi, then a disc image, then any other file.
LaunchTarget resolveLaunchTarget(OwnedGame game, PresetSystem system) {
  final candidates = <String>[];
  void add(String path) {
    if (!candidates.any((c) => p.equals(c, path))) candidates.add(path);
  }

  final mine = {for (final f in game.paths) p.basename(f)};
  for (final set in M3uService.detectDiscSets(_rootFiles(game.dir), extensions: launchDiscExtensions)) {
    if (!set.discs.any(mine.contains)) continue;
    final m3u = p.join(game.dir, '${set.base}.m3u');
    if (File(m3u).existsSync()) add(m3u);
    break;
  }
  game.paths.forEach(add);
  if (candidates.isEmpty) return const LaunchTarget.unsupported(null);

  final ranked = [...candidates]..sort((a, b) => _rank(a).compareTo(_rank(b)));
  final accepted = system.extensions.toSet();
  for (final c in ranked) {
    if (!accepted.contains(_ext(c))) continue;
    return LaunchTarget(c, discs: _ext(c) == 'm3u' ? _m3uDiscs(c) : const []);
  }
  return LaunchTarget.unsupported(_ext(ranked.first));
}

String _ext(String path) {
  final e = p.extension(path).toLowerCase();
  return e.isEmpty ? '' : e.substring(1);
}

int _rank(String path) => switch (_ext(path)) {
      'm3u' => 0,
      'cue' || 'gdi' => 1,
      'chd' || 'iso' || 'pbp' || 'rvz' || 'cso' => 2,
      _ => 3,
    };

List<String> _rootFiles(String dir) {
  try {
    return [for (final e in Directory(dir).listSync(followLinks: false)) if (e is File) p.basename(e.path)];
  } on FileSystemException {
    return const [];
  }
}

List<String> _m3uDiscs(String m3u) {
  try {
    return [
      for (final line in File(m3u).readAsLinesSync())
        if (line.trim().isNotEmpty && !line.trim().startsWith('#')) p.normalize(p.join(p.dirname(m3u), line.trim())),
    ];
  } on FileSystemException {
    return const [];
  }
}
