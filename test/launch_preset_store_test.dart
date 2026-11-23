import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_store.dart';

String presets({int version = 1, int schema = 1, String id = 'a'}) => jsonEncode({
      'schema': schema,
      'version': version,
      'presets': [
        {
          'id': id,
          'name': 'Emu $id',
          'systems': {
            'psx': {'extensions': ['chd']},
          },
        },
      ],
    });

/// Serves [body] with [etag]; answers 304 when the request carries it.
class _Server {
  _Server(this.server);

  final HttpServer server;
  String body = presets();
  String? etag = '"v1"';
  int status = HttpStatus.ok;
  final ifNoneMatch = <String?>[];

  String get url => 'http://${server.address.host}:${server.port}/launch_presets.json';

  static Future<_Server> start() async {
    final s = _Server(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    s.server.listen((r) async {
      final asked = r.headers.value(HttpHeaders.ifNoneMatchHeader);
      s.ifNoneMatch.add(asked);
      if (asked != null && asked == s.etag) {
        r.response.statusCode = HttpStatus.notModified;
      } else {
        r.response.statusCode = s.status;
        if (s.etag != null) r.response.headers.set(HttpHeaders.etagHeader, s.etag!);
        r.response.write(s.body);
      }
      await r.response.close();
    });
    return s;
  }
}

void main() {
  late Directory tmp;
  late _Server server;
  late String seed;
  final saved = HttpOverrides.current;

  setUp(() async {
    // The test binding answers every request with a 400; only loopback here.
    HttpOverrides.global = null;
    tmp = await Directory.systemTemp.createTemp('rt-presets-');
    server = await _Server.start();
    seed = presets(version: 3, id: 'seed');
  });

  tearDown(() async {
    HttpOverrides.global = saved;
    await server.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  LaunchPresetStore store() => LaunchPresetStore(url: server.url, seed: () async => seed, supportDir: () async => tmp);

  File cacheOf(LaunchPresetStore s) => File('${tmp.path}/launcher/presets/${s.cacheName}.json');

  test('with no cache the seed loads', () async {
    expect((await store().load()).presets.single.id, 'seed');
  });

  test('a cache with a higher version beats the seed', () async {
    final s = store();
    await cacheOf(s).create(recursive: true);
    await cacheOf(s).writeAsString(presets(version: 4, id: 'cache'));
    expect((await s.load()).presets.single.id, 'cache');
  });

  test('a seed with a higher version beats an older cache, as after an app update', () async {
    final s = store();
    await cacheOf(s).create(recursive: true);
    await cacheOf(s).writeAsString(presets(version: 2, id: 'cache'));
    expect((await s.load()).presets.single.id, 'seed');
  });

  test('a cache with a newer schema is refused whole', () async {
    final s = store();
    await cacheOf(s).create(recursive: true);
    await cacheOf(s).writeAsString(presets(version: 9, schema: 2, id: 'future'));
    expect((await s.load()).presets.single.id, 'seed');
  });

  test('a 200 that validates replaces the cache, and its ETag is sent next time', () async {
    final s = store();
    server.body = presets(version: 5, id: 'fresh');
    await s.refresh();
    expect((await s.load()).presets.single.id, 'fresh');
    await s.refresh();
    expect(server.ifNoneMatch, [null, '"v1"']);
  });

  test('a 304 keeps the cache', () async {
    final s = store();
    server.body = presets(version: 5, id: 'fresh');
    await s.refresh();
    server.body = presets(version: 6, id: 'never sent');
    await s.refresh();
    expect((await s.load()).presets.single.id, 'fresh');
  });

  test('a junk 200 never replaces the cache', () async {
    final s = store();
    server.body = presets(version: 5, id: 'fresh');
    await s.refresh();
    for (final junk in ['<html>rate limited</html>', presets(version: 7, schema: 2, id: 'future'), jsonEncode({'schema': 1, 'version': 8, 'presets': []})]) {
      server
        ..etag = '"junk"'
        ..body = junk;
      await s.refresh();
      expect(cacheOf(s).readAsStringSync(), presets(version: 5, id: 'fresh'), reason: junk);
    }
  });

  test('an error status or an unreachable server keeps the cache', () async {
    final s = store();
    server.body = presets(version: 5, id: 'fresh');
    await s.refresh();
    // A body that would validate, so only the status check can refuse it.
    server
      ..etag = null
      ..status = HttpStatus.internalServerError
      ..body = presets(version: 6, id: 'error');
    await s.refresh();
    expect(cacheOf(s).readAsStringSync(), presets(version: 5, id: 'fresh'));
    await server.server.close(force: true);
    await s.refresh();
    expect((await s.load()).presets.single.id, 'fresh');
  });

  group('LaunchPresetsSource', () {
    test('an https dart-define overrides the default URL', () {
      expect(LaunchPresetsSource.resolve(define: 'https://example.com/p.json'), 'https://example.com/p.json');
    });

    test('a non-https define is ignored', () {
      expect(LaunchPresetsSource.resolve(define: 'http://example.com/p.json'), LaunchPresetsSource.defaultUrl);
      expect(LaunchPresetsSource.resolve(define: ''), LaunchPresetsSource.defaultUrl);
    });
  });
}
