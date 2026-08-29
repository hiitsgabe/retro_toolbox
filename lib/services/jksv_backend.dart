import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:roms_downloader/services/jksv_meta.dart';

/// Bridges a folder of emulator save exports (`<TitleID>/<raw files>`) to the
/// JKSV backup format (a zip whose root is the save root, plus a generated
/// `.nx_save_meta.bin`). Also applies incoming Switch backups back into the
/// folder, keeping a timestamped copy of whatever it replaces.
class EmuTitle {
  final String titleId;
  final Directory dir;
  const EmuTitle({required this.titleId, required this.dir});
}

class JksvBackend {
  /// The user-chosen folder holding `<TitleID>/…` export folders.
  final Directory root;

  /// Resolves a display name for a title id (via the catalog). Returns null
  /// when unknown — the caller falls back to the raw title id.
  final String Function(String titleId)? nameFor;

  JksvBackend({required this.root, this.nameFor});

  static final _titleIdDir = RegExp(r'^[0-9A-Fa-f]{16}$');

  /// Export title folders present in [root]. Ignores our own `backups/` and
  /// `incoming/` staging dirs.
  List<EmuTitle> listTitles() {
    if (!root.existsSync()) return [];
    final out = <EmuTitle>[];
    for (final e in root.listSync().whereType<Directory>()) {
      final name = p.basename(e.path);
      if (_titleIdDir.hasMatch(name)) {
        out.add(EmuTitle(titleId: name.toUpperCase(), dir: e));
      }
    }
    out.sort((a, b) => a.titleId.compareTo(b.titleId));
    return out;
  }

  /// JKSV-safe display name for a title (unsafe path chars replaced), matching
  /// how JKSV strips names on the remote.
  String displayName(String titleId) {
    final raw = nameFor?.call(titleId) ?? titleId;
    return raw.split('').map((c) => RegExp(r'[a-zA-Z0-9 .\-_()\[\]]').hasMatch(c) ? c : '_').join().trim();
  }

  /// Builds a JKSV-restorable zip for [titleId]: every export file at the zip
  /// root plus a `.nx_save_meta.bin` carrying the title id.
  List<int> buildBackupZip(String titleId) {
    final dir = Directory(p.join(root.path, titleId));
    final archive = Archive();
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final rel = p.relative(f.path, from: dir.path);
      final data = f.readAsBytesSync();
      archive.addFile(ArchiveFile(rel, data.length, data));
    }
    final meta = JksvMeta.encode(applicationId: int.parse(titleId, radix: 16));
    archive.addFile(ArchiveFile(JksvMeta.fileName, meta.length, meta));
    return ZipEncoder().encode(archive);
  }

  /// Applies an incoming JKSV backup zip for [titleId] into the export folder.
  /// Backs up the existing export to `backups/<TitleID>/<timestamp>/` first.
  /// Drops JKSV's `.nx_save_meta.bin`; keeps the raw save files. [timestamp]
  /// is injected so the caller controls naming (tests stay deterministic).
  void applyIncoming(String titleId, List<int> zipBytes, {required String timestamp}) {
    final target = Directory(p.join(root.path, titleId));
    if (target.existsSync()) {
      final backup = Directory(p.join(root.path, 'backups', titleId, timestamp));
      backup.createSync(recursive: true);
      for (final f in target.listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(f.path, from: target.path);
        final dest = File(p.join(backup.path, rel));
        dest.parent.createSync(recursive: true);
        f.copySync(dest.path);
      }
      target.deleteSync(recursive: true);
    }
    target.createSync(recursive: true);

    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (p.basename(entry.name) == JksvMeta.fileName) continue;
      final dest = File(p.join(target.path, entry.name));
      dest.parent.createSync(recursive: true);
      dest.writeAsBytesSync(entry.content as List<int>);
    }
  }
}
