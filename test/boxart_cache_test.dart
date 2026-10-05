import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/boxart_service.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/utils/title_match.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('boxart_cache');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );

  late HttpServer server;
  late String base;
  var requests = 0;
  var failing = false;
  HttpOverrides? savedOverrides;

  setUp(() async {
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null; // the test binding stubs HTTP with 400s; loopback only here
    requests = 0;
    failing = false;
    BoxartService.clearMemoryCache();
    for (final f in tmp.listSync().whereType<File>()) {
      f.deleteSync();
    }
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) {
      requests++;
      if (failing) {
        req.response
          ..statusCode = 500
          ..close();
        return;
      }
      final json = req.uri.path.endsWith('.json');
      req.response
        ..headers.contentType = json ? ContentType.json : ContentType.html
        ..write(json
            ? jsonEncode([
                {'title': 'Alpha Quest 2 (USA)', 'pic': 'a1', 'alt': 'a2'},
              ])
            : '<a href="Alpha%20Quest%202%20(USA).png">x</a><a href="Beta%20Run%20(Europe).png">y</a>')
        ..close();
    });
  });
  tearDown(() async {
    await BoxartService.flushDiskWrites();
    await server.close(force: true);
    HttpOverrides.global = savedOverrides;
  });

  const games = [
    Game(title: 'a', url: 'https://h/Alpha%20Quest%202%20(USA).zip', size: 1, consoleId: 'c'),
    Game(title: 'b', url: 'https://h/Gamma%20(USA).zip', size: 1, consoleId: 'c'),
  ];
  Console htmlConsole() => Console(id: 'c', name: 'C', urls: const [], boxarts: '$base/art/');
  Future<List<String?>> art(Console c) async => [for (final g in await BoxartService().mutateGamesWithBoxarts(games, c)) g.details?.boxart];
  List<File> cacheFiles() => tmp.listSync().whereType<File>().where((f) => f.path.contains('boxarts_')).toList();
  // The disk write is fire-and-forget: wait for it.
  Future<List<File>> written() async {
    await BoxartService.flushDiskWrites();
    return cacheFiles();
  }

  void age(Duration d) {
    for (final f in cacheFiles()) {
      f.setLastModifiedSync(DateTime.now().subtract(d));
    }
  }

  test('box art listing is kept on disk for a week', () async {
    final first = await art(htmlConsole());
    expect(first, ['$base/art/Alpha%20Quest%202%20(USA).png', null]);
    expect(requests, 1);
    expect(await written(), hasLength(1));

    // Fresh process (no memory cache): served from disk.
    BoxartService.clearMemoryCache();
    expect(await art(htmlConsole()), first);
    expect(requests, 1);

    // Older than a week: fetched again.
    BoxartService.clearMemoryCache();
    age(const Duration(days: 8));
    expect(await art(htmlConsole()), first);
    expect(requests, 2);
  });

  test('a file dated in the future counts as expired', () async {
    await art(htmlConsole());
    await written();
    BoxartService.clearMemoryCache();
    age(const Duration(days: -2));
    await art(htmlConsole());
    expect(requests, 2);
  });

  test('a corrupt or foreign cache file is ignored and replaced', () async {
    final first = await art(htmlConsole());
    final file = (await written()).single;
    for (final junk in ['not json', '{}', '[1,2]', '{"key": "other", "boxarts": {}}']) {
      file.writeAsStringSync(junk);
      BoxartService.clearMemoryCache();
      expect(await art(htmlConsole()), first, reason: junk);
      await written();
    }
    expect(requests, 5);
  });

  test('an expired cache file is used when the listing cannot be fetched', () async {
    final first = await art(htmlConsole());
    await written();
    BoxartService.clearMemoryCache();
    age(const Duration(days: 30));
    failing = true;
    expect(await art(htmlConsole()), first);
    expect(requests, 2);
  });

  test('JSON configs sharing a URL but not their fields get their own listing', () async {
    Console jsonConsole(String image) => Console(id: 'j', name: 'J', urls: const [], boxarts: <String, dynamic>{
          'url': '$base/db.json',
          'name': 'title',
          'image': 'https://img.test/{$image}.png',
        });
    expect(await art(jsonConsole('pic')), ['https://img.test/a1.png', null]);
    expect(await art(jsonConsole('alt')), ['https://img.test/a2.png', null]);
    expect(requests, 2);
    expect(await written(), hasLength(2));
    BoxartService.clearMemoryCache();
    expect(await art(jsonConsole('alt')), ['https://img.test/a2.png', null]);
    expect(await art(jsonConsole('pic')), ['https://img.test/a1.png', null]);
    expect(requests, 2);
  });

  test('clearing the catalog cache drops the box art listing too', () async {
    final configDir = Directory('${tmp.path}/config')..createSync(recursive: true);
    File('${configDir.path}/consoles.json').writeAsStringSync(jsonEncode([
      {
        'name': 'Art Test',
        'url': ['$base/list/'],
        'file_format': ['.zip'],
        'boxarts': '$base/art/'
      },
    ]));
    final service = CatalogService();
    final id = CatalogService.consoleId('Art Test');
    final console = (await service.getConsoles())[id]!;

    await art(console);
    await written();
    await service.clearCatalogCache(id);
    expect(cacheFiles(), isEmpty);
    await art(console);
    expect(requests, 2); // memory entry dropped as well

    await written();
    await service.clearCatalogCache();
    expect(cacheFiles(), isEmpty);
    await art(console);
    expect(requests, 3);
  });

  test('when matching keeps failing the games come back unchanged', () async {
    final saved = matchInIsolate;
    addTearDown(() => matchInIsolate = saved);
    matchInIsolate = (_, __) async => throw StateError('worker died');
    final out = await BoxartService().mutateGamesWithBoxarts(games, htmlConsole());
    expect(identical(out, games), isTrue);
  });
}
