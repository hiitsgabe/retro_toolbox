import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/extraction_service.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('rt_extract'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> extract(String zip, String into, List<String> allowed) {
    final done = Completer<void>();
    ExtractionService.extractInIsolate('t', zip, into,
        allowedExtensions: allowed,
        onProgress: (_, __) {},
        onComplete: (_, __) => done.complete(),
        onError: (_, e, __) => done.completeError(e));
    return done.future;
  }

  void writeZip(String zipPath, Map<String, String> files) {
    final a = Archive();
    files.forEach((name, body) => a.addFile(ArchiveFile.string(name, body)));
    File(zipPath).writeAsBytesSync(ZipEncoder().encode(a));
  }

  test('extracting into the console folder leaves its other files alone', () async {
    // A console folder: other queued archives, a gamelist and media.
    File(p.join(dir.path, 'queued.zip')).writeAsStringSync('zip');
    File(p.join(dir.path, 'gamelist.xml')).writeAsStringSync('xml');
    Directory(p.join(dir.path, 'images')).createSync();
    File(p.join(dir.path, 'images', 'a.png')).writeAsStringSync('png');
    final zip = p.join(dir.path, 'game.zip');
    writeZip(zip, {'Game/game.gbc': 'rom', 'Game/readme.txt': 'junk'});

    await extract(zip, dir.path, ['.gbc']);

    expect(File(p.join(dir.path, 'game.gbc')).readAsStringSync(), 'rom');
    expect(File(p.join(dir.path, 'readme.txt')).existsSync(), false);
    expect(File(p.join(dir.path, 'queued.zip')).existsSync(), true);
    expect(File(p.join(dir.path, 'gamelist.xml')).existsSync(), true);
    expect(File(p.join(dir.path, 'images', 'a.png')).existsSync(), true);
    expect(dir.listSync().where((e) => p.basename(e.path).startsWith('.rt-extract')), isEmpty);
  });

  test('merges into existing folders and replaces files', () async {
    Directory(p.join(dir.path, 'Disc')).createSync();
    File(p.join(dir.path, 'Disc', 'keep.cue')).writeAsStringSync('mine');
    File(p.join(dir.path, 'Disc', 'game.cue')).writeAsStringSync('old');
    final zip = p.join(dir.path, 'game.zip');
    writeZip(zip, {'Disc/game.cue': 'new', 'Disc/game.bin': 'bin', 'game.m3u': 'list'});

    await extract(zip, dir.path, const []);

    expect(File(p.join(dir.path, 'Disc', 'game.cue')).readAsStringSync(), 'new');
    expect(File(p.join(dir.path, 'Disc', 'game.bin')).existsSync(), true);
    expect(File(p.join(dir.path, 'Disc', 'keep.cue')).readAsStringSync(), 'mine');
    expect(File(p.join(dir.path, 'game.m3u')).existsSync(), true);
  });
}
