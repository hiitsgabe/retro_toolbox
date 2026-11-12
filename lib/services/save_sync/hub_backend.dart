import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/path_guard.dart';

class HubEntry {
  const HubEntry(this.name, {required this.isDir, this.size = 0});

  final String name;
  final bool isDir;
  final int size;
}

/// The storage a hub lives on. Paths are relative to the hub root and use `/`.
abstract class HubBackend {
  /// Stable key for this hub, part of every stored base.
  String get id;

  /// Entries directly under [dir] (`''` is the root), sorted by name. Empty
  /// when [dir] does not exist. Names starting with `.` are hidden.
  Future<List<HubEntry>> list(String dir);

  Future<List<int>> read(String path);

  /// Creates parent folders as needed. Replaces an existing file whole.
  Future<void> write(String path, List<int> bytes);

  /// No error when [path] is already gone.
  Future<void> delete(String path);
}

/// A hub in a plain folder that another app (Syncthing, FolderSync) carries.
class FolderBackend implements HubBackend {
  FolderBackend(this.root, {Random? random}) : _random = random ?? Random.secure();

  final Directory root;
  final Random _random;

  @override
  String get id => 'folder:${p.normalize(root.path)}';

  String _abs(String rel) {
    if (!PathGuard.isSafeRelative(rel)) throw ArgumentError.value(rel, 'path');
    return p.join(root.path, rel);
  }

  @override
  Future<List<HubEntry>> list(String dir) async {
    final d = Directory(dir.isEmpty ? root.path : _abs(dir));
    if (!await d.exists()) return const [];
    final out = <HubEntry>[];
    await for (final e in d.list()) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        out.add(HubEntry(name, isDir: true));
      } else if (e is File) {
        out.add(HubEntry(name, isDir: false, size: await e.length()));
      }
    }
    return out..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<List<int>> read(String path) => File(_abs(path)).readAsBytes();

  @override
  Future<void> write(String path, List<int> bytes) async {
    final f = File(_abs(path));
    await f.parent.create(recursive: true);
    final tmp = File(p.join(f.parent.path, '.rt-tmp-${_random.nextInt(1 << 32).toRadixString(16)}'));
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    final f = File(_abs(path));
    if (await f.exists()) await f.delete();
  }
}
