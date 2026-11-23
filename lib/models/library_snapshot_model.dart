import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_state_model.dart';

enum LibraryPresence {
  none,
  file,
  extracted,
  fileAndExtracted;

  GameStatus toGameStatus() => switch (this) {
        LibraryPresence.extracted || LibraryPresence.fileAndExtracted => GameStatus.extracted,
        LibraryPresence.file => GameStatus.downloaded,
        LibraryPresence.none => GameStatus.ready,
      };
}

class LibrarySnapshot {
  final String libraryDir;
  final Set<String> exactFiles;
  final Set<String> baseNames;
  final Map<String, List<String>> relatedFiles;

  /// Root files under a real name `Game.sanitizeForFat` changes, by the name
  /// it gives them: a file copied in from a disk that allows `:` or a
  /// trailing dot is the catalog game of that name.
  final Map<String, String> aliases;

  final DateTime timestamp;

  const LibrarySnapshot({
    required this.libraryDir,
    required this.exactFiles,
    required this.baseNames,
    required this.relatedFiles,
    this.aliases = const {},
    required this.timestamp,
  });

  LibraryPresence statusFor(String filename) {
    final base = p.basename(filename);
    final ext = p.extension(base).toLowerCase();
    final baseNoExt = p.basenameWithoutExtension(base);
    final hasExact = exactFiles.contains(base) || aliases.containsKey(base);

    // Files we indexed for this base (includes root siblings and any files from an extracted folder)
    final rel = relatedFiles[baseNoExt] ?? const <String>[];

    // 1) Treat as extracted if there are files under .../<baseNoExt>/...
    final hasDirContent = rel.any((abs) {
      final parent = p.basename(p.dirname(abs));
      return parent == baseNoExt;
    });

    // 2) Or if there is a root-level sibling with same base but different extension
    final hasSiblingDifferentExtAtRoot = rel.any((abs) {
      // only root-level; as paths, so a saved folder ending in '/' still matches
      if (!p.equals(p.dirname(abs), libraryDir)) return false;
      final b = p.basename(abs);
      return p.basenameWithoutExtension(b) == baseNoExt && p.extension(b).toLowerCase() != ext;
    });

    final extracted = hasDirContent || hasSiblingDifferentExtAtRoot;

    if (hasExact && extracted) return LibraryPresence.fileAndExtracted;
    if (extracted) return LibraryPresence.extracted;
    if (hasExact) return LibraryPresence.file;
    return LibraryPresence.none;
  }

  Map<String, LibraryPresence> statusesFor(Iterable<String> filenames) {
    final result = <String, LibraryPresence>{};
    for (final f in filenames) {
      result[f] = statusFor(f);
    }
    return result;
  }

  /// The base names (file names without extension) that have anything in the
  /// library: a file, or files in a folder of that name. Cost follows the
  /// library's size, not the catalog's; [statusFor] settles each candidate.
  Set<String> presentBaseNames() => {
        ...baseNames,
        ...relatedFiles.keys,
        for (final f in exactFiles) p.basenameWithoutExtension(f),
        for (final a in aliases.keys) p.basenameWithoutExtension(a),
      };

  /// The root file [filename] is on disk: itself, or else the file whose
  /// real name `Game.sanitizeForFat` turns into it.
  String pathFor(String filename) {
    final base = p.basename(filename);
    return p.join(libraryDir, exactFiles.contains(base) ? base : aliases[base] ?? base);
  }

  Map<String, LibraryPresence> allStatuses() {
    final map = <String, LibraryPresence>{};
    for (final f in exactFiles) {
      map[f] = LibraryPresence.file;
    }
    for (final b in baseNames) {
      final hasExact = exactFiles.any((f) => p.basenameWithoutExtension(f) == b);
      map[b] = hasExact ? LibraryPresence.fileAndExtracted : LibraryPresence.extracted;
    }
    return map;
  }

  List<String> relatedFilesFor(String filename) {
    final base = p.basenameWithoutExtension(p.basename(filename));
    final fromBase = relatedFiles[base] ?? const [];
    if (fromBase.isNotEmpty) {
      final preferred = fromBase.where((abs) {
        final seg = p.separator + base + p.separator;
        return abs.contains(seg) || p.dirname(abs).endsWith(p.separator + base);
      }).toList();
      return preferred.isNotEmpty ? preferred : fromBase;
    }
    return relatedFiles[p.basename(filename)] ?? const [];
  }

  LibrarySnapshot copyWith({
    Set<String>? exactFiles,
    Set<String>? baseNames,
    Map<String, List<String>>? relatedFiles,
    Map<String, String>? aliases,
    DateTime? timestamp,
  }) {
    return LibrarySnapshot(
      libraryDir: libraryDir,
      exactFiles: exactFiles ?? this.exactFiles,
      baseNames: baseNames ?? this.baseNames,
      relatedFiles: relatedFiles ?? this.relatedFiles,
      aliases: aliases ?? this.aliases,
      timestamp: timestamp ?? DateTime.now(),
    );
  }
}
