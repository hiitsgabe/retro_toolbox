import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:retro_toolbox/services/jksv_source.dart';

class EmuTitle {
  final String titleId;
  final File zip;
  const EmuTitle({required this.titleId, required this.zip});
}

/// Bridges a folder of **emulator export zips** (each a `<TitleID>/<raw files>`
/// archive, exactly what Eden/Yuzu "Export Save" produces) to the JKSV backup
/// format. Also writes incoming Switch saves back out as export zips the user
/// can re-import, keeping a timestamped copy of what it replaces.
class FolderJksvSource implements JksvSource {
  /// The user-chosen folder holding emulator export `*.zip` files.
  final Directory root;

  /// Resolves a display name for a title id (via the catalog). Returns null
  /// when unknown — the caller falls back to the raw title id.
  final String Function(String titleId)? nameFor;

  FolderJksvSource({required this.root, this.nameFor});

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
  @override
  String displayName(String titleId) => jksvSafeName(nameFor?.call(titleId) ?? titleId);

  File? _zipFor(String titleId) {
    for (final t in listTitles()) {
      if (t.titleId == titleId) return t.zip;
    }
    return null;
  }

  @override
  Future<List<String>> titleIds() async => [for (final t in listTitles()) t.titleId];

  @override
  Future<List<int>> backupZip(String titleId) async {
    final src = _zipFor(titleId);
    if (src == null) throw StateError('No export zip for $titleId');
    return exportToJksv(titleId, src.readAsBytesSync());
  }

  /// Writes an incoming JKSV backup for [titleId] as a new export zip in
  /// [root]. Any existing export for the title is moved to
  /// `backups/<TitleID>/<timestamp>.zip` first.
  @override
  Future<void> applyIncoming(String titleId, List<int> jksvZip, {required String timestamp}) async {
    final existing = _zipFor(titleId);
    if (existing != null) {
      final backupDir = Directory(p.join(root.path, 'backups', titleId))..createSync(recursive: true);
      existing.renameSync(p.join(backupDir.path, '$timestamp.zip'));
    }

    final export = Archive();
    jksvToExportFiles(titleId, jksvZip).forEach((name, data) => export.addFile(ArchiveFile(name, data.length, data)));
    final name = displayName(titleId).isEmpty ? titleId : displayName(titleId);
    File(p.join(root.path, '$name [$titleId].zip')).writeAsBytesSync(ZipEncoder().encode(export));
  }
}
