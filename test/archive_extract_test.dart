import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rar/rar.dart';
// ignore: implementation_imports
import 'package:rar/src/rar_ffi.dart'; // to assert the backend swap
import 'package:retro_toolbox/services/archive_extract_service.dart';

void main() {
  final service = ArchiveExtractService();
  final savedPath = ArchiveExtractService.linuxRarPath;
  late RarPlatform savedRar;
  setUp(() {
    savedRar = RarPlatform.instance;
    ArchiveExtractService.linuxRar = null;
  });
  tearDown(() {
    RarPlatform.instance = savedRar;
    ArchiveExtractService.linuxRar = null;
    ArchiveExtractService.linuxRarPath = savedPath;
  });

  test('archiveKind classifies by extension, case-insensitive', () {
    expect(ArchiveExtractService.archiveKind('a.zip'), ArchiveKind.zip);
    expect(ArchiveExtractService.archiveKind('a.RAR'), ArchiveKind.rar);
    expect(ArchiveExtractService.archiveKind('a.7z'), ArchiveKind.unsupported);
    expect(ArchiveExtractService.archiveKind('a.nes'), ArchiveKind.unsupported);
  });

  test('rarSupported on android/ios/macos, never windows', () {
    for (final os in ['android', 'ios', 'macos']) {
      expect(ArchiveExtractService.rarSupported(overrideOs: os), true, reason: os);
    }
    expect(ArchiveExtractService.rarSupported(overrideOs: 'windows'), false);
  });

  test('linux: unsupported when the library is missing', () {
    ArchiveExtractService.linuxRarPath = '/nonexistent/lib/librar_native.so';
    expect(ArchiveExtractService.rarSupported(overrideOs: 'linux'), false);
    expect(RarPlatform.instance, same(savedRar));
  });

  test('linux: supported once a library loads, and the plugin goes FFI', () {
    // Any loadable library stands in for librar_native.so here.
    ArchiveExtractService.linuxRarPath = Platform.isMacOS ? '/usr/lib/libSystem.B.dylib' : 'libc.so.6';
    expect(ArchiveExtractService.rarSupported(overrideOs: 'linux'), true);
    expect(RarPlatform.instance, isA<RarFfi>());
  });

  test('linux: the load result is cached', () {
    ArchiveExtractService.linuxRar = true;
    ArchiveExtractService.linuxRarPath = '/nonexistent/lib/librar_native.so';
    expect(ArchiveExtractService.rarSupported(overrideOs: 'linux'), true);
  });

  // CI builds librar_native.so and points RAR_NATIVE_LIB at it; skipped elsewhere.
  final nativeLib = Platform.environment['RAR_NATIVE_LIB'];
  test('linux: extracts a real RAR through the native library', () async {
    ArchiveExtractService.linuxRarPath = nativeLib!;
    expect(ArchiveExtractService.rarSupported(), true);

    final dir = Directory.systemTemp.createTempSync('rar_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final out = p.join(dir.path, 'out');
    await service.extract('test/fixtures/sample.rar', out, onProgress: (_) {});
    expect(File(p.join(out, 'test.txt')).readAsStringSync(), 'test text document\r\n');
    expect(File(p.join(out, 'testdir', 'test.txt')).existsSync(), true);

    final listed = await Rar.listRarContents(rarFilePath: 'test/fixtures/sample.rar');
    expect(listed['success'], true, reason: '${listed['message']}');
    expect(listed['files'], contains('test.txt'));
  }, skip: !Platform.isLinux || nativeLib == null ? 'needs Linux and RAR_NATIVE_LIB' : false);

  test('extract rejects RAR on unsupported platforms', () async {
    ArchiveExtractService.linuxRar = false;
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
