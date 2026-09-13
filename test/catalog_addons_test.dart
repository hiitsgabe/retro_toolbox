import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';

typedef _Spy = ({String url, List<Map<String, String?>> seen});

/// A local server that records the headers it received and answers [body].
Future<_Spy> _server(String body, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final seen = <Map<String, String?>>[];
  server.listen((req) async {
    seen.add({
      'authorization': req.headers.value('authorization'),
      'cookie': req.headers.value('cookie'),
    });
    req.response.statusCode = status;
    req.response.write(body);
    await req.response.close();
  });
  return (url: 'http://${server.address.address}:${server.port}/', seen: seen);
}

String _listing(List<String> names) => jsonEncode([
      for (final name in names) {'name': name, 'size': 1024},
    ]);

Future<AddonStore> _store(List<Addon> addons, Map<String, String> catalogs) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final root = await Directory.systemTemp.createTemp('catalog_addons_test');
  addTearDown(() => root.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), root);
  await store.save(addons);
  for (final entry in catalogs.entries) {
    await store.writeCatalog(entry.key, entry.value);
  }
  return store;
}

String _catalog(String consoleName, String url, {Map<String, dynamic>? auth}) => jsonEncode([
      {'name': consoleName, 'url': url, 'file_format': ['.zip'], if (auth != null) 'auth': auth},
    ]);

void main() {
  // No `TestWidgetsFlutterBinding.ensureInitialized()` on purpose: the binding
  // installs an `HttpOverrides` that returns 400 for every request, and
  // `fetchSources` talks to a real loopback `HttpServer`.

  group('buildCatalog', () {
    test('two addons with a file both enter, in list order', () async {
      final store = await _store(
        const [Addon(id: 'one', name: 'One'), Addon(id: 'two', name: 'Two')],
        {
          'one': _catalog('SNES', 'https://one/'),
          'two': _catalog('SNES', 'https://two/'),
        },
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.consoles['snes']!.urls, ['https://one/', 'https://two/']);
      expect(merged.sources['snes']!.map((f) => f.addonId), ['one', 'two']);
    });

    test('addon with no catalog file is skipped without affecting others', () async {
      final store = await _store(
        const [Addon(id: 'ghost', name: 'Ghost'), Addon(id: 'one', name: 'One')],
        {'one': _catalog('SNES', 'https://one/')},
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.sources['snes']!.single.addonId, 'one');
    });

    test('unreadable catalog from one addon does not affect others', () async {
      final store = await _store(
        const [Addon(id: 'broken', name: 'Broken'), Addon(id: 'one', name: 'One')],
        {'broken': 'this is not json', 'one': _catalog('SNES', 'https://one/')},
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.consoles.keys, ['snes']);
      expect(merged.sources['snes']!.single.addonId, 'one');
    });

    test('each source auth comes from the addon that declared the console', () async {
      final store = await _store(
        const [Addon(id: 'one', name: 'One'), Addon(id: 'two', name: 'Two')],
        {
          'one': _catalog('SNES', 'https://one/', auth: {'auth_message': 'paste the token'}),
          'two': _catalog('SNES', 'https://two/', auth: {'cookies': true}),
        },
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.sources['snes']![0].auth!['auth_message'], 'paste the token');
      expect(merged.sources['snes']![1].auth!['cookies'], true);
    });

    test('empty addon list yields empty catalog', () async {
      final store = await _store(const [], const {});
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.isEmpty, isTrue);
    });
  });

  group('fetchSources', () {
    const console = Console(id: 'snes', name: 'SNES', urls: [], fileFormat: ['.zip']);

    test('each source is fetched with its own addon auth', () async {
      final a = await _server(_listing(['A (USA).zip']));
      final b = await _server(_listing(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      await CatalogService().fetchSources(
        client,
        console,
        [
          ConsoleSource(addonId: 'one', url: a.url, auth: const {'auth_message': 'paste'}),
          ConsoleSource(addonId: 'two', url: b.url, auth: const {'cookies': true, 'cookie_name': 'session'}),
        ],
        tokens: const {'one': 'tok-one', 'two': 'tok-two'},
      );

      expect(a.seen.single['authorization'], 'Bearer tok-one');
      expect(a.seen.single['cookie'], isNull);
      expect(b.seen.single['cookie'], 'session=tok-two');
      expect(b.seen.single['authorization'], isNull);
    });

    test('games are tagged with the addon that served them', () async {
      final a = await _server(_listing(['A (USA).zip']));
      final b = await _server(_listing(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      final games = await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'one', url: a.url),
        ConsoleSource(addonId: 'two', url: b.url),
      ]);

      final byTitle = {for (final game in games) game.title: game.sourceId};
      expect(byTitle, {'A (USA).zip': 'one', 'B (USA).zip': 'two'});
    });

    test('no token for the addon means no auth header is sent', () async {
      final a = await _server(_listing(['A (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'one', url: a.url, auth: const {'auth_message': 'paste'}),
      ]);

      expect(a.seen.single['authorization'], isNull);
    });

    test('one failing source does not prevent the other from delivering', () async {
      final bad = await _server('error', status: 500);
      final good = await _server(_listing(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      final games = await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'bad', url: bad.url),
        ConsoleSource(addonId: 'good', url: good.url),
      ]);

      expect(games.map((j) => j.title), ['B (USA).zip']);
      expect(games.single.sourceId, 'good');
    });

    test('all sources failing propagates the error', () async {
      final bad = await _server('error', status: 500);
      final client = HttpClient();
      addTearDown(client.close);

      expect(
        () => CatalogService().fetchSources(client, console, [ConsoleSource(addonId: 'bad', url: bad.url)]),
        throwsA(isA<Exception>()),
      );
    });
  });
}
