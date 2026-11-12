import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';

class FsEntry {
  const FsEntry(this.path, this.size, this.mtime);

  final String path;
  final int size;

  /// Seconds since the epoch.
  final int mtime;
}

class GameFsError implements Exception {
  GameFsError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the sync needs from game folders. Paths are absolute.
abstract class GameFs {
  Future<bool> exists(String path);
  Future<bool> isDir(String path);

  /// Every file under [dir], recursively; empty when [dir] is missing.
  Future<List<FsEntry>> listFiles(String dir);

  /// Path to lowercase hex sha256.
  Future<Map<String, String>> sha256(List<String> paths);

  /// Copies a file; the parent of [dst] must exist. The copy gets the current time.
  Future<void> copyOut(String src, String dst);
  Future<void> moveTo(String src, String dst);
  Future<void> remove(String path);

  /// Puts [staged] at [target] through a temp file in the target's folder,
  /// after checking the temp's hash equals [expectSha].
  Future<void> replace(String staged, String target, String expectSha);

  /// Creates [dir] inside an existing game folder so the game can write in it.
  Future<void> makeGameDir(String dir);

  Future<bool> running(String package);
  Future<String?> versionName(String package);
  Future<bool> installed(String package);
}

class ShellGameFs implements GameFs {
  ShellGameFs(this.shell, this.guard, {Random? random}) : _random = random ?? Random.secure();

  final PrivilegedShell shell;
  final PathGuard guard;
  final Random _random;

  static final _packageRe = RegExp(r'^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$');

  Future<ShellResult> _must(List<String> argv) async {
    final r = await shell.run(argv);
    if (!r.ok) throw GameFsError('${argv.first} failed: $r');
    return r;
  }

  String _pkg(String package) {
    if (!_packageRe.hasMatch(package)) throw ArgumentError.value(package, 'package');
    return package;
  }

  /// A yes/no probe: exit 0 is yes, exit 1 with nothing on stderr is no, and
  /// anything else (a dead bridge, a refused su, a signal) is an error, so a
  /// probe that failed never reads as "absent" or "not running".
  Future<bool> _probe(List<String> argv) async {
    final r = await shell.run(argv);
    if (r.ok) return true;
    if (r.code == 1 && r.err.trim().isEmpty) return false;
    throw GameFsError('${argv.first} failed: $r');
  }

  @override
  Future<bool> exists(String path) => _probe(['test', '-e', guard.check(path)]);

  @override
  Future<bool> isDir(String path) => _probe(['test', '-d', guard.check(path)]);

  @override
  Future<List<FsEntry>> listFiles(String dir) async {
    final d = guard.check(dir);
    if (!await isDir(d)) {
      // `test -d` is false on EACCES too: only a folder that is not there is empty.
      final s = await shell.run(['stat', '-c', '%F', d]);
      if (!s.ok && !s.err.contains('No such file')) throw GameFsError('cannot reach $d: $s');
      return const [];
    }
    final r = await _must(['find', d, '-type', 'f', '-exec', 'stat', '-c', '%s|%Y|%n', '{}', '+']);
    final out = <FsEntry>[];
    for (final line in r.out.split('\n')) {
      final a = line.indexOf('|');
      final b = a < 0 ? -1 : line.indexOf('|', a + 1);
      if (b < 0) continue;
      final size = int.tryParse(line.substring(0, a)), mtime = int.tryParse(line.substring(a + 1, b));
      if (size == null || mtime == null) continue;
      out.add(FsEntry(line.substring(b + 1), size, mtime));
    }
    return out;
  }

  @override
  Future<Map<String, String>> sha256(List<String> paths) async {
    if (paths.isEmpty) return const {};
    final checked = [for (final x in paths) guard.check(x)];
    final r = await _must(['sha256sum', ...checked]);
    final out = <String, String>{};
    for (final line in r.out.split('\n')) {
      final m = RegExp(r'^([0-9a-f]{64}) [ *](.+)$').firstMatch(line);
      if (m != null) out[m[2]!] = m[1]!;
    }
    for (final x in checked) {
      if (!out.containsKey(x)) throw GameFsError('no hash for $x');
    }
    return out;
  }

  @override
  Future<void> copyOut(String src, String dst) => _must(['cp', guard.check(src), guard.check(dst)]);

  @override
  Future<void> moveTo(String src, String dst) => _must(['mv', '-f', guard.check(src), guard.check(dst)]);

  @override
  Future<void> remove(String path) => _must(['rm', '-f', guard.check(path)]);

  @override
  Future<void> replace(String staged, String target, String expectSha) async {
    final src = guard.check(staged), dst = guard.check(target);
    final tmp = guard.check(p.posix.join(p.posix.dirname(dst), '.rtsync-${_random.nextInt(1 << 32).toRadixString(16)}'));
    try {
      await _must(['cp', src, tmp]);
      if (shell.privilege == Privilege.root) await _chownLikeParent(tmp);
      await _must(['chmod', '666', tmp]);
      final got = (await sha256([tmp]))[tmp];
      if (got != expectSha) throw GameFsError('hash mismatch writing $dst');
      await _must(['mv', '-f', tmp, dst]);
    } catch (_) {
      await shell.run(['rm', '-f', tmp]);
      rethrow;
    }
  }

  @override
  Future<void> makeGameDir(String dir) async {
    final d = guard.check(dir);
    // Build under a hidden name and rename last, so the unit's name only exists once the folder is writable.
    final tmp = guard.check(p.posix.join(p.posix.dirname(d), '.rtsync-${_random.nextInt(1 << 32).toRadixString(16)}'));
    try {
      await _must(['mkdir', tmp]);
      if (shell.privilege == Privilege.root) await _chownLikeParent(tmp);
      await _must(['chmod', 'a+rwx', tmp]); // never octal: toybox octal chmod clears the inherited setgid
      await _must(['mv', tmp, d]);
    } catch (_) {
      await shell.run(['rmdir', tmp]);
      rethrow;
    }
  }

  Future<void> _chownLikeParent(String path) async {
    final owner = (await _must(['stat', '-c', '%u:%g', p.posix.dirname(path)])).out.trim();
    await _must(['chown', owner, path]);
  }

  @override
  Future<bool> running(String package) => _probe(['pidof', _pkg(package)]);

  @override
  Future<String?> versionName(String package) async {
    final r = await shell.run(['dumpsys', 'package', _pkg(package)]);
    if (!r.ok) return null;
    final v = RegExp(r'^\s*versionName=(.+)$', multiLine: true).firstMatch(r.out)?.group(1)?.trim();
    return v == null || v == 'null' ? null : v;
  }

  @override
  Future<bool> installed(String package) async {
    final r = await shell.run(['pm', 'path', _pkg(package)]);
    return r.ok && r.out.trim().startsWith('package:');
  }
}
