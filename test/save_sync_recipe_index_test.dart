import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';

String shaOf(String s) => sha256.convert(utf8.encode(s)).toString();

/// The repo's own pattern for an HTTP test: a loopback server, no mocks.
class FakeCatalog {
  FakeCatalog(this.server);

  final HttpServer server;
  int indexHits = 0;
  int conditionalHits = 0;
  int bodyHits = 0;
  String etag = 'v1';

  /// Recipe id to the file served at `<base>/<id>.json`.
  final bodies = <String, String>{'alpha': jsonEncode({'schema': 1, 'id': 'alpha'})};

  /// Recipe id to the sha256 the index claims, when it should lie.
  final claimed = <String, String>{};

  /// Raw index text, when a test wants junk there.
  String? rawIndex;

  late final String base = 'http://${server.address.host}:${server.port}';

  String get index =>
      rawIndex ??
      jsonEncode({
        'format': 1,
        'recipes': [
          {'id': 'alpha', 'packages': ['com.example.alpha'], 'status': 'draft', 'sha256': claimed['alpha'] ?? shaOf(bodies['alpha']!)},
          {'id': 'beta', 'packages': ['com.example.beta', 'com.example.beta.demo'], 'status': 'verified'},
        ],
      });

  static Future<FakeCatalog> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeCatalog(s);
    s.listen((r) async {
      final name = r.uri.pathSegments.isEmpty ? '' : r.uri.pathSegments.last;
      if (name == 'index.json') {
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
      final body = name.endsWith('.json') ? fake.bodies[name.substring(0, name.length - 5)] : null;
      if (body != null) {
        fake.bodyHits++;
        r.response.write(body);
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

  RecipeIndex index() => RecipeIndex(baseUrl: fake.base, cacheDir: Directory(p.join(tmp.path, 'save_sync')));

  test('an entry is found by every package it names, exactly, with its sha256', () async {
    final c = await index().load();
    expect(c.byPackage['com.example.alpha']!.id, 'alpha');
    expect(c.byPackage['com.example.alpha']!.sha256, shaOf(fake.bodies['alpha']!));
    expect(c.byPackage['com.example.beta.demo']!.id, 'beta');
    expect(c.byPackage['com.example.beta.demo']!.sha256, isNull);
    expect(c.byPackage['com.example.alph'], isNull, reason: 'exact only: a near miss must never resolve');
  });

  // A fix to a recipe must not wait a day: every load asks, and an unchanged
  // catalog costs only a 304.
  test('every load asks again, conditionally, and a 304 keeps the cache', () async {
    await index().load();
    final c = await index().load();
    expect(fake.indexHits, 2);
    expect(fake.conditionalHits, 1);
    expect(c.entries, hasLength(2));
  });

  // Stale but known beats confidently wrong: nothing turns red because the
  // network is down.
  test('unreachable with a cache uses it and says so', () async {
    await index().load();
    final i = index();
    await fake.server.close(force: true);
    final c = await i.load();
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

  test('a body comes from <base>/<id>.json, is kept, and outlives the network', () async {
    final i = index();
    final entry = (await i.load()).byPackage['com.example.alpha']!;
    expect((await i.ensureBody(entry))!['id'], 'alpha');
    expect(fake.bodyHits, 1);
    expect(File(p.join(tmp.path, 'save_sync', 'alpha.json')).existsSync(), isTrue);
    expect((await i.ensureBody(entry))!['id'], 'alpha');
    expect(fake.bodyHits, 1, reason: 'a kept body matching the index is not downloaded again');
    await fake.server.close(force: true);
    expect((await i.ensureBody(entry))!['id'], 'alpha');
  });

  test('a kept body the index no longer matches is downloaded again', () async {
    final i = index();
    await i.ensureBody((await i.load()).byPackage['com.example.alpha']!);
    fake.bodies['alpha'] = jsonEncode({'schema': 1, 'id': 'alpha', 'v': 2});
    fake.etag = 'v2';
    final changed = (await i.load()).byPackage['com.example.alpha']!;
    expect((await i.ensureBody(changed))!['v'], 2);
    expect(fake.bodyHits, 2);
  });

  // raw.githubusercontent.com can serve the old file for a few minutes after
  // the index changed. That copy must not replace a good one.
  test('a downloaded body that does not match the index sha256 is never kept', () async {
    fake.claimed['alpha'] = '0' * 64;
    final i = index();
    expect(await i.ensureBody((await i.load()).byPackage['com.example.alpha']!), isNull);
    expect(File(p.join(tmp.path, 'save_sync', 'alpha.json')).existsSync(), isFalse);
  });

  // A network that takes the request and never answers must not hold the
  // refresh forever: the fetch gives up and the cache, here none, is used.
  test('a server that never answers is given up on, not waited for', () async {
    final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => silent.close(force: true));
    silent.listen((_) {}); // takes the request, never writes or closes the response
    final i = RecipeIndex(baseUrl: 'http://${silent.address.host}:${silent.port}', cacheDir: Directory(p.join(tmp.path, 'silent')));
    final clock = Stopwatch()..start();
    final c = await i.load();
    expect(c.isEmpty, isTrue);
    expect(clock.elapsed, lessThan(const Duration(seconds: 15)));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('junk where the index should be is empty, never a crash', () async {
    fake.rawIndex = 'not json at all';
    expect((await index().load()).isEmpty, isTrue);
  });
}
