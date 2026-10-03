import 'dart:io';

import 'package:path/path.dart' as p;

/// A remote file plus its path relative to the browsed folder, '/'-separated.
typedef RemoteFile<T> = ({T entry, String relPath});

/// Expands a selection of remote entries (files and folders) into every file
/// they contain, at any depth. [children] lists a folder, given the entry and
/// its relative path. Shared by the SMB and FTP browsers.
Future<List<RemoteFile<T>>> collectRemoteFiles<T>(
  List<T> roots, {
  required String Function(T) nameOf,
  required bool Function(T) isDir,
  required Future<List<T>> Function(T dir, String relPath) children,
}) async {
  final out = <RemoteFile<T>>[];
  Future<void> walk(List<T> entries, String prefix) async {
    for (final e in entries) {
      final name = nameOf(e);
      if (name == '.' || name == '..') continue; // FTP listings include these
      final rel = prefix.isEmpty ? name : '$prefix/$name';
      if (isDir(e)) {
        await walk(await children(e, rel), rel);
      } else {
        out.add((entry: e, relPath: rel));
      }
    }
  }

  await walk(roots, '');
  return out;
}

/// Local destination for [relPath] under [root], creating its parent folders.
Future<String> localPathFor(String root, String relPath) async {
  final path = p.joinAll([root, ...relPath.split('/')]);
  await Directory(p.dirname(path)).create(recursive: true);
  return path;
}
