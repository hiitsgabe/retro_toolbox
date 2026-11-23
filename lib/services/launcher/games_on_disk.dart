import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';

/// [console]'s [Console.onDiskFormats] less every extension another console
/// of [sharing] claims too. [sharing] are the consoles with the same library
/// dir; in a dir they share, a file such an extension names is no one's.
Set<String> ownFormats(Console console, Iterable<Console> sharing) {
  final others = {
    for (final c in sharing)
      if (c.id != console.id) ...c.onDiskFormats,
  };
  return console.onDiskFormats.difference(others);
}

/// Whether [dir] holds a game in one of [formats]: a file at its root, or a
/// root folder with such a file directly inside (an extracted game). Nothing
/// deeper counts. False when [dir] cannot be read. Loads no catalog.
Future<bool> hasGamesOnDisk(String dir, Set<String> formats) async {
  if (dir.isEmpty || formats.isEmpty) return false;
  bool game(FileSystemEntity e) => e is File && formats.contains(p.extension(e.path).toLowerCase());
  try {
    await for (final e in Directory(dir).list(followLinks: false)) {
      if (game(e)) return true;
      if (e is Directory) {
        try {
          if (await e.list(followLinks: false).any(game)) return true;
        } on FileSystemException {
          // One unreadable folder does not hide the rest.
        }
      }
    }
  } on FileSystemException {
    return false;
  }
  return false;
}
