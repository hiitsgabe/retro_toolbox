import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/link_download.dart';

void main() {
  test('isValidDownloadUrl accepts http(s) with a host only', () {
    expect(isValidDownloadUrl('https://h.example/a.zip'), isTrue);
    expect(isValidDownloadUrl('  http://h/a  '), isTrue);
    for (final bad in ['', 'ftp://h/a', 'https:///a', 'https://h/a b.zip']) {
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
  });

  group('network', () {
    late HttpServer server;
    late Directory tmp;
    late Uint8List source;
    var honourRange = true;
    var status = 200;
    String? lastRange;
    String url() => 'http://127.0.0.1:${server.port}/f.bin';

    setUp(() async {
      honourRange = true;
      status = 200;
      lastRange = null;
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

    test('an existing destination is not overwritten', () async {
      final dest = '${tmp.path}/out.bin';
      File(dest).writeAsStringSync('old');
      await downloadToFile(url: url(), destPath: dest, onProgress: (_, __) {});
      expect(File(dest).readAsStringSync(), 'old');
      expect(File('${tmp.path}/out (1).bin').readAsBytesSync(), source);
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
