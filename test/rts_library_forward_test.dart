import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/rts_folder_model.dart';
import 'package:retro_toolbox/services/rts_server_service.dart';

const console = Console(
  id: 'gb',
  name: 'GB',
  urls: [],
  originalFormat: ['.zip'],
  decompress: Decompress.unzip,
  auth: {'type': 'bearer', 'token': 'secret'},
);

void main() {
  late Directory dir;
  late HttpServer upstream;
  late List<HttpRequest> seen;
  late RtsServerService rts;
  late List<Game> games;
  final body = List<int>.generate(100, (i) => i);

  Game game(String name, int size) => Game(
        title: name,
        url: 'http://127.0.0.1:${upstream.port}/${Uri.encodeComponent(name)}',
        size: size,
        consoleId: 'gb',
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rts_lib');
    seen = [];
    final seenAuth = <String?>[];
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      seen.add(req);
      seenAuth.add(req.headers.value('x-test-auth'));
      req.response.add(body);
      await req.response.close();
    });
    games = [game('a.zip', 999), game('d.zip', 7), game('Alpha & Beta (USA).zip', 100)];
    rts = RtsServerService();
    await rts.start(
      port: 0,
      folders: [const RtsFolder(name: 'F', path: '/nonexistent', romsSubfolder: 'r')],
      library: RtsLibrary(
        consoles: () async => {'gb': console},
        games: (_) async => games,
        authHeaders: (_) => {'x-test-auth': 'hub'},
        downloadDir: (_) => p.join(dir.path, 'dl'),
      ),
    );
    Directory(p.join(dir.path, 'dl')).createSync();
    File(p.join(dir.path, 'dl', 'a.zip')).writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() async {
    await rts.stop();
    await upstream.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<(int, List<int>)> get(String path) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:${rts.port}$path'))).close();
      return (res.statusCode, await res.fold<List<int>>([], (a, b) => a..addAll(b)));
    } finally {
      client.close(force: true);
    }
  }

  test('forwarded console carries no auth and points at the hub', () {
    final j = RtsServerService.forwardedConsoleJson(console, '10.0.0.2:9093');
    for (final k in ['auth', 'regex', 'list_url', 'download_url', 'id']) {
      expect(j.containsKey(k), isFalse, reason: k);
    }
    expect(j['url'], 'http://10.0.0.2:9093/lib/gb/');
    expect(j['ignore_extension_filtering'], true);
    expect(j['decompress'], 'unzip');
  });

  test('localFileFor matches exact name and a single unpacked file', () {
    final d = Directory(p.join(dir.path, 'm'))..createSync();
    for (final n in ['a.zip', 'b.gbc', 'c.cue', 'c.bin']) {
      File(p.join(d.path, n)).writeAsStringSync('x');
    }
    expect(RtsServerService.localFileFor(d.path, 'a.zip'), endsWith('a.zip'));
    expect(RtsServerService.localFileFor(d.path, 'b.zip'), endsWith('b.gbc'));
    expect(RtsServerService.localFileFor(d.path, 'c.zip'), isNull);
    expect(RtsServerService.localFileFor(d.path, 'd.zip'), isNull);
    expect(RtsServerService.localFileFor(p.join(dir.path, 'missing'), 'a.zip'), isNull);
  });

  test('listing announces local files', () {
    final l = RtsServerService.forwardedListing(games.take(2).toList(), p.join(dir.path, 'dl'));
    expect(l, [(name: 'a.zip', size: 3), (name: 'd.zip', size: 7)]);
  });

  test('server: consoles.json lists folders then library', () async {
    final (s, b) = await get('/consoles.json');
    final list = jsonDecode(utf8.decode(b)) as List;
    expect(s, 200);
    expect(list, hasLength(2));
    expect(list[1]['url'], endsWith('/lib/gb/'));
  });

  test('server: local game served from disk, missing game proxied and saved', () async {
    var (s, b) = await get('/lib/gb/a.zip');
    expect(s, 200);
    expect(b, [1, 2, 3]);
    expect(seen, isEmpty);
    (s, b) = await get('/lib/gb/d.zip');
    expect(s, 200);
    expect(b, body);
    expect(seen.single.headers.value('x-test-auth'), 'hub');
    final saved = File(p.join(dir.path, 'dl', 'd.zip'));
    for (var i = 0; i < 100 && !saved.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(saved.readAsBytesSync(), body);
  });

  test('server: proxied download creates a missing download dir', () async {
    Directory(p.join(dir.path, 'dl')).deleteSync(recursive: true);
    final (s, b) = await get('/lib/gb/d.zip');
    expect(s, 200);
    expect(b, body);
  });

  test('server: names with spaces and & round-trip', () async {
    const name = 'Alpha & Beta (USA).zip';
    final (_, lb) = await get('/lib/gb/');
    expect((jsonDecode(utf8.decode(lb)) as List).map((e) => e['name']), contains(name));
    final (s, b) = await get('/lib/gb/${Uri.encodeComponent(name)}');
    expect(s, 200);
    expect(b, body);
  });

  test('server: unknown console, unknown game, path escape -> 404', () async {
    File(p.join(dir.path, 'secret.txt')).writeAsStringSync('s');
    for (final path in ['/lib/nope/', '/lib/gb/zzz.zip', '/lib/gb/..%2F..%2Fetc%2Fpasswd', '/lib/gb/..%2Fsecret.txt']) {
      expect((await get(path)).$1, 404, reason: path);
    }
  });

  test('server: a literal % in a name is not decoded twice', () async {
    games.add(game('100% Pure.zip', 100));
    var (s, b) = await get('/lib/gb/${Uri.encodeComponent('100% Pure.zip')}');
    expect(s, 200);
    expect(b, body);

    final folder = Directory(p.join(dir.path, 'f'))..createSync();
    File(p.join(folder.path, '100% Pure.zip')).writeAsBytesSync([9]);
    File(p.join(folder.path, '%41.zip')).writeAsBytesSync([7]);
    final other = RtsServerService();
    await other.start(port: 0, folders: [RtsFolder(name: 'F', path: folder.path, romsSubfolder: 'r')]);
    addTearDown(other.stop);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    for (final (name, byte) in [('100% Pure.zip', 9), ('%41.zip', 7)]) {
      final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:${other.port}/f/0/${Uri.encodeComponent(name)}'))).close();
      expect(res.statusCode, 200, reason: name);
      expect(await res.fold<List<int>>([], (a, c) => a..addAll(c)), [byte], reason: name);
    }
  });
}
