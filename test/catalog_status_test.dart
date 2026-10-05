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

  test('service reports sorting, box art and saving after the pages load, then a saved catalog on reload', () async {
    // Loopback server standing in for the catalog source: two JSON listings.
    HttpOverrides.global = null; // the test binding stubs HTTP with 400s; loopback only here
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      final items = req.uri.path == '/p1/'
          ? [{'name': 'a.bin', 'size': 1}, {'name': 'b.bin', 'size': 2}]
          : [{'name': 'c.bin', 'size': 3}];
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
