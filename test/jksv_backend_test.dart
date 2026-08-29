import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/jksv_backend.dart';
import 'package:roms_downloader/services/jksv_meta.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('jksv_test'));
  tearDown(() => root.deleteSync(recursive: true));

  void writeExport(String titleId, Map<String, String> files) {
    final d = Directory(p.join(root.path, titleId))..createSync(recursive: true);
    files.forEach((name, content) => File(p.join(d.path, name)).writeAsStringSync(content));
  }

  test('listTitles finds only 16-hex export folders', () {
    writeExport('010043600B6A6000', {'slot00': 'x'});
    Directory(p.join(root.path, 'notATitle')).createSync();
    final backend = JksvBackend(root: root);
    expect(backend.listTitles().map((t) => t.titleId), ['010043600B6A6000']);
  });

  test('displayName maps via nameFor and sanitizes', () {
    final backend = JksvBackend(root: root, nameFor: (id) => 'Zelda: TOTK');
    expect(backend.displayName('0100000000010000'), 'Zelda_ TOTK');
  });

  test('buildBackupZip puts raw files at root plus a valid meta', () {
    writeExport('010043600B6A6000', {'SP-Opt': 'opt', 'slot': 'data'});
    final backend = JksvBackend(root: root);
    final zip = backend.buildBackupZip('010043600B6A6000');
    final archive = ZipDecoder().decodeBytes(zip);
    final names = archive.map((e) => e.name).toSet();
    expect(names.contains('SP-Opt'), isTrue);
    expect(names.contains('slot'), isTrue);
    expect(names.contains(JksvMeta.fileName), isTrue);
    final meta = JksvMeta.decode(archive.findFile(JksvMeta.fileName)!.content as dynamic);
    expect(meta.magicOk, isTrue);
    expect(meta.applicationId, 0x010043600B6A6000);
  });

  test('applyIncoming backs up the old save then writes the new one', () {
    writeExport('010043600B6A6000', {'slot': 'OLD'});
    final backend = JksvBackend(root: root);

    final incoming = Archive()..addFile(ArchiveFile('slot', 3, 'NEW'.codeUnits))..addFile(ArchiveFile(JksvMeta.fileName, 4, [1, 2, 3, 4]));
    backend.applyIncoming('010043600B6A6000', ZipEncoder().encode(incoming)!, timestamp: '20260829-1200');

    // New save written, meta dropped.
    expect(File(p.join(root.path, '010043600B6A6000', 'slot')).readAsStringSync(), 'NEW');
    expect(File(p.join(root.path, '010043600B6A6000', JksvMeta.fileName)).existsSync(), isFalse);
    // Old save preserved under backups/.
    expect(File(p.join(root.path, 'backups', '010043600B6A6000', '20260829-1200', 'slot')).readAsStringSync(), 'OLD');
  });
}
