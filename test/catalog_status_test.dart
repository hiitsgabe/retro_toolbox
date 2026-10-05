import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StatusService extends CatalogService {
  @override
  Future<List<Game>> loadCatalog(String consoleId,
      {String? iaAccessKey,
      String? iaSecretKey,
      String? authToken,
      void Function(int done, int total)? onProgress,
      void Function(String status)? onStatus}) async {
    onStatus?.call('Sorting 3 games');
    return const [Game(title: 'one.bin', url: 'https://h/one.bin', size: 1, consoleId: 'a')];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('catalog_status');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );

  HttpOverrides? savedOverrides;
  setUp(() => savedOverrides = HttpOverrides.current);
  tearDown(() => HttpOverrides.global = savedOverrides);

  test('service reports sorting, box art and saving after the pages load, then a saved catalog on reload', () async {
    // Loopback server standing in for the catalog source: two JSON listings.
    HttpOverrides.global = null; // the test binding stubs HTTP with 400s; loopback only here
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      final items = switch (req.uri.path) {
        '/p1/' => [{'name': 'a.bin', 'size': 1}, {'name': 'b.bin', 'size': 2}],
        '/empty/' => <Map<String, Object>>[],
        _ => [{'name': 'c.bin', 'size': 3}],
      };
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(items))
        ..close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final configDir = Directory('${tmp.path}/config')..createSync(recursive: true);
    File('${configDir.path}/consoles.json').writeAsStringSync(jsonEncode([
      {
        'name': 'Status Test',
        'url': ['$base/p1/', '$base/p2/'],
        'file_format': ['.bin'],
      },
      {
        'name': 'Empty Test',
        'url': ['$base/empty/'],
        'file_format': ['.bin'],
      }
    ]));

    final service = CatalogService();
    final id = CatalogService.consoleId('Status Test');

    final statuses = <String>[];
    final games = await service.loadCatalog(id, onStatus: statuses.add);
    expect(games, hasLength(3));
    expect(statuses, ['Sorting 3 games', 'Matching box art', 'Saving catalog']);

    // Second call is served from the cache file.
    final cached = <String>[];
    await service.loadCatalog(id, onStatus: cached.add);
    expect(cached, ['Loading saved catalog']);

    // A source that lists nothing is not cached: the next load must retry.
    final emptyId = CatalogService.consoleId('Empty Test');
    expect(await service.loadCatalog(emptyId), isEmpty);
    expect(Directory(tmp.path).listSync(recursive: true).whereType<File>().where((f) => f.path.contains('empty_test')), isEmpty);
  });

  test('a JSON source with its own regex is read by the regex', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          '0100000000001000': {'name': {'en': 'Alpha'}, 'size': 5},
          '0100000000002000': {'name': {'en': 'Beta'}, 'size': 7},
        }))
        ..close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    await CatalogService().resetCatalog(); // drops the console list cached by the test above
    final configDir = Directory('${tmp.path}/config')..createSync(recursive: true);
    File('${configDir.path}/consoles.json').writeAsStringSync(jsonEncode([
      {
        'name': 'Regex Json Test',
        'url': ['$base/list'],
        'regex': r'"(?P<id>[0-9A-F]{16})"\s*:\s*\{.*?"en"\s*:\s*"(?P<text>[^"]+)".*?"size"\s*:\s*(?P<size>\d+)',
        'download_url': '$base/dl/<id>',
        'file_format': ['.bin'],
        'ignore_extension_filtering': true,
      }
    ]));

    final games = await CatalogService().loadCatalog(CatalogService.consoleId('Regex Json Test'));
    expect(games.map((g) => g.title), ['Alpha.bin', 'Beta.bin']);
    expect(games.first.url, '$base/dl/0100000000001000');
  });

  test('date and popularity groups in a regex fill the game details', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      req.response
        ..write([
          '<i href="a.bin" d="1999-07-04" p="12"></i>',
          '<i href="b.bin" d="2001" p=""></i>',
          '<i href="c.bin" d="soon" p="3"></i>',
          '<i href="d.bin" d="200105" p="x"></i>',
        ].join('\n'))
        ..close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    await CatalogService().resetCatalog();
    final configDir = Directory('${tmp.path}/config')..createSync(recursive: true);
    File('${configDir.path}/consoles.json').writeAsStringSync(jsonEncode([
      {
        'name': 'Regex Date Test',
        'url': ['$base/'],
        'regex': r'<i href="(?P<href>[^"]+)" d="(?P<date>[^"]*)" p="(?P<popularity>[^"]*)"></i>',
        'file_format': ['.bin'],
      }
    ]));

    final games = await CatalogService().loadCatalog(CatalogService.consoleId('Regex Date Test'));
    expect([for (final g in games) (g.title, g.details?.releaseDate, g.details?.popularity)], [
      ('a.bin', 19990704, 12),
      ('b.bin', 20010000, null),
      ('c.bin', null, 3),
      ('d.bin', 20010500, null),
    ]);
    expect(games.every((g) => g.details?.boxart == null), isTrue);
  });

  test('release dates come from DAT files on the console', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      req.response
        ..statusCode = req.uri.path == '/missing.dat' ? 404 : 200
        ..write(switch (req.uri.path) {
          '/list/' => '<a href="Alpha Title (USA).bin">x</a>\n<a href="Beta Title (USA).bin">x</a>',
          '/years.dat' => 'game (\n\tcomment "Alpha Title (USA)"\n\treleaseyear "1999"\n)\n',
          '/months.dat' => 'game (\n\tcomment "Alpha Title (USA)"\n\treleasemonth "07"\n)\n',
          _ => '',
        })
        ..close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    await CatalogService().resetCatalog();
    final configDir = Directory('${tmp.path}/config')..createSync(recursive: true);
    File('${configDir.path}/consoles.json').writeAsStringSync(jsonEncode([
      {
        'name': 'Dat Date Test',
        'url': ['$base/list/'],
        'regex': r'<a href="(?P<href>[^"]+)">',
        'file_format': ['.bin'],
        'release_dates': ['$base/years.dat', '$base/missing.dat', '$base/months.dat'],
      }
    ]));

    final statuses = <String>[];
    final games = await CatalogService().loadCatalog(CatalogService.consoleId('Dat Date Test'), onStatus: statuses.add);
    expect([for (final g in games) g.details?.releaseDate], [19990700, null]);
    expect(statuses, contains('Matching release dates'));
  });

  test('provider shows the service status as loadingStatus', () async {
    SharedPreferences.setMockInitialValues({});
    const a = Console(id: 'a', name: 'A', urls: []);
    final container = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _StatusService())),
    ]);
    addTearDown(container.dispose);
    final seen = <String>[];
    container.listen(catalogProvider, (_, s) => seen.add(s.loadingStatus));

    await container.read(catalogProvider.notifier).loadCatalog(a);
    expect(seen, contains('Sorting 3 games'));
  });
}
