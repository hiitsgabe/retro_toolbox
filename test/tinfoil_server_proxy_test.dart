import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';

void main() {
  late HttpServer upstream;
  late TinfoilServerService service;

  setUp(() async {
    // Fake upstream: asserts auth header arrives, honors Range with 206.
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      if (req.headers.value('Authorization') != 'Bearer tok123') {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final body = List<int>.generate(100, (i) => i);
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        final from = int.parse(m.group(1)!);
        final to = m.group(2)!.isEmpty ? 99 : int.parse(m.group(2)!);
        req.response.statusCode = 206;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $from-$to/100');
        req.response.add(body.sublist(from, to + 1));
      } else {
        req.response.add(body);
      }
      await req.response.close();
    });
    service = TinfoilServerService();
  });

  tearDown(() async {
    await service.stop();
    await upstream.close(force: true);
  });

  Future<void> startService() async {
    final console = Console(id: 'switch', name: 'Switch', urls: const [], fileFormat: const ['.nsz']);
    final game = Game(title: 'Game.nsz', url: 'http://127.0.0.1:${upstream.port}/file.nsz', size: 100, consoleId: 'switch');
    await service.start(
      port: 0, // ephemeral for tests
      loadGames: () async => {console: [game]},
      authHeaders: (c) => {'Authorization': 'Bearer tok123'},
    );
  }

  test('serves tinfoil index at /', () async {
    await startService();
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}/'))).close();
    expect(res.statusCode, 200);
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    expect((data['files'] as List).single['size'], 100);
    client.close();
  });

  test('proxies /dl with auth and Range passthrough', () async {
    await startService();
    final client = HttpClient();
    // Index hit populates the route map.
    await (await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}/'))).close().then((r) => r.drain<void>());
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}/dl/switch/0/Game.nsz'));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');
    final res = await req.close();
    expect(res.statusCode, 206);
    expect(res.headers.value(HttpHeaders.contentRangeHeader), 'bytes 10-19/100');
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(bytes, List.generate(10, (i) => 10 + i));
    client.close();
  });

  test('unknown route 404s', () async {
    await startService();
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}/nope'))).close();
    expect(res.statusCode, 404);
    client.close();
  });
}
