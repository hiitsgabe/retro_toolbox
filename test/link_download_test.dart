import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/link_download.dart';

void main() {
  test('isValidDownloadUrl accepts http(s) with a host only', () {
    expect(isValidDownloadUrl('https://h.example/a.zip'), isTrue);
    expect(isValidDownloadUrl('  http://h/a  '), isTrue);
    for (final bad in ['', 'ftp://h/a', 'https:///a', 'https://h/a b.zip', 'https://h/a\x00b', 'https://h/a\x07b', 'https://h/a\u202eb']) {
      expect(isValidDownloadUrl(bad), isFalse, reason: bad);
    }
  });

  test('file names are sanitised', () {
    expect(fileNameFromContentDisposition('attachment; filename="../x.zip"'), 'x.zip');
    expect(fileNameFromContentDisposition("attachment; filename*=UTF-8''a%20b.zip"), 'a b.zip');
    expect(fileNameFromContentDisposition('attachment; filename="a/b.zip"'), 'b.zip');
    expect(fileNameFromContentDisposition("attachment; filename=\"old.zip\"; filename*=UTF-8''new.zip"), 'new.zip');
    expect(fileNameFromContentDisposition(null), isNull);
    expect(safeFileName('???'), 'download');
    expect(safeFileName('..'), 'download');
    expect(safeFileName('a:b\u0001.zip'), 'a_b.zip');
    expect(fileNameFromUrl('https://h/dir/game%20pack.zip?x=1'), 'game pack.zip');
    expect(fileNameFromUrl('https://h/'), 'download');
    expect(fileNameFromUrl('https://h/%FF'), '%FF');
    expect(fileNameFromUrl('https://h/a%C3'), 'a%C3');
    // not UTF-8: no throw, falls back to the plain name (or null)
    expect(fileNameFromContentDisposition("attachment; filename*=ISO-8859-1''caf%E9.zip; filename=\"cafe.zip\""), 'cafe.zip');
    expect(fileNameFromContentDisposition("attachment; filename*=ISO-8859-1''caf%E9.zip"), isNull);
  });

  test('leading dots are dropped so a saved file is never hidden', () {
    expect(safeFileName('.profile'), 'profile');
    expect(safeFileName(' . x.zip'), 'x.zip');
    expect(safeFileName('...'), 'download');
  });

  test('reserveDownloadPath skips names with a leftover .part or held by another download', () {
    final dir = Directory.systemTemp.createTempSync('reserve');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/a.zip.part').writeAsStringSync('some other file');
    expect(p.basename(reserveDownloadPath(dir.path, 'a.zip')), 'a (1).zip');
    expect(p.basename(reserveDownloadPath(dir.path, 'a.zip')), 'a (2).zip');
  });

  test('a stalled response times out and keeps the .part for a retry', () async {
    final stall = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => stall.close(force: true));
    stall.listen((req) async {
      if (req.uri.path == '/headers') return; // never answers
      req.response.contentLength = 100000;
      req.response.add(List.filled(20000, 1)); // big enough that the server really flushes it
      await req.response.flush(); // then stalls
    });
    final dir = Directory.systemTemp.createTempSync('link_stall');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<void> get(String path, String dest) =>
        downloadToFile(url: 'http://127.0.0.1:${stall.port}$path', destPath: dest, onProgress: (_, __) {}, idleTimeout: const Duration(milliseconds: 300));
    await expectLater(get('/headers', '${dir.path}/h.bin'), throwsA(isA<TimeoutException>()));
    await expectLater(get('/body', '${dir.path}/b.bin'), throwsA(isA<TimeoutException>()));
    expect(File('${dir.path}/b.bin.part').lengthSync(), 20000);
  }, timeout: const Timeout(Duration(seconds: 10)));

  group('network', () {
    late HttpServer server;
    late Directory tmp;
    late Uint8List source;
    var honourRange = true;
    var status = 200;
    String? lastRange;
    String? lastEncoding;
    String url() => 'http://127.0.0.1:${server.port}/f.bin';

    setUp(() async {
      honourRange = true;
      status = 200;
      lastRange = null;
      lastEncoding = null;
      source = Uint8List.fromList(List.generate(1000, (i) => i % 251));
      tmp = await Directory.systemTemp.createTemp('link_dl');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final res = req.response;
        if (status != 200) {
          res.statusCode = status;
          await res.close();
          return;
        }
        res.headers.set('content-disposition', 'attachment; filename="served.bin"');
        lastRange = req.headers.value('range');
        lastEncoding = req.headers.value('accept-encoding');
        final m = lastRange == null ? null : RegExp(r'bytes=(\d+)-').firstMatch(lastRange!);
        if (m != null && honourRange) {
          final from = int.parse(m.group(1)!);
          res.statusCode = 206;
          res.contentLength = source.length - from;
          if (req.method != 'HEAD') res.add(source.sublist(from));
        } else {
          res.contentLength = source.length;
          if (req.method != 'HEAD') res.add(source);
        }
        await res.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await tmp.delete(recursive: true);
    });

    test('fresh download leaves no .part', () async {
      final dest = '${tmp.path}/out.bin';
      final seen = <List<int>>[];
      await downloadToFile(url: url(), destPath: dest, onProgress: (d, t) => seen.add([d, t]));
      expect(File(dest).readAsBytesSync(), source);
      expect(File('$dest.part').existsSync(), isFalse);
      expect(seen.last, [1000, 1000]);
    });

    test('asks for an uncompressed body so resume offsets match the file', () async {
      await downloadToFile(url: url(), destPath: '${tmp.path}/out.bin', onProgress: (_, __) {});
      expect(lastEncoding, 'identity');
    });

    test('resumes a .part when the server honours Range', () async {
      final dest = '${tmp.path}/out.bin';
      File('$dest.part').writeAsBytesSync(source.sublist(0, 400));
      final seen = <List<int>>[];
      await downloadToFile(url: url(), destPath: dest, onProgress: (d, t) => seen.add([d, t]));
      expect(lastRange, 'bytes=400-');
      expect(File(dest).readAsBytesSync(), source);
      expect(seen.last, [1000, 1000]);
    });

    test('restarts from zero when the server ignores Range', () async {
      honourRange = false;
      final dest = '${tmp.path}/out.bin';
      File('$dest.part').writeAsBytesSync(source.sublist(0, 400));
      await downloadToFile(url: url(), destPath: dest, onProgress: (_, __) {});
      expect(File(dest).readAsBytesSync(), source);
    });

    test('finishes at exactly destPath and never overwrites a file there', () async {
      final dest = '${tmp.path}/out.bin';
      File(dest).writeAsStringSync('old');
      await expectLater(downloadToFile(url: url(), destPath: dest, onProgress: (_, __) {}), throwsA(isA<StateError>()));
      expect(File(dest).readAsStringSync(), 'old');
      expect(File('${tmp.path}/out (1).bin').existsSync(), isFalse);
    });

    test('a job drops a leftover .part on its first run and resumes on a retry', () async {
      final dest = '${tmp.path}/out.bin';
      final job = downloadJob(url(), dest);
      File('$dest.part').writeAsBytesSync(List.filled(400, 7)); // some other file's
      status = 500;
      await expectLater(job((_, __) {}), throwsA(isA<HttpException>()));
      expect(File('$dest.part').existsSync(), isFalse);
      File('$dest.part').writeAsBytesSync(source.sublist(0, 400)); // what a failed run left
      status = 200;
      await job((_, __) {});
      expect(lastRange, 'bytes=400-');
      expect(File(dest).readAsBytesSync(), source);
    });

    test('a 404 throws and leaves the destination missing', () async {
      status = 404;
      final dest = '${tmp.path}/out.bin';
      await expectLater(downloadToFile(url: url(), destPath: dest, onProgress: (_, __) {}), throwsA(isA<HttpException>()));
      expect(File(dest).existsSync(), isFalse);
    });

    test('probeFileName reads Content-Disposition', () async {
      expect(await probeFileName(url()), 'served.bin');
    });

    test('probeFileName is null when the server says nothing useful', () async {
      status = 404;
      expect(await probeFileName(url()), isNull);
    });
  });
}
