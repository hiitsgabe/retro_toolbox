import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:retro_toolbox/services/jksv_meta.dart';

/// Where the JDKV server reads Switch saves from and writes incoming ones to.
/// Async because a source can live behind the network (the Save Sync hub).
abstract class JksvSource {
  /// Upper-case 16-hex title ids with a save to serve.
  Future<List<String>> titleIds();

  /// JKSV-safe folder name for a title on the remote.
  String displayName(String titleId);

  /// A JKSV-restorable zip: save root at the zip root plus `.nx_save_meta.bin`.
  Future<List<int>> backupZip(String titleId);

  /// Stores a backup uploaded by JKSV. [timestamp] names whatever it replaces.
  Future<void> applyIncoming(String titleId, List<int> jksvZip, {required String timestamp});
}

/// Export layout (`<TitleID>/<rel>`, what Eden/Yuzu "Export Save" writes) to
/// JKSV layout: the save root at the zip root (JKSV wants "root of zip = root
/// of save"), plus a `.nx_save_meta.bin` carrying the title id.
List<int> exportToJksv(String titleId, List<int> exportZip) {
  final export = ZipDecoder().decodeBytes(exportZip);
  final out = Archive();
  final prefix = '$titleId/';
  for (final e in export) {
    if (!e.isFile) continue;
    // Strip the `<TitleID>/` prefix so the save root sits at the zip root.
    final upper = e.name.toUpperCase();
    if (!upper.startsWith(prefix)) continue;
    final rel = e.name.substring(prefix.length);
    if (rel.isEmpty) continue;
    final data = e.content as List<int>;
    out.addFile(ArchiveFile(rel, data.length, data));
  }
  final meta = JksvMeta.encode(applicationId: int.parse(titleId, radix: 16));
  out.addFile(ArchiveFile(JksvMeta.fileName, meta.length, meta));
  return ZipEncoder().encode(out);
}

/// JKSV layout to export layout files: `<TitleID>/<rel>` to bytes, in zip
/// order, with the meta dropped (the emulator has no use for it).
Map<String, List<int>> jksvToExportFiles(String titleId, List<int> jksvZip) {
  final incoming = ZipDecoder().decodeBytes(Uint8List.fromList(jksvZip));
  final files = <String, List<int>>{};
  for (final e in incoming) {
    if (!e.isFile) continue;
    if (p.basename(e.name) == JksvMeta.fileName) continue;
    files['$titleId/${e.name}'] = e.content as List<int>;
  }
  return files;
}
