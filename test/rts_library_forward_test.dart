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
  late String downloadDir;
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
    downloadDir = p.join(dir.path, 'dl');
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      seen.add(req);
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
        downloadDir: (_) => downloadDir,
      ),
    );
    Directory(p.join(dir.path, 'dl')).createSync();
    File(p.join(dir.path, 'dl', 'a.zip')).writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() async {
    // The hub finishes its copy after the client has its bytes.
    for (var i = 0; i < 500 && rts.activeTransfers.value > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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

  test('localFiles matches exact name and a single unpacked file', () {
    final d = Directory(p.join(dir.path, 'm'))..createSync();
    for (final n in ['a.zip', 'b.gbc', 'c.cue', 'c.bin', 'e.sav', 'f.gbc', 'f.sav']) {
      File(p.join(d.path, n)).writeAsStringSync('x');
    }
    final gs = [for (final n in ['a.zip', 'b.zip', 'c.zip', 'd.zip', 'e.zip', 'f.zip']) game(n, 1)];
    final any = RtsServerService.localFiles(gs, d.path, const []);
    expect(any['a.zip'], endsWith('a.zip'));
    expect(any['b.zip'], endsWith('b.gbc'));
    expect(any.containsKey('c.zip'), isFalse);
    expect(any.containsKey('d.zip'), isFalse);
    // A lone save file is not the game; with formats known it is ignored.
    final gbc = RtsServerService.localFiles(gs, d.path, const ['.GBC']);
    expect(gbc.containsKey('e.zip'), isFalse);
    expect(gbc['f.zip'], endsWith('f.gbc'));
    expect(RtsServerService.localFiles(gs, p.join(dir.path, 'missing'), const []), isEmpty);
    expect(RtsServerService.localFiles(gs, null, const []), isEmpty);
  });

  test('listing announces local files', () {
    final gs = games.take(2).toList();
    final l = RtsServerService.forwardedListing(gs, RtsServerService.localFiles(gs, downloadDir, const []));
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

  test('server: unknown console, unknown game, path escape, non-game file -> 404', () async {
    File(p.join(dir.path, 'secret.txt')).writeAsStringSync('s');
    File(p.join(downloadDir, 'notes.txt')).writeAsStringSync('n');
    File(p.join(downloadDir, 'd.zip.part')).writeAsStringSync('p');
    Directory(p.join(downloadDir, 'sub')).createSync();
    File(p.join(downloadDir, 'sub', 'x.zip')).writeAsStringSync('x');
    for (final path in [
      '/lib/nope/',
      '/lib/gb/zzz.zip',
      '/lib/gb/..%2F..%2Fetc%2Fpasswd',
      '/lib/gb/..%2Fsecret.txt',
      '/lib/gb/notes.txt',
      '/lib/gb/d.zip.part',
      '/lib/gb/sub/x.zip',
      '/lib/gb/sub%2Fx.zip',
    ]) {
      expect((await get(path)).$1, 404, reason: path);
    }
  });

  test('server: no download folder set -> proxied, nothing read or written locally', () async {
    // An empty path resolves to the working directory: point it somewhere harmless.
    final cwd = Directory.current;
    Directory.current = dir;
    addTearDown(() => Directory.current = cwd);
    downloadDir = '';
    final cwdFile = File(p.join(dir.path, 'probe.zip'))..writeAsBytesSync([5]);
    games.add(game('probe.zip', 100));
    final (_, lb) = await get('/lib/gb/');
    expect((jsonDecode(utf8.decode(lb)) as List).last, {'name': 'probe.zip', 'size': 100});
    var (s, b) = await get('/lib/gb/probe.zip');
    expect(s, 200);
    expect(b, body);
    expect(cwdFile.readAsBytesSync(), [5]);
    (s, b) = await get('/lib/gb/d.zip');
    expect(b, body);
    for (var i = 0; i < 50 && rts.activeTransfers.value > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(File(p.join(dir.path, 'd.zip')).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'd.zip.part')).existsSync(), isFalse);
  });

  test('server: an uncreatable download folder still streams the game', () async {
    File(p.join(dir.path, 'blocker')).writeAsStringSync('');
    downloadDir = p.join(dir.path, 'blocker', 'dl');
    final (s, b) = await get('/lib/gb/d.zip');
    expect(s, 200);
    expect(b, body);
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
