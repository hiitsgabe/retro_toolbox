import 'dart:io';

import 'package:path/path.dart' as p;

/// A single file with the size used to decide which duplicate to keep.
typedef FileEntry = ({String path, int size});

/// A proposed rename produced by the clean-names scan.
typedef RenameEntry = ({String path, String from, String to});

/// A junk file/folder found by the ghost scan.
typedef GhostEntry = ({String path, String name, int size, bool isDir});

/// Ports the console_utilities file-management utilities (Dedupe Games,
/// Clean File Names, Ghost File Cleaner) into three folder-scoped operations.
/// The pure helpers hold the decision logic; the scan/apply methods are thin
/// disk wrappers over them. Deletes/renames are always previewed by the caller.
class CollectionCleanService {
  /// Extensions treated as game files by dedupe and clean-names (flat scans).
  static const gameExtensions = {
    '.zip', '.7z', '.rar', '.iso', '.bin', '.cue', '.chd', '.nsp', '.nsz', '.xci',
    '.cia', '.3ds', '.nds', '.gba', '.gbc', '.gb', '.nes', '.sfc', '.smc', '.md',
    '.gen', '.smd', '.gg', '.sms', '.pce', '.n64', '.z64', '.v64', '.gcm', '.wbfs',
    '.wad', '.pbp', '.cso', '.pkg',
  };

  static const _ghostFileNames = {'.DS_Store', 'Thumbs.db', 'desktop.ini'};
  static const _ghostDirNames = {'__MACOSX', '.AppleDouble'};

  static final _parens = RegExp(r'\(.*?\)');
  static final _brackets = RegExp(r'\[.*?\]');
  static final _ws = RegExp(r'\s+');
  static final _nonAlnum = RegExp(r'[^a-z0-9\s]');

  // --- pure helpers -------------------------------------------------------

  /// Canonical key for duplicate grouping: drop extension and region/rev tags,
  /// lowercase, keep only alphanumerics and single spaces.
  static String normalizeName(String filename) {
    var n = p.basenameWithoutExtension(filename);
    n = n.replaceAll(_parens, '').replaceAll(_brackets, '').toLowerCase();
    n = n.replaceAll(_nonAlnum, '');
    return n.split(_ws).where((s) => s.isNotEmpty).join(' ').trim();
  }

  /// Proposed clean filename (tags stripped, whitespace collapsed, extension
  /// and case preserved). Null when nothing changes or the base would be empty.
  static String? cleanFileName(String filename) {
    final ext = p.extension(filename);
    var base = p.basenameWithoutExtension(filename);
    base = base.replaceAll(_parens, '').replaceAll(_brackets, '');
    base = base.split(_ws).where((s) => s.isNotEmpty).join(' ').trim();
    if (base.isEmpty) return null;
    final cleaned = '$base$ext';
    return cleaned != filename ? cleaned : null;
  }

  static bool isGhostFile(String basename) => _ghostFileNames.contains(basename) || basename.startsWith('._');

  static bool isGhostDir(String basename) => _ghostDirNames.contains(basename);

  /// Groups [files] by [normalizeName] and returns every file except the
  /// largest in each group with more than one member.
  static List<FileEntry> pickDuplicateRemovals(List<FileEntry> files) {
    final groups = <String, List<FileEntry>>{};
    for (final f in files) {
      final key = normalizeName(p.basename(f.path));
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(f);
    }
    final removals = <FileEntry>[];
    for (final g in groups.values) {
      if (g.length < 2) continue;
      g.sort((a, b) => b.size.compareTo(a.size));
      removals.addAll(g.skip(1));
    }
    return removals;
  }

  // --- disk wrappers ------------------------------------------------------

  // Static path entry points so scans can run off the UI thread via `compute`.
  static List<FileEntry> scanDuplicatesPath(String path) => CollectionCleanService().scanDuplicates(Directory(path));
  static List<RenameEntry> scanRenamesPath(String path) => CollectionCleanService().scanRenames(Directory(path));
  static List<GhostEntry> scanGhostsPath(String path) => CollectionCleanService().scanGhosts(Directory(path));

  static bool _isGame(String path) => gameExtensions.contains(p.extension(path).toLowerCase());

  List<FileSystemEntity> _flatGameFiles(Directory dir) => dir
      .listSync(followLinks: false)
      .whereType<File>()
      .where((f) => _isGame(f.path))
      .toList();

  /// Duplicate game files in [dir] (flat), largest kept. Returns the removals.
  List<FileEntry> scanDuplicates(Directory dir) {
    final files = _flatGameFiles(dir).map<FileEntry>((f) => (path: f.path, size: f.statSync().size)).toList();
    return pickDuplicateRemovals(files);
  }

  /// Proposed renames for game files in [dir] (flat).
  List<RenameEntry> scanRenames(Directory dir) {
    final renames = <RenameEntry>[];
    for (final f in _flatGameFiles(dir)) {
      final name = p.basename(f.path);
      final cleaned = cleanFileName(name);
      if (cleaned != null) renames.add((path: f.path, from: name, to: cleaned));
    }
    return renames;
  }

  /// Junk files/folders anywhere under [dir] (recursive).
  List<GhostEntry> scanGhosts(Directory dir) {
    final ghosts = <GhostEntry>[];
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory && isGhostDir(name)) {
        ghosts.add((path: e.path, name: name, size: _dirSize(e), isDir: true));
      } else if (e is File && isGhostFile(name)) {
        ghosts.add((path: e.path, name: name, size: e.statSync().size, isDir: false));
      }
    }
    return ghosts;
  }

  /// Deletes [paths], but only those inside [base]. Returns how many were removed.
  int applyDelete(Directory base, Iterable<String> paths) {
    final rootWithSep = '${base.path}${Platform.pathSeparator}';
    // Deepest paths first so a ghost folder's children are gone before it is.
    final sorted = paths.toList()..sort((a, b) => b.length.compareTo(a.length));
    var count = 0;
    for (final path in sorted) {
      if (_resolveWithin(path, rootWithSep) == null) continue;
      final type = FileSystemEntity.typeSync(path);
      try {
        if (type == FileSystemEntityType.directory) {
          Directory(path).deleteSync(recursive: true);
        } else if (type == FileSystemEntityType.file) {
          File(path).deleteSync();
        } else {
          continue; // already gone
        }
        count++;
      } on FileSystemException {
        // Permission denied or race — skip, matches the source's leniency.
      }
    }
    return count;
  }

  /// Renames each [from]→[to] within [base] when the target does not exist.
  /// Returns how many succeeded.
  int applyRenames(Directory base, List<RenameEntry> renames) {
    var count = 0;
    for (final r in renames) {
      final dest = p.join(p.dirname(r.path), r.to);
      if (_resolveWithin(r.path, '${base.path}${Platform.pathSeparator}') == null) continue;
      if (File(dest).existsSync() || Directory(dest).existsSync()) continue;
      try {
        File(r.path).renameSync(dest);
        count++;
      } on FileSystemException {
        // Skip on error, matches the source's leniency.
      }
    }
    return count;
  }

  static String? _resolveWithin(String path, String rootWithSep) {
    final resolved = p.normalize(p.absolute(path));
    return resolved.startsWith(p.normalize(rootWithSep.substring(0, rootWithSep.length - 1))) ? resolved : null;
  }

  static int _dirSize(Directory dir) {
    var total = 0;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += e.statSync().size;
        } on FileSystemException {
          // ignore unreadable entries
        }
      }
    }
    return total;
  }
}
