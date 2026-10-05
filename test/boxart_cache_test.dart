import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/boxart_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('boxart_cache');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );

  HttpOverrides? savedOverrides;
  setUp(() => savedOverrides = HttpOverrides.current);
  tearDown(() => HttpOverrides.global = savedOverrides);

  test('box art listing is kept on disk for a week', () async {
    HttpOverrides.global = null; // the test binding stubs HTTP with 400s; loopback only here
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((req) {
      requests++;
      req.response
        ..headers.contentType = ContentType.html
        ..write('<a href="Alpha%20Quest%202%20(USA).png">x</a><a href="Beta%20Run%20(Europe).png">y</a>')
        ..close();
    });
    final console = Console(id: 'c', name: 'C', urls: const [], boxarts: 'http://127.0.0.1:${server.port}/art/');
    const games = [
      Game(title: 'a', url: 'https://h/Alpha%20Quest%202%20(USA).zip', size: 1, consoleId: 'c'),
      Game(title: 'b', url: 'https://h/Gamma%20(USA).zip', size: 1, consoleId: 'c'),
    ];
    List<String?> art(List<Game> g) => [for (final x in g) x.details?.boxart];

    final first = art(await BoxartService().mutateGamesWithBoxarts(games, console));
    expect(first, ['${console.boxarts}Alpha%20Quest%202%20(USA).png', null]);
    expect(requests, 1);

    // Fresh process (no memory cache): served from disk.
    BoxartService.clearMemoryCache();
    expect(art(await BoxartService().mutateGamesWithBoxarts(games, console)), first);
    expect(requests, 1);

    // Older than a week: fetched again.
    BoxartService.clearMemoryCache();
    for (final f in tmp.listSync().whereType<File>().where((f) => f.path.contains('boxarts_'))) {
      f.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
    }
    expect(art(await BoxartService().mutateGamesWithBoxarts(games, console)), first);
    expect(requests, 2);
  });
}
