import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

typedef FileOpsProgress = void Function(int done, int total);

/// Local file operations for the file explorer: copy/move (recursive, never
/// overwriting) and zip, each reporting progress in bytes.
class FileOps {
  /// [name] when free in [dir], else `name (1)`, `name (2)`… with the number
  /// before the extension, so a copy never overwrites an existing entry.
  /// [reserved] marks more full paths as taken.
  static String uniqueName(String dir, String name, {bool Function(String path)? reserved}) {
    bool taken(String n) => FileSystemEntity.typeSync(p.join(dir, n)) != FileSystemEntityType.notFound || (reserved?.call(p.join(dir, n)) ?? false);
    if (!taken(name)) return name;
    final isDir = FileSystemEntity.isDirectorySync(p.join(dir, name));
    final ext = isDir ? '' : p.extension(name);
    final stem = name.substring(0, name.length - ext.length);
    for (var i = 1;; i++) {
      final candidate = '$stem ($i)$ext';
      if (!taken(candidate)) return candidate;
    }
  }

  /// Total bytes of every file under [paths].
  static Future<int> sizeOf(List<String> paths) async {
    var total = 0;
    for (final path in paths) {
      if (await FileSystemEntity.isDirectory(path)) {
        await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
          if (e is File) total += await e.length();
        }
      } else {
        total += await File(path).length();
      }
    }
    return total;
  }

  /// Copies (or moves, with [move]) each of [sources] into [destDir], folders
  /// recursively. A name already in [destDir] gets [uniqueName]. Throws
  /// [ArgumentError] when a folder would be copied into itself.
  static Future<void> copyInto(List<String> sources, String destDir, {bool move = false, FileOpsProgress? onProgress}) async {
    final dest = p.normalize(p.absolute(destDir));
    for (final s in sources) {
      final src = p.normalize(p.absolute(s));
      if (dest == src || p.isWithin(src, dest)) {
        throw ArgumentError('Can\'t ${move ? 'move' : 'copy'} ${p.basename(src)} into itself');
      }
    }
    await Directory(dest).create(recursive: true);
    final total = await sizeOf(sources);
    var done = 0;
    void advance(int n) {
      done += n;
      onProgress?.call(done, total);
    }

    for (final s in sources) {
      final target = p.join(dest, uniqueName(dest, p.basename(s)));
      if (move && await _tryRename(s, target)) {
        advance(await sizeOf([target]));
        continue;
      }
      try {
        await _copy(s, target, advance);
      } catch (_) {
        // Cancelled (the progress callback threw) or failed: no partial copy.
        try {
          await _delete(target);
        } catch (_) {}
        rethrow;
      }
      if (move) await _delete(s);
    }
    onProgress?.call(total, total);
  }

  /// A same-volume move is a rename: instant, no copy. False when the volumes
  /// differ (e.g. internal storage to SD card), so the caller copies instead.
  static Future<bool> _tryRename(String src, String target) async {
    try {
      if (await FileSystemEntity.isDirectory(src)) {
        await Directory(src).rename(target);
      } else {
        await File(src).rename(target);
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static Future<void> _copy(String src, String target, void Function(int) advance) async {
    if (await FileSystemEntity.isDirectory(src)) {
      await Directory(target).create(recursive: true);
      await for (final e in Directory(src).list(followLinks: false)) {
        await _copy(e.path, p.join(target, p.basename(e.path)), advance);
      }
      return;
    }
    final out = File(target).openWrite();
    try {
      await for (final chunk in File(src).openRead()) {
        out.add(chunk);
        advance(chunk.length);
      }
      await out.flush();
    } finally {
      await out.close();
    }
  }

  static Future<void> _delete(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  /// Zips [sources] into [outZip], each at its name relative to its own
  /// parent (a folder keeps its tree). Runs in an isolate — compression would
  /// otherwise freeze the UI — and reports bytes added. When [onProgress]
  /// throws (the task was cancelled) or the zip fails, the isolate is stopped
  /// and the partial [outZip] deleted.
  static Future<void> zip(List<String> sources, String outZip, {FileOpsProgress? onProgress}) async {
    final total = await sizeOf(sources);
    final port = ReceivePort();
    final errors = ReceivePort();
    final isolate = await Isolate.spawn(_zipWorker, [port.sendPort, sources, outZip], onError: errors.sendPort);
    final done = Completer<void>();
    var reported = 0;
    void report(int bytes) {
      if (bytes <= reported || done.isCompleted) return;
      reported = bytes;
      try {
        onProgress?.call(bytes, total);
      } catch (e) {
        done.completeError(e);
      }
    }

    // ponytail: the encoder says nothing inside a file, so a big file's progress
    // is the zip's size on disk; compressed bytes trail the input, so the bar
    // jumps at the end. Count the bytes the encoder reads if that matters.
    final poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      try {
        report(min(File(outZip).lengthSync(), total - 1));
      } catch (_) {} // not created yet
    });
    final errSub = errors.listen((e) {
      if (!done.isCompleted) done.completeError(Exception((e as List).first));
    });
    final sub = port.listen((msg) {
      if (msg is List) {
        report(msg[0] as int);
      } else if (msg is String) {
        if (!done.isCompleted) done.completeError(Exception(msg));
      } else if (!done.isCompleted) {
        done.complete();
      }
    });
    try {
      await done.future;
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      try {
        await File(outZip).delete();
      } catch (_) {}
      rethrow;
    } finally {
      poll.cancel();
      await sub.cancel();
      await errSub.cancel();
      port.close();
      errors.close();
    }
  }

  static Future<void> _zipWorker(List<dynamic> args) async {
    final send = args[0] as SendPort;
    final sources = (args[1] as List).cast<String>();
    final outZip = args[2] as String;
    try {
      final files = <(File, String)>[];
      for (final s in sources) {
        final base = p.dirname(s);
        if (await FileSystemEntity.isDirectory(s)) {
          await for (final e in Directory(s).list(recursive: true, followLinks: false)) {
            if (e is File) files.add((e, p.relative(e.path, from: base)));
          }
        } else {
          files.add((File(s), p.basename(s)));
        }
      }
      var total = 0;
      for (final (f, _) in files) {
        total += await f.length();
      }
      final encoder = ZipFileEncoder()..create(outZip);
      var done = 0;
      for (final (f, name) in files) {
        // Zip entries always use '/', whatever the platform separator.
        await encoder.addFile(f, p.posix.joinAll(p.split(name)));
        done += await f.length();
        send.send([done, total]);
      }
      await encoder.close();
      send.send(null);
    } catch (e) {
      send.send('$e');
    }
  }
}
