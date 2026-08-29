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

  /// Writes an emulator-style export zip (`<TitleID>/<files>`) into [root].
  void writeExportZip(String fileName, String titleId, Map<String, String> files) {
    final archive = Archive();
    files.forEach((name, content) => archive.addFile(ArchiveFile('$titleId/$name', content.length, content.codeUnits)));
    File(p.join(root.path, fileName)).writeAsBytesSync(ZipEncoder().encode(archive));
  }

  test('listTitles reads the title id from export zip contents', () {
    writeExportZip('South Park.zip', '010043600B6A6000', {'slot00': 'x'});
    File(p.join(root.path, 'not-a-zip.txt')).writeAsStringSync('nope');
    final backend = JksvBackend(root: root);
    expect(backend.listTitles().map((t) => t.titleId), ['010043600B6A6000']);
  });

  test('buildBackupZip strips the TitleID prefix and adds meta', () {
    writeExportZip('game.zip', '010043600B6A6000', {'SP-Opt': 'opt', 'slot': 'data'});
    final backend = JksvBackend(root: root);
    final zip = backend.buildBackupZip('010043600B6A6000');
    final archive = ZipDecoder().decodeBytes(zip);
    final names = archive.map((e) => e.name).toSet();
    // Save root at the zip root — no TitleID folder.
    expect(names.contains('SP-Opt'), isTrue);
    expect(names.contains('slot'), isTrue);
    expect(names.any((n) => n.startsWith('010043600B6A6000/')), isFalse);
    final meta = JksvMeta.decode(archive.findFile(JksvMeta.fileName)!.content as dynamic);
    expect(meta.applicationId, 0x010043600B6A6000);
  });

  test('applyIncoming writes an export zip and backs up the old one', () {
    writeExportZip('old.zip', '010043600B6A6000', {'slot': 'OLD'});
    final backend = JksvBackend(root: root, nameFor: (_) => 'South Park');

    // Incoming JKSV backup: save files at root + meta.
    final jksv = Archive()
      ..addFile(ArchiveFile('slot', 3, 'NEW'.codeUnits))
      ..addFile(ArchiveFile(JksvMeta.fileName, 4, [1, 2, 3, 4]));
    backend.applyIncoming('010043600B6A6000', ZipEncoder().encode(jksv), timestamp: '20260829-1200');

    // New export written with the TitleID prefix restored, meta dropped.
    final newZip = File(p.join(root.path, 'South Park [010043600B6A6000].zip'));
    expect(newZip.existsSync(), isTrue);
    final out = ZipDecoder().decodeBytes(newZip.readAsBytesSync());
    expect(out.findFile('010043600B6A6000/slot')!.content, 'NEW'.codeUnits);
    expect(out.findFile(JksvMeta.fileName), isNull);
    // Old export preserved under backups/.
    expect(File(p.join(root.path, 'backups', '010043600B6A6000', '20260829-1200.zip')).existsSync(), isTrue);
  });
}
