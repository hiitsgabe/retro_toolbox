import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/drive_transport.dart';

// Plain test() only: TestWidgetsFlutterBinding answers every HttpClient request
// with 400, loopback included, so this file must never initialize it.
void main() {
  late HttpServer server;
  late List<String> seen;
  late Future<void> Function(HttpResponse res) answer;

  setUp(() async {
    seen = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decodeStream(req);
      seen.add('${req.method} ${req.uri} auth=${req.headers.value('authorization')} type=${req.headers.value('content-type')} body=$body');
      await answer(req.response);
      await req.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  Uri url(String path, [Map<String, String>? query]) => Uri.parse('http://127.0.0.1:${server.port}$path').replace(queryParameters: query);

  test('sends method, query, headers and body; returns status, lower-case headers and body', () async {
    answer = (res) async {
      res.statusCode = 201;
      res.headers.set('Location', 'http://127.0.0.1/session?upload_id=7');
      res.write('{"id":"f1"}');
    };
    final r = await HttpDriveTransport().send(DriveRequest(
      'POST',
      url('/drive/v3/files', {'q': "'root' in parents and trashed = false", 'pageSize': '1000'}),
      headers: {'Authorization': 'Bearer t1', 'Content-Type': 'application/json; charset=UTF-8'},
      body: utf8.encode('{"name":"a"}'),
    ));
    expect(seen.single, "POST /drive/v3/files?q=%27root%27+in+parents+and+trashed+%3D+false&pageSize=1000 auth=Bearer t1 "
        'type=application/json; charset=UTF-8 body={"name":"a"}');
    expect(r.status, 201);
    expect(r.ok, isTrue);
    expect(r.headers['location'], 'http://127.0.0.1/session?upload_id=7');
    expect(r.json, {'id': 'f1'});
  });

  test('an error page that is not JSON keeps its status and reads as null JSON', () async {
    answer = (res) async {
      res.statusCode = 502;
      res.write('<html>Bad Gateway</html>');
    };
    final r = await HttpDriveTransport().send(DriveRequest('GET', url('/drive/v3/files/f1', {'alt': 'media'})));
    expect(seen.single, 'GET /drive/v3/files/f1?alt=media auth=null type=null body=');
    expect(r.status, 502);
    expect(r.ok, isFalse);
    expect(r.json, isNull);
    expect(utf8.decode(r.body), '<html>Bad Gateway</html>');
  });

  group('the idle time', () {
    const idle = Duration(milliseconds: 300);

    Future<ServerSocket> serve() async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(s.close);
      return s;
    }

    Uri at(int port, String path) => Uri.parse('http://127.0.0.1:$port$path');

    test('an upload the server stops taking is cut off and its connection closed', () async {
      final raw = await serve();
      final subs = <StreamSubscription<Uint8List>>[];
      final closed = Completer<void>();
      var got = 0;
      raw.listen((s) => subs.add(s.listen((d) => got += d.length, onDone: closed.complete, onError: (_) => closed.complete())..pause()));
      final body = Uint8List(32 << 20);
      await expectLater(
        HttpDriveTransport(idle: idle).send(DriveRequest('POST', at(raw.port, '/upload/drive/v3/files'), body: body)),
        throwsA(isA<DriveNetworkError>().having((e) => e.cause, 'cause', isA<TimeoutException>())),
      );
      subs.single.resume();
      await closed.future.timeout(const Duration(seconds: 5));
      expect(got, lessThan(body.length), reason: 'the rest of the body was never sent');
    });

    test('a slow upload that keeps moving has no deadline', () async {
      final server = await RawServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final body = Uint8List(32 << 20);
      server.listen((s) {
        s.readEventsEnabled = false;
        s.listen((_) {});
        var got = 0;
        int? need;
        // 2 MB every 100 ms: the whole body takes far longer than the idle time, no pause is as long.
        Timer.periodic(const Duration(milliseconds: 100), (t) {
          for (var n = 0; n < 2 << 20;) {
            final d = s.read(min(1 << 16, (2 << 20) - n));
            if (d == null || d.isEmpty) break;
            need ??= latin1.decode(d).indexOf('\r\n\r\n') + 4 + body.length;
            n += d.length;
            got += d.length;
          }
          if (need == null || got < need!) return;
          t.cancel();
          s.write(utf8.encode('HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}'));
        });
      });
      final watch = Stopwatch()..start();
      final r = await HttpDriveTransport(idle: idle).send(DriveRequest('POST', at(server.port, '/upload/drive/v3/files'), body: body));
      expect(watch.elapsed, greaterThan(idle * 2), reason: 'longer than the idle time in all');
      expect(r.json, <String, Object?>{});
    });

    test('a response that stops coming is cut off and its connection closed', () async {
      final raw = await serve();
      final closed = Completer<void>();
      raw.listen((s) {
        var answered = false;
        s.listen((_) {
          if (answered) return;
          answered = true;
          s.write('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n0123456789');
        }, onDone: closed.complete, onError: (_) => closed.complete());
      });
      await expectLater(
        HttpDriveTransport(idle: idle).send(DriveRequest('GET', at(raw.port, '/drive/v3/files/f1'))),
        throwsA(isA<DriveNetworkError>().having((e) => e.cause, 'cause', isA<TimeoutException>())),
      );
      await closed.future.timeout(const Duration(seconds: 5));
    });

    test('a slow response that keeps coming has no deadline', () async {
      final raw = await serve();
      raw.listen((s) {
        var answered = false;
        s.listen((_) async {
          if (answered) return;
          answered = true;
          s.write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n');
          for (var i = 0; i < 6; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            s.write('$i');
          }
        });
      });
      final watch = Stopwatch()..start();
      final r = await HttpDriveTransport(idle: idle).send(DriveRequest('GET', at(raw.port, '/drive/v3/files/f1')));
      expect(watch.elapsed, greaterThan(idle), reason: 'longer than the idle time in all');
      expect(utf8.decode(r.body), '012345');
    });

    test('a refused connection is a network error', () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final url = at(raw.port, '/drive/v3/files');
      await raw.close();
      await expectLater(
        HttpDriveTransport(idle: idle).send(DriveRequest('GET', url)),
        throwsA(isA<DriveNetworkError>().having((e) => e.cause, 'cause', isA<SocketException>())),
      );
    });
  });
}
