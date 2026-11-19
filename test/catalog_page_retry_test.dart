import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/catalog_service.dart';

/// A catalog in two pages; page `b` fails its first [bFailures] requests.
class _Feed {
  final int bFailures;
  late final HttpServer server;
  int bHits = 0;
  _Feed(this.bFailures);

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      if (r.uri.path == '/b' && ++bHits <= bFailures) {
        r.response.statusCode = 502;
      } else {
        r.response.write(r.uri.path == '/a' ? '<g id="A1">Alpha</g>' : '<g id="B1">Beta</g>');
      }
      await r.response.close();
    });
  }

  String url(String page) => 'http://127.0.0.1:${server.port}/$page';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    HttpOverrides.global = null;
    tmp = Directory.systemTemp.createTempSync('catalog_retry');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    CatalogService.pageRetryDelay = Duration.zero;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<List<String>> load(_Feed feed) async {
    await CatalogService().setCatalogFromJson(jsonEncode({
      'paged': {
        'name': 'Paged',
        'url': [feed.url('a'), feed.url('b')],
        'original_format': ['.nsz'],
        'ignore_extension_filtering': true,
        'regex': r'<g id="(?P<id>\w+)">(?P<text>[^<]+)</g>',
        'download_url': 'https://h.example.com/<id>/base',
      },
    }));
    return [for (final g in await CatalogService().loadCatalog('paged')) g.title];
  }

  test('a page that fails three times and then answers is in the catalog', () async {
    final feed = _Feed(3);
    await feed.start();
    addTearDown(() => feed.server.close(force: true));

    expect(await load(feed), ['Alpha.nsz', 'Beta.nsz']);
    expect(feed.bHits, 4);
  });

  test('a page that keeps failing leaves the catalog unsaved, so the next load fetches it again', () async {
    final feed = _Feed(1000);
    await feed.start();
    addTearDown(() => feed.server.close(force: true));

    expect(await load(feed), ['Alpha.nsz']);
    expect(feed.bHits, 4);
    expect(await load(feed), ['Alpha.nsz']);
    expect(feed.bHits, 8);
  });
}
