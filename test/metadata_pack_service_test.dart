import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/metadata_pack_service.dart';

const packJson = '''
{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System",
 "built":"2026-09-10","games":[{"id":"snes/crystal-vanguard","title":"Crystal Vanguard",
 "dumps":[{"name":"Crystal Vanguard (USA)","crc":"2d206bf7"}]}]}
''';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('packs_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  MetadataPackService service() => MetadataPackService(
        cacheDir: tmp,
        fetch: (uri) async => throw StateError('network not allowed in this test'),
      );

  test('readCached returns null when nothing is on disk', () async {
    expect(await service().readCached('snes'), isNull);
  });

  test('writeCache writes and readCached reads it back', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    final pack = await svc.readCached('snes');
    expect(pack, isNotNull);
    expect(pack!.games.single.title, 'Crystal Vanguard');
    expect(await File(p.join(tmp.path, 'snes.json')).exists(), isTrue);
  });

  test('writeCache creates the directory when it does not exist', () async {
    final nested = Directory(p.join(tmp.path, 'a', 'b'));
    final svc = MetadataPackService(
        cacheDir: nested, fetch: (uri) async => throw StateError('no'));
    await svc.writeCache('snes', packJson);
    expect(await File(p.join(nested.path, 'snes.json')).exists(), isTrue);
  });

  test('readCached returns null and deletes the file when the JSON is corrupt',
      () async {
    final svc = service();
    final file = File(p.join(tmp.path, 'snes.json'));
    await file.create(recursive: true);
    await file.writeAsString('{ this is not json');
    expect(await svc.readCached('snes'), isNull);
    expect(await file.exists(), isFalse);
  });

  test('cachedPacks lists the ids on disk', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    await svc.writeCache('nes', packJson);
    final ids = await svc.cachedPacks();
    expect(ids..sort(), ['nes', 'snes']);
  });

  test('evict deletes the pack from disk', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    await svc.evict('snes');
    expect(await svc.readCached('snes'), isNull);
    expect(await svc.cachedPacks(), isEmpty);
  });

  test('readCachedIndex and writeCacheIndex use index.json', () async {
    final svc = service();
    const indexJson =
        '{"built":"2026-09-10","packs":[{"pack":"snes","system":"S","games":1,"aliases":[]}]}';
    expect(await svc.readCachedIndex(), isNull);
    await svc.writeCacheIndex(indexJson);
    final index = await svc.readCachedIndex();
    expect(index!.packs.single.pack, 'snes');
    expect(await svc.cachedPacks(), isEmpty);
  });

  List<int> gz(String s) => gzip.encode(utf8.encode(s));

  test('packUri and indexUri point at the fixed-tag release', () {
    final svc = service();
    expect(svc.packUri('snes').toString(),
        'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs/snes.json.gz');
    expect(svc.indexUri().toString(),
        'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs/index.json');
  });

  test('an explicit base redirects both URIs at a local build', () {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw StateError('network not allowed in this test'),
      base: 'http://localhost:8787',
    );
    expect(svc.packUri('snes').toString(), 'http://localhost:8787/snes.json.gz');
    expect(svc.indexUri().toString(), 'http://localhost:8787/index.json');
  });

  test('download unzips, writes the cache and returns the pack', () async {
    final requests = <Uri>[];
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        requests.add(uri);
        return gz(packJson);
      },
    );
    final pack = await svc.download('snes');
    expect(pack.games.single.title, 'Crystal Vanguard');
    expect(requests.single.path, endsWith('/packs/snes.json.gz'));
    expect(await File(p.join(tmp.path, 'snes.json')).exists(), isTrue);
  });

  test('load uses the cache and does not hit the network', () async {
    var calls = 0;
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        calls++;
        return gz(packJson);
      },
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes');
    expect(pack!.games.single.title, 'Crystal Vanguard');
    expect(calls, 0);
  });

  test('load with forceRefresh hits the network even with a cache', () async {
    var calls = 0;
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        calls++;
        return gz(packJson);
      },
    );
    await svc.writeCache('snes', packJson);
    await svc.load('snes', forceRefresh: true);
    expect(calls, 1);
  });

  test('load falls back to the cache when the network fails', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw const SocketException('no network'),
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes', forceRefresh: true);
    expect(pack!.games.single.title, 'Crystal Vanguard');
  });

  test('load returns null with neither network nor cache', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw const SocketException('no network'),
    );
    expect(await svc.load('snes'), isNull);
  });

  test('httpFetch does not hang on a connection that accepts but never answers',
      () async {
    // connectionTimeout covers only the connect phase, so a socket that
    // accepts and stays silent would hang forever without the read timeout.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {});
    addTearDown(() async {
      await server.close();
    });
    final uri = Uri.parse('http://127.0.0.1:${server.port}/anything');

    final sw = Stopwatch()..start();
    await expectLater(
      MetadataPackService.httpFetch(uri,
          timeout: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('load falls back to the cache when the fetch times out', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async =>
          throw TimeoutException('network hung', const Duration(seconds: 1)),
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes', forceRefresh: true);
    expect(pack!.games.single.title, 'Crystal Vanguard');
  });

  test('loadIndex downloads index.json ungzipped and caches it', () async {
    const indexJson =
        '{"built":"2026-09-10","packs":[{"pack":"snes","system":"S","games":1,"aliases":["snes"]}]}';
    final requests = <Uri>[];
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        requests.add(uri);
        return utf8.encode(indexJson);
      },
    );
    final index = await svc.loadIndex(forceRefresh: true);
    expect(index!.packs.single.pack, 'snes');
    expect(requests.single.path, endsWith('/packs/index.json'));
    expect((await svc.readCachedIndex())!.built, '2026-09-10');
  });
}
