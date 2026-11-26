import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_groups_support.dart';

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

/// The app's console list, as the console grid reads it.
class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp(super.state);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The config, in memory; [enabled] is launcher mode.
class MemoryConfig implements LaunchConfigStore {
  MemoryConfig(this.enabled);
  bool enabled;

  @override
  Future<LaunchConfig> load() async => LaunchConfig(enabled: enabled);

  @override
  Future<void> save(LaunchConfig config) async => enabled = config.enabled;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _psx = Console(id: 'psx', name: 'PlayStation', urls: [], originalFormat: ['.zip']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt-owned-view-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  final usa = psxGame('Tekken 3 (USA)'), eu = psxGame('Tekken 3 (Europe, Australia)'), crash = psxGame('Crash Bandicoot (USA)');

  Future<(ProviderContainer, CatalogNotifier)> setUpCatalog({required bool launcher, List<Game>? games, bool keepPrefs = false}) async {
    if (!keepPrefs) SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      appStateProvider.overrideWith((ref) => _FakeApp(const AppState(consoles: {'psx': _psx}))),
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService(games ?? [usa, eu, crash]))),
      launcherAvailableProvider.overrideWithValue(true),
      launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(launcher))),
    ]);
    addTearDown(c.dispose);
    final settings = c.read(settingsProvider.notifier);
    await settings.loaded;
    await settings.setSetting<String>(AppSettings.downloadDir, tmp.path, 'psx');
    return (c, c.read(catalogProvider.notifier));
  }

  List<String> shown(ProviderContainer c) => [for (final g in c.read(catalogProvider).paginatedFilteredGames) g.title];

  test('in launcher mode a console opens on the owned view: every version on disk, whatever the default filter hides', () async {
    File('${tmp.path}/${eu.filename}').writeAsStringSync('x');
    final (c, catalog) = await setUpCatalog(launcher: true);
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).filter.ownedOnly, isTrue);
    expect(shown(c), [eu.title]);
  });

  test('with launcher mode off a console opens with the owned view off, even after it was on', () async {
    final (c, catalog) = await setUpCatalog(launcher: false);
    catalog.updateFilter(const CatalogFilter(ownedOnly: true));
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).filter.ownedOnly, isFalse);
    expect(shown(c), containsAll([usa.title, crash.title]));
  });

  test('with nothing owned, the empty-result fallback keeps the owned view: an empty list is the answer', () async {
    final (c, catalog) = await setUpCatalog(launcher: true);
    await catalog.loadCatalog(_psx);
    final state = c.read(catalogProvider);
    expect(state.filter.ownedOnly, isTrue);
    expect(state.filter.regions, isEmpty, reason: 'the fallback ran');
    expect(state.filteredGamesCount, 0);
  });

  test('Clear and Reset keep the owned view', () async {
    File('${tmp.path}/${eu.filename}').writeAsStringSync('x');
    final (c, catalog) = await setUpCatalog(launcher: true);
    await catalog.loadCatalog(_psx);
    catalog.clearFilters();
    expect(c.read(catalogProvider).filter.ownedOnly, isTrue);
    expect(c.read(catalogProvider).filter.regions, isEmpty);
    catalog.defaultFilters();
    expect(c.read(catalogProvider).filter.ownedOnly, isTrue);
    expect(c.read(catalogProvider).filter.regions, {'USA'});
    await catalog.updateFilteredGames(immediate: true);
    expect(shown(c), [eu.title]);
  });

  test('a snapshot change filters an owned view again', () async {
    final (c, catalog) = await setUpCatalog(launcher: true);
    await catalog.loadCatalog(_psx);
    expect(shown(c), isEmpty);
    File('${tmp.path}/${crash.filename}').writeAsStringSync('x');
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    for (var i = 0; i < 100 && shown(c).isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(shown(c), [crash.title]);
  });

  test('the owned view toggles', () async {
    final (c, catalog) = await setUpCatalog(launcher: true);
    await catalog.loadCatalog(_psx);
    catalog.toggleOwnedOnly();
    expect(c.read(catalogProvider).filter.ownedOnly, isFalse);
    await catalog.updateFilteredGames(immediate: true);
    expect(shown(c), isNotEmpty);
    catalog.toggleOwnedOnly();
    expect(c.read(catalogProvider).filter.ownedOnly, isTrue);
  });

  test('the owned view, filters and sort carry over to the next console load; the search does not', () async {
    final (c, catalog) = await setUpCatalog(launcher: true);
    await catalog.loadCatalog(_psx);
    catalog.toggleOwnedOnly();
    catalog.setSort(CatalogSort.popular);
    catalog.updateFilter(c.read(catalogProvider).filter.copyWith(showFavoritesOnly: true));
    catalog.updateFilterText('crash');
    await catalog.loadCatalog(_psx);
    final state = c.read(catalogProvider);
    expect(state.filter.ownedOnly, isFalse);
    expect(state.filter.sort, CatalogSort.popular);
    expect(state.filter.showFavoritesOnly, isTrue);
    expect(state.filterText, isEmpty);
  });

  test('the filters, sort and owned view are kept across app starts; the search is not', () async {
    final (c, catalog) = await setUpCatalog(launcher: true);
    await catalog.loadCatalog(_psx);
    catalog.toggleOwnedOnly();
    catalog.setSort(CatalogSort.popular);
    catalog.updateFilter(c.read(catalogProvider).filter.copyWith(regions: {'Europe'}));
    catalog.updateFilterText('tekken');
    await pumpEventQueue();

    final (c2, catalog2) = await setUpCatalog(launcher: true, keepPrefs: true);
    await catalog2.loadCatalog(_psx);
    final state = c2.read(catalogProvider);
    expect(state.filter.ownedOnly, isFalse);
    expect(state.filter.sort, CatalogSort.popular);
    expect(state.filter.regions, {'Europe'});
    expect(state.filterText, isEmpty);
  });
}
