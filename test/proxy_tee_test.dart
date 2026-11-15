import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/link_download.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';

void main() {
  late HttpServer upstream;
  late HttpServer proxy;
  late Directory dir;
  late File saveTo;
  late File part;
  late Future<void> Function(HttpRequest) upstreamHandler;
  final body = List<int>.generate(100, (i) => i);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('proxy_tee');
    saveTo = File(p.join(dir.path, 'game.zip'));
    part = File('${saveTo.path}.part');
    upstreamHandler = (req) async {
      req.response.add(body);
      await req.response.close();
    };
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) => upstreamHandler(req));
    proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    proxy.listen((req) async {
      try {
        await TinfoilServerService.proxyUpstream(
          req,
          url: 'http://127.0.0.1:${upstream.port}/game.zip',
          headers: const {},
          saveTo: saveTo,
        );
      } catch (_) {
        // Stand-in for _handle's catch, which answers the client.
        await req.response.close().catchError((_) {});
      }
    });
  });

  tearDown(() async {
    await proxy.close(force: true);
    await upstream.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<(int, List<int>)> fetch({String? range}) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:${proxy.port}/'));
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      final res = await req.close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      return (res.statusCode, bytes);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> waitUntil(bool Function() cond) async {
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (!cond() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('full 200 download is saved', () async {
    final (status, bytes) = await fetch();
    expect(status, 200);
    expect(bytes, body);
    await waitUntil(() => saveTo.existsSync());
    expect(saveTo.readAsBytesSync(), body);
    expect(part.existsSync(), isFalse);
  });

  test('range request is proxied but not saved', () async {
    upstreamHandler = (req) async {
      req.response.statusCode = 206;
      req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 10-19/100');
      req.response.add(body.sublist(10, 20));
      await req.response.close();
    };
    final (status, bytes) = await fetch(range: 'bytes=10-19');
    expect(status, 206);
    expect(bytes, body.sublist(10, 20));
    expect(saveTo.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('upstream error saves nothing', () async {
    upstreamHandler = (req) async {
      req.response.statusCode = 403;
      await req.response.close();
    };
    final (status, _) = await fetch();
    expect(status, 502);
    expect(saveTo.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('short body is discarded', () async {
    upstreamHandler = (req) async {
      req.response.contentLength = 100;
      // Headers go out with the detach; the body is then cut short by hand.
      final socket = await req.response.detachSocket();
      socket.add(body.sublist(0, 50));
      await socket.flush();
      socket.destroy();
    };
    try {
      await fetch();
    } catch (_) {}
    await waitUntil(() => !part.existsSync());
    expect(saveTo.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('client disconnect discards the part', () async {
    // Dart only notices a dead client when writes start failing, so send
    // enough after the disconnect to fill the socket buffers.
    final chunk = List<int>.filled(1 << 20, 7);
    upstreamHandler = (req) async {
      req.response.add(chunk);
      await req.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        for (var i = 0; i < 32; i++) {
          req.response.add(chunk);
          await req.response.flush();
        }
        await req.response.close();
      } catch (_) {}
    };
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${proxy.port}/'));
    final res = await req.close();
    await res.first;
    client.close(force: true);
    await waitUntil(() => !part.existsSync());
    expect(saveTo.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('unwritable save location still serves the client', () async {
    saveTo = File(p.join(dir.path, 'missing', 'game.zip'));
    final (status, bytes) = await fetch();
    expect(status, 200);
    expect(bytes, body);
    expect(Directory(p.join(dir.path, 'missing')).existsSync(), isFalse);
  });

  test('a stale part from a killed run is overwritten and the download saved', () async {
    part.writeAsStringSync('x');
    final (status, bytes) = await fetch();
    expect(status, 200);
    expect(bytes, body);
    await waitUntil(() => saveTo.existsSync());
    expect(saveTo.readAsBytesSync(), body);
    expect(part.existsSync(), isFalse);
  });

  test("a link download's part is left alone", () async {
    expect(reserveDownloadPath(dir.path, 'game.zip'), saveTo.path);
    part.writeAsStringSync('x');
    final (status, bytes) = await fetch();
    expect(status, 200);
    expect(bytes, body);
    expect(part.readAsStringSync(), 'x');
    expect(saveTo.existsSync(), isFalse);
  });

  test('two concurrent full downloads save exactly one correct file', () async {
    upstreamHandler = (req) async {
      req.response.contentLength = body.length;
      req.response.add(body.sublist(0, 50));
      await req.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      req.response.add(body.sublist(50));
      await req.response.close();
    };
    final results = await Future.wait([fetch(), fetch()]);
    for (final (status, bytes) in results) {
      expect(status, 200);
      expect(bytes, body);
    }
    await waitUntil(() => saveTo.existsSync() && !part.existsSync());
    expect(saveTo.readAsBytesSync(), body);
    expect(dir.listSync().map((e) => p.basename(e.path)), ['game.zip']);
  });

  test('a compressed body reaches the client intact but is not saved', () async {
    upstreamHandler = (req) async {
      final gz = gzip.encode(body);
      req.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      req.response.contentLength = gz.length;
      req.response.add(gz);
      await req.response.close();
    };
    final (status, bytes) = await fetch(); // HttpClient decodes gzip
    expect(status, 200);
    expect(bytes, body);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(saveTo.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('an HTML page is proxied but not saved', () async {
    upstreamHandler = (req) async {
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html>sign in</html>');
      await req.response.close();
    };
    final (status, _) = await fetch();
    expect(status, 200);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(saveTo.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });
}
