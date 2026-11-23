import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/library_snapshot_model.dart';

/// A game whose files are on disk, as the launcher sees it.
class OwnedGame {
  const OwnedGame({required this.game, required this.dir, required this.paths});

  final Game game;

  /// The console's library dir.
  final String dir;

  /// Absolute paths of the game's files on disk.
  final List<String> paths;

  /// From a catalog game's presence in [snapshot], or null when it has none.
  /// A downloaded file is `<dir>/<filename>`, or the file whose real name
  /// `sanitizeForFat` turns into that one; an extracted game is what the
  /// snapshot indexed for it (its folder, or its root siblings), sorted by
  /// path, with the archive itself last when it was kept.
  static OwnedGame? fromPresence(Game game, String dir, LibraryPresence presence, LibrarySnapshot snapshot) {
    final file = snapshot.pathFor(game.filename);
    String abs(String path) => p.isAbsolute(path) ? path : p.join(dir, path);
    // Sorted because the snapshot keeps the directory's listing order, which differs between devices and
    // would make a tie in resolveLaunchTarget pick a different file on each. A set because the scan files a
    // folder with no extension under its name and its base name, which are the same key, so each file twice.
    List<String> extracted() => {for (final f in snapshot.relatedFilesFor(game.filename)) abs(f)}.toList()..sort();
    final paths = switch (presence) {
      LibraryPresence.none => null,
      LibraryPresence.file => [file],
      LibraryPresence.extracted => extracted(),
      LibraryPresence.fileAndExtracted => [
          for (final f in extracted())
            if (!p.equals(f, file)) f,
          file,
        ],
    };
    return paths == null ? null : OwnedGame(game: game, dir: dir, paths: paths);
  }

  /// A loose game (see OwnedLibrary): the files [sideMap] keeps for its
  /// gameId, by their real names. Null when it keeps none.
  static OwnedGame? fromLoose(Game game, String dir, Map<String, List<String>> sideMap) {
    final paths = sideMap[game.gameId];
    return paths == null || paths.isEmpty ? null : OwnedGame(game: game, dir: dir, paths: paths);
  }
}
