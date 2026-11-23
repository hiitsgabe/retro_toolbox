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
  /// A downloaded file is `<dir>/<filename>`; an extracted game is what the
  /// snapshot indexed for it (its folder, or its root siblings), with the
  /// archive itself last when it was kept.
  static OwnedGame? fromPresence(Game game, String dir, LibraryPresence presence, LibrarySnapshot snapshot) {
    final file = p.join(dir, game.filename);
    String abs(String path) => p.isAbsolute(path) ? path : p.join(dir, path);
    final paths = switch (presence) {
      LibraryPresence.none => null,
      LibraryPresence.file => [file],
      LibraryPresence.extracted => [for (final f in snapshot.relatedFilesFor(game.filename)) abs(f)],
      LibraryPresence.fileAndExtracted => [
          for (final f in snapshot.relatedFilesFor(game.filename))
            if (!p.equals(abs(f), file)) abs(f),
          file,
        ],
    };
    return paths == null ? null : OwnedGame(game: game, dir: dir, paths: paths);
  }
}
