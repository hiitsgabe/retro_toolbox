import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/file_ops.dart';

late Directory root;

File put(String rel, String content) => File(p.join(root.path, rel))
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

String read(String rel) => File(p.join(root.path, rel)).readAsStringSync();
bool exists(String rel) => FileSystemEntity.typeSync(p.join(root.path, rel)) != FileSystemEntityType.notFound;

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('fileops'));
  tearDown(() => root.deleteSync(recursive: true));

  test('uniqueName keeps the name when free and numbers it otherwise, before the extension', () {
    put('dst/game.zip', 'x');
    put('dst/game (1).zip', 'x');
    put('dst/folder/a', 'x');
    expect(FileOps.uniqueName(p.join(root.path, 'dst'), 'new.bin'), 'new.bin');
    expect(FileOps.uniqueName(p.join(root.path, 'dst'), 'game.zip'), 'game (2).zip');
    expect(FileOps.uniqueName(p.join(root.path, 'dst'), 'folder'), 'folder (1)');
  });

  test('copyInto copies files and whole folders, reporting bytes, and leaves the sources', () async {
    put('src/a.bin', '12345');
    put('src/dir/b.bin', '123');
    put('src/dir/sub/c.bin', '12');
    final seen = <int>[];
    await FileOps.copyInto([p.join(root.path, 'src/a.bin'), p.join(root.path, 'src/dir')], p.join(root.path, 'dst'),
        onProgress: (done, total) {
      expect(total, 10);
      seen.add(done);
    });
    expect(read('dst/a.bin'), '12345');
    expect(read('dst/dir/sub/c.bin'), '12');
    expect(exists('src/dir/b.bin'), isTrue);
    expect(seen.last, 10);
  });

  test('copyInto renames on a clash instead of overwriting', () async {
    put('src/a.bin', 'new');
    put('dst/a.bin', 'old');
    await FileOps.copyInto([p.join(root.path, 'src/a.bin')], p.join(root.path, 'dst'));
    expect(read('dst/a.bin'), 'old');
    expect(read('dst/a (1).bin'), 'new');
  });

  test('move removes the sources', () async {
    put('src/dir/b.bin', '123');
    await FileOps.copyInto([p.join(root.path, 'src/dir')], p.join(root.path, 'dst'), move: true);
    expect(read('dst/dir/b.bin'), '123');
    expect(exists('src/dir'), isFalse);
  });

  test('a folder cannot be copied into itself', () async {
    put('src/dir/b.bin', '1');
    expect(
      () => FileOps.copyInto([p.join(root.path, 'src/dir')], p.join(root.path, 'src/dir/inner')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('zip packs files and folders with their relative paths', () async {
    put('src/a.bin', 'aaa');
    put('src/dir/sub/c.bin', 'cc');
    final out = p.join(root.path, 'out.zip');
    int? lastDone;
    await FileOps.zip([p.join(root.path, 'src/a.bin'), p.join(root.path, 'src/dir')], out, onProgress: (d, t) => lastDone = d);
    final archive = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
    final names = archive.files.where((f) => f.isFile).map((f) => f.name).toSet();
    expect(names, {'a.bin', 'dir/sub/c.bin'});
    expect(lastDone, 5);
  });
}
