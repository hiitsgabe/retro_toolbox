import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalogService extends CatalogService {
  final Map<String, List<Game>> byConsole;
  _FakeCatalogService(this.byConsole);

  @override
  Future<List<Game>> loadCatalog(String consoleId,
          {String? iaAccessKey, String? iaSecretKey, String? authToken, void Function(int done, int total)? onProgress}) async =>
      byConsole[consoleId] ?? [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('catalog_switch');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );

  test('switching to a console whose catalog comes back empty drops the previous games and reports it', () async {
    SharedPreferences.setMockInitialValues({});
    const a = Console(id: 'a', name: 'A', urls: []);
    const b = Console(id: 'b', name: 'B', urls: []);
    final service = _FakeCatalogService({
      'a': const [Game(title: 'one.bin', url: 'https://h/one.bin', size: 1, consoleId: 'a')],
    });
    final container = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, service)),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    await notifier.loadCatalog(a);
    expect(container.read(catalogProvider).paginatedFilteredGames, hasLength(1));

    await notifier.loadCatalog(b);
    final s = container.read(catalogProvider);
    expect(s.paginatedFilteredGames, isEmpty);
    expect(s.errorMessage, isNotEmpty);
  });
}
