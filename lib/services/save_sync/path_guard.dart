import 'package:path/path.dart' as p;

/// The absolute paths one sync run may touch: the bound package's areas and
/// the Toolbox's own SaveSync folder. Every path goes through [check] before
/// a shell command sees it.
class PathGuard {
  PathGuard(Iterable<String> roots) : _roots = roots.map(p.posix.normalize).toList();

  final List<String> _roots;

  /// The normalised [path], or throws [PathRefused] when it is relative,
  /// contains a `..` segment, a newline or a backslash, or is outside every root.
  String check(String path) {
    if (!path.startsWith('/') || path.contains('\n') || path.contains(r'\') || path.split('/').contains('..')) {
      throw PathRefused(path);
    }
    final norm = p.posix.normalize(path);
    for (final r in _roots) {
      if (norm == r || p.posix.isWithin(r, norm)) return norm;
    }
    throw PathRefused(path);
  }

  /// True for a relative path made of plain segments: no leading slash, no
  /// empty, `.` or `..` segment, no backslash, no newline. Glob characters are allowed.
  static bool isSafeRelative(String rel) {
    if (rel.isEmpty || rel.startsWith('/') || rel.contains(r'\') || rel.contains('\n')) return false;
    return !rel.split('/').any((s) => s.isEmpty || s == '.' || s == '..');
  }
}

class PathRefused implements Exception {
  PathRefused(this.path);

  final String path;

  @override
  String toString() => 'Path refused: $path';
}
