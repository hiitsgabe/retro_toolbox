import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:roms_downloader/services/jksv_meta.dart';

/// Bridges a folder of **emulator export zips** (each a `<TitleID>/<raw files>`
/// archive, exactly what Eden/Yuzu "Export Save" produces) to the JKSV backup
/// format (a zip whose root is the save root, plus a generated
/// `.nx_save_meta.bin`). Also writes incoming Switch saves back out as export
/// zips the user can re-import, keeping a timestamped copy of what it replaces.
class EmuTitle {
  final String titleId;
  final File zip;
  const EmuTitle({required this.titleId, required this.zip});
}

class JksvBackend {
  /// The user-chosen folder holding emulator export `*.zip` files.
  final Directory root;

  /// Resolves a display name for a title id (via the catalog). Returns null
  /// when unknown — the caller falls back to the raw title id.
  final String Function(String titleId)? nameFor;

  JksvBackend({required this.root, this.nameFor});

  static final _titleIdRe = RegExp(r'^([0-9A-Fa-f]{16})/');

  /// The title id carried by an export zip = the 16-hex top-level folder its
  /// entries live under. Null if the zip isn't in export shape.
  static String? titleIdOf(Archive archive) {
    for (final e in archive) {
      final m = _titleIdRe.firstMatch(e.name);
      if (m != null) return m.group(1)!.toUpperCase();
    }
    return null;
  }

  /// Export zips present in [root], keyed by title id. Skips our own output
  /// (`backups/`) which lives in a subdirectory, not at the root.
  List<EmuTitle> listTitles() {
    if (!root.existsSync()) return [];
    final out = <EmuTitle>[];
    final seen = <String>{};
    for (final f in root.listSync().whereType<File>()) {
      if (p.extension(f.path).toLowerCase() != '.zip') continue;
      try {
        final id = titleIdOf(ZipDecoder().decodeBytes(f.readAsBytesSync()));
        if (id != null && seen.add(id)) out.add(EmuTitle(titleId: id, zip: f));
      } catch (_) {}
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

  File? _zipFor(String titleId) {
    for (final t in listTitles()) {
      if (t.titleId == titleId) return t.zip;
    }
    return null;
  }

  /// Builds a JKSV-restorable zip for [titleId]: the export's save files moved
  /// to the zip root (JKSV wants "root of zip = root of save"), plus a
  /// `.nx_save_meta.bin` carrying the title id.
  List<int> buildBackupZip(String titleId) {
    final src = _zipFor(titleId);
    if (src == null) throw StateError('No export zip for $titleId');
    final export = ZipDecoder().decodeBytes(src.readAsBytesSync());
    final out = Archive();
    final prefix = '$titleId/';
    for (final e in export) {
      if (!e.isFile) continue;
      // Strip the `<TitleID>/` prefix so the save root sits at the zip root.
      final lower = e.name.toUpperCase();
      if (!lower.startsWith(prefix)) continue;
      final rel = e.name.substring(prefix.length);
      if (rel.isEmpty) continue;
      final data = e.content as List<int>;
      out.addFile(ArchiveFile(rel, data.length, data));
    }
    final meta = JksvMeta.encode(applicationId: int.parse(titleId, radix: 16));
    out.addFile(ArchiveFile(JksvMeta.fileName, meta.length, meta));
    return ZipEncoder().encode(out);
  }

  /// Applies an incoming JKSV backup zip for [titleId] as a new export zip in
  /// [root] (entries re-prefixed with `<TitleID>/`, meta dropped). Any existing
  /// export for the title is moved to `backups/<TitleID>/<timestamp>.zip`
  /// first. [timestamp] is injected so the caller controls naming.
  void applyIncoming(String titleId, List<int> jksvZipBytes, {required String timestamp}) {
    final existing = _zipFor(titleId);
    if (existing != null) {
      final backupDir = Directory(p.join(root.path, 'backups', titleId))..createSync(recursive: true);
      existing.renameSync(p.join(backupDir.path, '$timestamp.zip'));
    }

    final incoming = ZipDecoder().decodeBytes(Uint8List.fromList(jksvZipBytes));
    final export = Archive();
    for (final e in incoming) {
      if (!e.isFile) continue;
      if (p.basename(e.name) == JksvMeta.fileName) continue;
      final data = e.content as List<int>;
      export.addFile(ArchiveFile('$titleId/${e.name}', data.length, data));
    }
    final name = displayName(titleId).isEmpty ? titleId : displayName(titleId);
    File(p.join(root.path, '$name [$titleId].zip')).writeAsBytesSync(ZipEncoder().encode(export));
  }
}
