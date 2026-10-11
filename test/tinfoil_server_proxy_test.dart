import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';

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

  test('follows redirects with the data request: a one-use storage link is hit once', () async {
    // The game URL redirects to a storage link that only works once (a probe
    // before the real request would burn it).
    final storage = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => storage.close(force: true));
    var storageHits = 0;
    storage.listen((req) async {
      storageHits++;
      if (storageHits > 1) {
        req.response.statusCode = 403;
      } else {
        req.response.statusCode = 206;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-3/100');
        req.response.add([1, 2, 3, 4]);
      }
      await req.response.close();
    });
    final api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => api.close(force: true));
    api.listen((req) async {
      req.response.statusCode = HttpStatus.found;
      req.response.headers.set(HttpHeaders.locationHeader, 'http://127.0.0.1:${storage.port}/once');
      await req.response.close();
    });

    final console = Console(id: 'switch', name: 'Switch', urls: const [], fileFormat: const ['.nsz']);
    final game = Game(title: 'Game.nsz', url: 'http://127.0.0.1:${api.port}/dl', size: 100, consoleId: 'switch');
    await service.start(port: 0, loadGames: () async => {console: [game]}, authHeaders: (c) => {'Authorization': 'Bearer tok123'});
    final client = HttpClient();
    addTearDown(client.close);
    await (await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}/'))).close().then((r) => r.drain<void>());
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}/dl/switch/0/Game.nsz'));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
    final res = await req.close();
    expect(res.statusCode, 206);
    expect(await res.fold<List<int>>([], (a, b) => a..addAll(b)), [1, 2, 3, 4]);
    expect(storageHits, 1);
  });

  test('a game already in the download folder is listed and served from disk', () async {
    final dir = Directory.systemTemp.createTempSync('tinfoil_local');
    addTearDown(() => dir.deleteSync(recursive: true));
    // The catalog's .nsz was downloaded and decompressed to .nsp here.
    File('${dir.path}/Game.nsp').writeAsBytesSync(List.generate(50, (i) => 200 - i));
    final console = Console(id: 'switch', name: 'Switch', urls: const [], fileFormat: const ['.nsz']);
    // API-style URL with no file name: the file is named after the title.
    final game = Game(title: 'Game.nsz', url: 'http://127.0.0.1:${upstream.port}/download/0100000000001000/base', size: 100, consoleId: 'switch');
    await service.start(
      port: 0,
      loadGames: () async => {console: [game]},
      authHeaders: (c) => {'Authorization': 'Bearer tok123'},
      downloadDir: (c) => dir.path,
    );
    final client = HttpClient();
    addTearDown(client.close);
    final index = await (await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}/'))).close();
    final file = (jsonDecode(await index.transform(utf8.decoder).join())['files'] as List).single;
    expect(file['size'], 50);
    expect(file['url'], endsWith('/dl/switch/0/Game%20%5B0100000000001000%5D.nsp')); // local extension, title ID kept

    final req = await client.getUrl(Uri.parse(file['url'] as String));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-14');
    final res = await req.close();
    expect(res.statusCode, 206);
    expect(res.headers.value(HttpHeaders.contentRangeHeader), 'bytes 10-14/50');
    expect(await res.fold<List<int>>([], (a, b) => a..addAll(b)), [190, 189, 188, 187, 186]);

    final whole = await (await client.getUrl(Uri.parse(file['url'] as String))).close();
    expect(whole.statusCode, 200);
    expect((await whole.fold<List<int>>([], (a, b) => a..addAll(b))).length, 50);
  });

  test('File Browser folders: Fast install lists only games on the device', () async {
    final dir = Directory.systemTemp.createTempSync('tinfoil_folders');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/Here.nsp').writeAsBytesSync([1, 2, 3]);
    final console = Console(id: 'switch', name: 'Switch', urls: const [], fileFormat: const ['.nsz']);
    final here = Game(title: 'Here.nsz', url: 'http://127.0.0.1:${upstream.port}/download/0100000000001000/base', size: 100, consoleId: 'switch');
    final away = Game(title: 'Away.nsz', url: 'http://127.0.0.1:${upstream.port}/download/0100000000002000/base', size: 100, consoleId: 'switch');
    await service.start(port: 0, loadGames: () async => {console: [here, away]}, authHeaders: (c) => {}, downloadDir: (c) => dir.path);
    final client = HttpClient();
    addTearDown(client.close);
    Future<Map<String, dynamic>> index(String path) async =>
        jsonDecode(await (await (await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}$path'))).close()).transform(utf8.decoder).join());

    final root = await index('/');
    expect((root['files'] as List).length, 2); // New Games still sees everything
    expect(root['directories'], ['http://127.0.0.1:${service.port}/Fast%20install/', 'http://127.0.0.1:${service.port}/All%20games/']);

    final fast = await index('/Fast%20install/');
    expect((fast['files'] as List).map((f) => f['url']), [endsWith('Here%20%5B0100000000001000%5D.nsp')]);
    expect(fast.containsKey('directories'), isFalse);

    final all = await index('/All%20games/');
    expect((all['files'] as List).length, 2);
  });

  test('unknown route 404s', () async {
    await startService();
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:${service.port}/nope'))).close();
    expect(res.statusCode, 404);
    client.close();
  });
}
