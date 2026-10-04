import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/file_ops.dart';

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

/// A transfer the task queue runs in the background, reporting progress.
typedef TransferJob = Future<void> Function(FileOpsProgress onProgress);

/// Runs [download] into a temporary folder, zips what it produced into
/// [outZip], then removes the folder. Progress: 90% download, 10% zip.
Future<void> downloadThenZip(
  Future<void> Function(String dir, FileOpsProgress onProgress) download,
  String outZip,
  FileOpsProgress onProgress,
) async {
  final tmp = await Directory.systemTemp.createTemp('remote_zip');
  try {
    await download(tmp.path, (d, t) => onProgress(t > 0 ? d * 90 ~/ t : 0, 100));
    final top = [for (final e in tmp.listSync()) e.path];
    await FileOps.zip(top, outZip, onProgress: (d, t) => onProgress(90 + (t > 0 ? d * 10 ~/ t : 0), 100));
  } finally {
    await tmp.delete(recursive: true);
  }
}
