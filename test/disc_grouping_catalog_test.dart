import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
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

  test('grouping is on by default, and turning it off or on for the console re-lists it at once', () async {
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
    expect(container.read(catalogProvider).paginatedFilteredGames, hasLength(2)); // on by default

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

    expect(await countAfter(settings.setSetting<bool>(AppSettings.groupVersions, false, 'psx')), 4);
    expect(await countAfter(settings.setSetting<bool>(AppSettings.groupVersions, true, 'psx')), 2);
    final grouped = container.read(catalogProvider).paginatedFilteredGames;
    expect(grouped.firstWhere((g) => g.discs.isNotEmpty).discs, hasLength(3));
  });

  test('a console read by a regex (one entry per game already) is never grouped', () async {
    SharedPreferences.setMockInitialValues({});
    const sw = Console(id: 'psx', name: 'PSX', urls: [], regex: 'x');
    final container = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(
          ref,
          _FakeCatalogService([
            _g('Final Fantasy VII (USA) (Disc 1)'),
            _g('Final Fantasy VII (USA) (Disc 2)'),
          ]))),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).loaded;
    await container.read(catalogProvider.notifier).loadCatalog(sw);
    expect(container.read(catalogProvider).paginatedFilteredGames, hasLength(2));
    expect(container.read(catalogProvider.notifier).groupsVersions, isFalse);
  });

  test('a version on disk is the entry, with no filter on, and the setting predicate is the notifier\'s', () async {
    final dir = Directory.systemTemp.createTempSync('owned_version');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/Game (Europe).chd').writeAsStringSync('x');
    SharedPreferences.setMockInitialValues({});
    const psx = Console(id: 'psx', name: 'PSX', urls: []);
    final container = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService([_g('Game (USA)'), _g('Game (Europe)')]))),
    ]);
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.loaded;
    await settings.setSetting<String>(AppSettings.downloadDir, dir.path, 'psx');
    final catalog = container.read(catalogProvider.notifier);
    await catalog.loadCatalog(psx);
    catalog.clearFilters();
    await catalog.updateFilteredGames(immediate: true);
    expect(catalog.groupsVersions, isTrue);
    expect(container.read(catalogProvider).paginatedFilteredGames.single.title, 'Game (Europe)');
  });

  test('a version being downloaded is the entry too', () async {
    SharedPreferences.setMockInitialValues({});
    const psx = Console(id: 'psx', name: 'PSX', urls: []);
    final eu = _g('Game (Europe)');
    final container = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService([_g('Game (USA)'), eu]))),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).loaded;
    final catalog = container.read(catalogProvider.notifier);
    final manager = container.read(gameStateManagerProvider.notifier);
    await catalog.loadCatalog(psx);
    catalog.clearFilters();
    await catalog.updateFilteredGames(immediate: true);
    expect(container.read(catalogProvider).paginatedFilteredGames.single.title, 'Game (USA)');
    manager.state = {...manager.state, eu.gameId: GameState(game: eu, status: GameStatus.downloading)};
    await catalog.updateFilteredGames(immediate: true);
    expect(container.read(catalogProvider).paginatedFilteredGames.single.title, 'Game (Europe)');
  });
}
