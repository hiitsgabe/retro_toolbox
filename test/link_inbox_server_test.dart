import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/link_inbox_server.dart';

void main() {
  late LinkInboxServer server;
  final client = HttpClient();

  setUp(() async {
    server = LinkInboxServer();
    await server.start(0);
  });
  tearDown(() => server.stop());

  Future<HttpClientResponse> post(String body, {String type = 'application/x-www-form-urlencoded'}) async {
    final req = await client.post('127.0.0.1', server.port!, '/link');
    req.headers.set(HttpHeaders.contentTypeHeader, type);
    req.add(utf8.encode(body));
    final res = await req.close();
    await res.drain<void>();
    return res;
  }

  test('GET / serves the page', () async {
    final res = await (await client.get('127.0.0.1', server.port!, '/')).close();
    final body = await utf8.decodeStream(res);
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'text/html');
    expect(body, contains('Send to handheld'));
    expect(body, contains('#17102B'));
  });

  test('other paths are 404', () async {
    final res = await (await client.get('127.0.0.1', server.port!, '/nope')).close();
    await res.drain<void>();
    expect(res.statusCode, 404);
  });

  test('POST /link with a valid url emits it', () async {
    final first = server.links.first;
    final res = await post('url=https%3A%2F%2Fh%2Fa.zip');
    expect(res.statusCode, 200);
    expect(await first.timeout(const Duration(seconds: 2)), 'https://h/a.zip');
  });

  test('POST /link accepts a plain-text body', () async {
    final first = server.links.first;
    final res = await post('https://h/b.zip', type: 'text/plain');
    expect(res.statusCode, 200);
    expect(await first.timeout(const Duration(seconds: 2)), 'https://h/b.zip');
  });

  test('invalid or oversized posts are rejected and emit nothing', () async {
    final seen = <String>[];
    final sub = server.links.listen(seen.add);
    expect((await post('url=')).statusCode, 400);
    expect((await post('url=ftp%3A%2F%2Fh')).statusCode, 400);
    expect((await post('url=https%3A%2F%2Fh%2Fa%20b')).statusCode, 400);
    expect((await post('url=%ZZ')).statusCode, 400);
    expect((await post('url=${'a' * 9000}')).statusCode, 413);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(seen, isEmpty);
    await sub.cancel();
  });

  test('a chunked body over the limit is cut off with 413', () async {
    final req = await client.post('127.0.0.1', server.port!, '/link');
    req.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
    req.contentLength = -1; // chunked: no Content-Length to check up front
    for (var i = 0; i < 4; i++) {
      req.add(utf8.encode('https://h/${'a' * 3000}'));
    }
    final res = await req.close();
    await res.drain<void>();
    expect(res.statusCode, 413);
  });

  test('stop closes the port', () async {
    final port = server.port!;
    expect(server.running, isTrue);
    await server.stop();
    expect(server.running, isFalse);
    expect(server.port, isNull);
    await expectLater(Socket.connect('127.0.0.1', port), throwsA(isA<SocketException>()));
  });
}
