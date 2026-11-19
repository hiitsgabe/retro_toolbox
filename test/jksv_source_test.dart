import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/jksv_folder_source.dart';
import 'package:retro_toolbox/services/jksv_meta.dart';
import 'package:retro_toolbox/services/jksv_source.dart';

/// Copy of `JksvBackend.buildBackupZip` before the JksvSource refactor, kept as
/// the reference the folder source must still match.
List<int> legacyBuildBackupZip(String titleId, File src) {
  final export = ZipDecoder().decodeBytes(src.readAsBytesSync());
  final out = Archive();
  final prefix = '$titleId/';
  for (final e in export) {
    if (!e.isFile) continue;
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

/// Entry names, file flags and bytes in archive order. Zip timestamps come from
/// the wall clock, so raw bytes can differ across a 2 s tick; this plus the
/// total length is what a restore and a PROPFIND see.
List<List<Object>> entries(List<int> zip) => [
      for (final e in ZipDecoder().decodeBytes(zip)) [e.name, e.isFile, e.isFile ? List<int>.from(e.content as List<int>) : const <int>[]]
    ];

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('jksv_source_test'));
  tearDown(() => root.deleteSync(recursive: true));

  File writeExportZip(String fileName, String titleId, Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) => archive.addFile(ArchiveFile('$titleId/$name', content.length, content.codeUnits)));
    return File(p.join(root.path, fileName))..writeAsBytesSync(ZipEncoder().encode(archive));
  }

  test('folder source backup matches the pre-refactor buildBackupZip', () async {
    final src = writeExportZip('game.zip', '010043600B6A6000', {'SP-Opt': 'opt', 'slot': 'data'});
    final legacy = legacyBuildBackupZip('010043600B6A6000', src);
    final now = await FolderJksvSource(root: root).backupZip('010043600B6A6000');
    expect(entries(now), entries(legacy));
    expect(now.length, legacy.length);
  });

  test('folder source backup matches the legacy one for nested, lower-case and foreign entries', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('0100abcd00001000/slot', 1, [1]))
      ..addFile(ArchiveFile('0100ABCD00001000/dir/inner.bin', 2, [2, 3]))
      ..addFile(ArchiveFile('0100ABCD00001000/', 0, Uint8List(0)))
      ..addFile(ArchiveFile('other/stray', 1, [9]));
    final src = File(p.join(root.path, 'mixed.zip'))..writeAsBytesSync(ZipEncoder().encode(archive));
    final legacy = legacyBuildBackupZip('0100ABCD00001000', src);
    final now = await FolderJksvSource(root: root).backupZip('0100ABCD00001000');
    expect(entries(now), entries(legacy));
    expect(now.length, legacy.length);
  });

  group('shared conversion', () {
    List<int> exportZip(String titleId, Map<String, List<int>> files) {
      final a = Archive();
      files.forEach((rel, data) => a.addFile(ArchiveFile('$titleId/$rel', data.length, data)));
      return ZipEncoder().encode(a);
    }

    test('exportToJksv then jksvToExportFiles returns the original files', () {
      const id = '0100ABCD00001000';
      final files = {
        'slot00': 'savedata'.codeUnits,
        'dir/inner.bin': [0, 1, 2, 255],
        'empty': <int>[],
      };
      final back = jksvToExportFiles(id, exportToJksv(id, exportZip(id, files)));
      expect(back.keys.toSet(), {for (final k in files.keys) '$id/$k'});
      files.forEach((rel, data) => expect(back['$id/$rel'], data, reason: rel));
    });

    test('exportToJksv puts the save root at the zip root with a meta carrying the title id', () {
      const id = '0100ABCD00001000';
      final archive = ZipDecoder().decodeBytes(exportToJksv(id, exportZip(id, {'slot00': 'x'.codeUnits})));
      expect(archive.map((e) => e.name).toList(), ['slot00', JksvMeta.fileName]);
      final meta = JksvMeta.decode(Uint8List.fromList(archive.findFile(JksvMeta.fileName)!.content as List<int>));
      expect(meta.magicOk, isTrue);
      expect(meta.applicationId, 0x0100ABCD00001000);
    });

    test('jksvToExportFiles drops the meta and prefixes the title id', () {
      final jksv = Archive()
        ..addFile(ArchiveFile('slot', 3, 'NEW'.codeUnits))
        ..addFile(ArchiveFile('sub/${JksvMeta.fileName}', 1, [7]))
        ..addFile(ArchiveFile(JksvMeta.fileName, JksvMeta.size, JksvMeta.encode(applicationId: 1)));
      final files = jksvToExportFiles('0100ABCD00001000', ZipEncoder().encode(jksv));
      expect(files.keys.toList(), ['0100ABCD00001000/slot']);
      expect(files['0100ABCD00001000/slot'], 'NEW'.codeUnits);
    });
  });
}
