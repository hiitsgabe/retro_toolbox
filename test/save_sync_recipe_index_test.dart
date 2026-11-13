import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';

/// The repo's own pattern for an HTTP test: a loopback server, no mocks.
class FakeCatalog {
  FakeCatalog(this.server);

  final HttpServer server;
  int indexHits = 0;
  int conditionalHits = 0;
  String etag = 'v1';
  String index = jsonEncode({
    'format': 1,
    'recipes': [
      {'id': 'alpha', 'packages': ['com.example.alpha'], 'status': 'draft'},
      {'id': 'beta', 'packages': ['com.example.beta', 'com.example.beta.demo'], 'status': 'verified'},
    ],
  });

  late final String base = 'http://${server.address.host}:${server.port}';

  static Future<FakeCatalog> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeCatalog(s);
    s.listen((r) async {
      if (r.uri.path.endsWith('index.json')) {
        fake.indexHits++;
        if (r.headers.value(HttpHeaders.ifNoneMatchHeader) == fake.etag) {
          fake.conditionalHits++;
          r.response.statusCode = HttpStatus.notModified;
          await r.response.close();
          return;
        }
        r.response.headers.set(HttpHeaders.etagHeader, fake.etag);
        r.response.write(fake.index);
        await r.response.close();
        return;
      }
      if (r.uri.path.endsWith('/recipes/alpha.json')) {
        r.response.write(jsonEncode({'schema': 1, 'id': 'alpha'}));
        await r.response.close();
        return;
      }
      r.response.statusCode = HttpStatus.notFound;
      await r.response.close();
    });
    return fake;
  }
}

void main() {
  late Directory tmp;
  late FakeCatalog fake;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('recipeindex');
    fake = await FakeCatalog.start();
  });
  tearDown(() async {
    await fake.server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  RecipeIndex index({String? base}) => RecipeIndex(baseUrl: base ?? fake.base, cacheDir: Directory(p.join(tmp.path, 'save_sync')));

  test('an entry is found by every package it names, exactly', () async {
    final c = await index().load();
    expect(c.byPackage['com.example.alpha']!.id, 'alpha');
    expect(c.byPackage['com.example.beta.demo']!.id, 'beta');
    expect(c.byPackage['com.example.alph'], isNull, reason: 'exact only: a near miss must never resolve');
  });

  test('a second load inside the day costs no request at all', () async {
    await index().load();
    expect(fake.indexHits, 1);
    await index().load();
    expect(fake.indexHits, 1);
  });

  test('a forced refresh asks conditionally, and a 304 keeps the cache', () async {
    await index().load();
    final c = await index().load(force: true);
    expect(fake.conditionalHits, 1);
    expect(c.entries, hasLength(2));
  });

  // Stale but known beats confidently wrong: nothing turns red because the
  // network is down.
  test('unreachable with a cache uses it and says so', () async {
    await index().load();
    final i = index();
    await fake.server.close(force: true);
    final c = await i.load(force: true);
    expect(c.entries, hasLength(2));
    expect(c.fromCache, isTrue);
  });

  test('unreachable with no cache is empty, not an error', () async {
    final i = index();
    await fake.server.close(force: true);
    final c = await i.load();
    expect(c.isEmpty, isTrue);
    expect(c.fromCache, isFalse);
  });

  test('a body is fetched on demand and then served from the cache', () async {
    final i = index();
    expect((await i.body('alpha'))!['id'], 'alpha');
    await fake.server.close(force: true);
    expect((await i.body('alpha'))!['id'], 'alpha', reason: 'kept bodies survive the network');
    expect(await i.body('never-published'), isNull);
  });

  test('junk where the index should be is empty, never a crash', () async {
    fake.index = 'not json at all';
    expect((await index().load()).isEmpty, isTrue);
  });
}
