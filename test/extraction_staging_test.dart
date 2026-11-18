import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/extraction_service.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('rt_extract'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<String>> extract(String zip, String into, List<String> allowed) {
    final done = Completer<List<String>>();
    ExtractionService.extractInIsolate('t', zip, into,
        allowedExtensions: allowed,
        onProgress: (_, __) {},
        onComplete: (_, __, files) => done.complete(files),
        onError: (_, e, __) => done.completeError(e));
    return done.future;
  }

  void writeZip(String zipPath, Map<String, String> files) {
    final a = Archive();
    files.forEach((name, body) => a.addFile(ArchiveFile.string(name, body)));
    File(zipPath).writeAsBytesSync(ZipEncoder().encode(a));
  }

  // Android 12+ refuses a foreground service started while the app is in the
  // background (an auto-extract after a download finished behind another app).
  // The archive must still be extracted, not handed to a service that is not there.
  test('a refused foreground service falls back to extracting in an isolate', () async {
    final zip = p.join(dir.path, 'game.zip');
    writeZip(zip, {'Game/game.iso': 'disc'});
    ExtractionService.useForegroundService = () => true;
    ExtractionService.startForegroundService = (_) async =>
        ServiceRequestFailure(error: Exception('startForegroundService() not allowed due to mAllowStartForeground false'));
    addTearDown(ExtractionService.resetForTesting);

    final done = Completer<List<String>>();
    await ExtractionService.startExtraction(
      taskId: 't',
      filePath: zip,
      extractionDir: dir.path,
      allowedExtensions: const ['.iso'],
      onProgress: (_, __) {},
      onComplete: (_, __, files) => done.complete(files),
      onError: (_, e, __) => done.completeError(e),
    );

    final files = await done.future.timeout(const Duration(seconds: 10));
    expect(files.map(p.basename), ['game.iso']);
    expect(File(p.join(dir.path, 'game.iso')).readAsStringSync(), 'disc');
  });

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

  test('complete reports only this archive\'s files', () async {
    // Another game already extracted into the same console folder.
    File(p.join(dir.path, 'other.cue')).writeAsStringSync('c');
    File(p.join(dir.path, 'other.bin')).writeAsStringSync('b');
    final zip = p.join(dir.path, 'game.zip');
    writeZip(zip, {'game.cue': 'c', 'game.bin': 'b', 'readme.txt': 'x'});

    final files = await extract(zip, dir.path, ['.cue', '.bin']);

    expect(files.toSet(), {p.join(dir.path, 'game.cue'), p.join(dir.path, 'game.bin')});
  });
}
