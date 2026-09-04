import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/archive_extract_service.dart';

void main() {
  final service = ArchiveExtractService();

  test('archiveKind classifies by extension, case-insensitive', () {
    expect(ArchiveExtractService.archiveKind('a.zip'), ArchiveKind.zip);
    expect(ArchiveExtractService.archiveKind('a.RAR'), ArchiveKind.rar);
    expect(ArchiveExtractService.archiveKind('a.7z'), ArchiveKind.unsupported);
    expect(ArchiveExtractService.archiveKind('a.nes'), ArchiveKind.unsupported);
  });

  test('rarSupported only on android/ios/macos', () {
    for (final os in ['android', 'ios', 'macos']) {
      expect(ArchiveExtractService.rarSupported(overrideOs: os), true, reason: os);
    }
    for (final os in ['linux', 'windows']) {
      expect(ArchiveExtractService.rarSupported(overrideOs: os), false, reason: os);
    }
  });

  test('extract rejects RAR on unsupported platforms', () async {
    await expectLater(
      service.extract('/tmp/x.rar', '/tmp/out', overrideOs: 'linux'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('extract rejects unknown archive types', () async {
    await expectLater(
      service.extract('/tmp/x.7z', '/tmp/out', overrideOs: 'macos'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('extract unpacks a real zip to the output folder', () async {
    final dir = Directory.systemTemp.createTempSync('ax_test');
    addTearDown(() => dir.existsSync() ? dir.deleteSync(recursive: true) : null);

    final bytes = utf8Bytes('hello world');
    final archive = Archive()..addFile(ArchiveFile('inner/hello.txt', bytes.length, bytes));
    final zipPath = p.join(dir.path, 'sample.zip');
    File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));

    final out = p.join(dir.path, 'out');
    await service.extract(zipPath, out);
    expect(File(p.join(out, 'inner', 'hello.txt')).existsSync(), true);
  });
}

List<int> utf8Bytes(String s) => s.codeUnits;
