import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalogService extends CatalogService {
  _FakeCatalogService(this.games);
  final List<Game> games;

  @override
  Future<List<Game>> loadCatalog(String consoleId,
          {String? iaAccessKey,
          String? iaSecretKey,
          String? authToken,
          void Function(int done, int total)? onProgress,
          void Function(String status)? onStatus}) async =>
      games;
}

Game _g(String title) => Game(title: title, url: 'https://h/${Uri.encodeComponent(title)}.chd', size: 1, consoleId: 'psx');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('disc_grouping_catalog');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('turning grouping on or off for the console re-lists it at once', () async {
    SharedPreferences.setMockInitialValues({});
    const psx = Console(id: 'psx', name: 'PSX', urls: []);
    final container = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(
          ref,
          _FakeCatalogService([
            _g('Crash Bandicoot (USA)'),
            _g('Final Fantasy VII (USA) (Disc 1)'),
            _g('Final Fantasy VII (USA) (Disc 2)'),
            _g('Final Fantasy VII (USA) (Disc 3)'),
          ]))),
    ]);
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.loaded;
    final catalog = container.read(catalogProvider.notifier);
    await catalog.loadCatalog(psx);
    expect(container.read(catalogProvider).paginatedFilteredGames, hasLength(4));

    // The re-list runs in compute: wait (bounded) for the count to change.
    Future<int> countAfter(Future<void> change) async {
      final before = container.read(catalogProvider).paginatedFilteredGames.length;
      await change;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        final now = container.read(catalogProvider).paginatedFilteredGames.length;
        if (now != before) return now;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return before;
    }

    expect(await countAfter(settings.setSetting<bool>(AppSettings.groupDiscs, true, 'psx')), 2);
    final grouped = container.read(catalogProvider).paginatedFilteredGames;
    expect(grouped.firstWhere((g) => g.discs.isNotEmpty).discs, hasLength(3));

    expect(await countAfter(settings.setSetting<bool>(AppSettings.groupDiscs, false, 'psx')), 4);
  });
}
