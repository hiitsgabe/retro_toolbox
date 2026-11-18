import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/services/game_groups.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalogService extends CatalogService {
  _FakeCatalogService(this.byConsole);
  final Map<String, List<Game>> byConsole;

  @override
  Future<List<Game>> loadCatalog(String consoleId,
          {String? iaAccessKey,
          String? iaSecretKey,
          String? authToken,
          void Function(int done, int total)? onProgress,
          void Function(String status)? onStatus}) async =>
      byConsole[consoleId]!;
}

Game _g(String title, {String console = 'psx', int size = 1}) =>
    Game(title: title, url: 'https://h/${Uri.encodeComponent(title)}.chd', size: size, consoleId: console);

const _psx = Console(id: 'psx', name: 'PSX', urls: []);
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('game_groups_owned');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<(ProviderContainer, CatalogNotifier)> setUpCatalog(Map<String, List<Game>> games, {Map<String, Directory> dirs = const {}}) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService(games))),
    ]);
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.loaded;
    for (final e in dirs.entries) {
      await settings.setSetting<String>(AppSettings.downloadDir, e.value.path, e.key);
    }
    return (container, container.read(catalogProvider.notifier));
  }

  String entry(ProviderContainer c) => c.read(catalogProvider).paginatedFilteredGames.single.title;

  Future<void> load(CatalogNotifier catalog, Console console) async {
    await catalog.loadCatalog(console);
    catalog.clearFilters();
    await catalog.updateFilteredGames(immediate: true);
  }

  // The re-pick runs on its own (async, in the main isolate): wait for it.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('a cancelled download stops being the entry on the next run', () async {
    final eu = _g('Game (Europe)');
    final (c, catalog) = await setUpCatalog({
      'psx': [_g('Game (USA)'), eu]
    });
    final manager = c.read(gameStateManagerProvider.notifier);
    await load(catalog, _psx);
    manager.state = {...manager.state, eu.gameId: GameState(game: eu, status: GameStatus.downloading)};
    await catalog.updateFilteredGames(immediate: true);
    expect(entry(c), 'Game (Europe)');
    manager.state = {...manager.state, eu.gameId: GameState(game: eu, status: GameStatus.ready)};
    await catalog.updateFilteredGames(immediate: true);
    expect(entry(c), 'Game (USA)');
    expect(c.read(inFlightGameIdsProvider), isEmpty);
  });

  test('after a console switch, the new console\'s version on disk is the entry', () async {
    final psxDir = Directory.systemTemp.createTempSync('owned_psx');
    final ps2Dir = Directory.systemTemp.createTempSync('owned_ps2');
    addTearDown(() => psxDir.deleteSync(recursive: true));
    addTearDown(() => ps2Dir.deleteSync(recursive: true));
    File('${ps2Dir.path}/Game (Europe).chd').writeAsStringSync('x');
    final (c, catalog) = await setUpCatalog({
      'psx': [_g('Game (USA)'), _g('Game (Europe)')],
      'ps2': [_g('Game (USA)', console: 'ps2'), _g('Game (Europe)', console: 'ps2')],
    }, dirs: {
      'psx': psxDir,
      'ps2': ps2Dir
    });
    await load(catalog, _psx);
    expect(entry(c), 'Game (USA)');
    await load(catalog, _ps2);
    expect(c.read(catalogProvider).paginatedFilteredGames.single.gameId, 'ps2/Game (Europe).chd');
  });

  test('a version extracted to its folder is owned; one in another folder is not', () async {
    final dir = Directory.systemTemp.createTempSync('owned_folder');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/Game (Europe)').createSync();
    File('${dir.path}/Game (Europe)/Game (Europe).cue').writeAsStringSync('x');
    Directory('${dir.path}/updates').createSync();
    File('${dir.path}/updates/Other (Europe).chd').writeAsStringSync('x');
    final (c, catalog) = await setUpCatalog({
      'psx': [_g('Game (USA)'), _g('Game (Europe)'), _g('Other (USA)'), _g('Other (Europe)')],
    }, dirs: {
      'psx': dir
    });
    await load(catalog, _psx);
    expect([for (final g in c.read(catalogProvider).paginatedFilteredGames) g.title], ['Game (Europe)', 'Other (USA)']);
  });

  test('a root extraction (cue/bin beside nothing) and a chd conversion are owned', () async {
    final dir = Directory.systemTemp.createTempSync('owned_root');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/Game (Europe).cue').writeAsStringSync('x');
    File('${dir.path}/Game (Europe).bin').writeAsStringSync('x');
    final (c, catalog) = await setUpCatalog({
      'psx': [
        Game(title: 'Game (USA)', url: 'https://h/Game%20(USA).zip', size: 1, consoleId: 'psx'),
        Game(title: 'Game (Europe)', url: 'https://h/Game%20(Europe).zip', size: 1, consoleId: 'psx'),
      ],
    }, dirs: {
      'psx': dir
    });
    await load(catalog, _psx);
    expect(entry(c), 'Game (Europe)');
  });

  test('a file the app removes stops owning on the next run', () async {
    final dir = Directory.systemTemp.createTempSync('owned_removed');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/Game (Europe).chd').writeAsStringSync('x');
    final (c, catalog) = await setUpCatalog({
      'psx': [_g('Game (USA)'), _g('Game (Europe)')]
    }, dirs: {
      'psx': dir
    });
    await load(catalog, _psx);
    expect(entry(c), 'Game (Europe)');
    c.read(librarySnapshotProvider(dir.path).notifier).markFileRemoved('Game (Europe).chd');
    await catalog.updateFilteredGames(immediate: true);
    expect(entry(c), 'Game (USA)');
  });

  test('a finished download of another version switches the shown entry in place, with no filter run', () async {
    final dir = Directory.systemTemp.createTempSync('owned_stale');
    addTearDown(() => dir.deleteSync(recursive: true));
    final eu = _g('Game (Europe)');
    final (c, catalog) = await setUpCatalog({
      'psx': [_g('Game (USA)'), eu]
    }, dirs: {
      'psx': dir
    });
    final manager = c.read(gameStateManagerProvider.notifier);
    await load(catalog, _psx);
    expect(entry(c), 'Game (USA)');
    final before = c.read(catalogProvider).paginatedFilteredGames;
    manager.state = {...manager.state, eu.gameId: GameState(game: eu, status: GameStatus.downloading)};
    await until(() => entry(c) == 'Game (Europe)');
    expect(entry(c), 'Game (Europe)', reason: 'a download starting');
    File('${dir.path}/Game (Europe).chd').writeAsStringSync('x');
    c.read(librarySnapshotProvider(dir.path).notifier).markFileAdded('Game (Europe).chd');
    manager.state = {...manager.state, eu.gameId: GameState(game: eu, status: GameStatus.downloaded)};
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(entry(c), 'Game (Europe)', reason: 'and finished: it stays');
    expect(c.read(catalogProvider).paginatedFilteredGames, isNot(same(before)));
    expect(c.read(catalogProvider).paginatedFilteredGames.single.group!.title, 'Game');
  });

  test('a re-pick keeps the order and the pages', () async {
    final games = [
      for (var i = 0; i < 70; i++) ...[_g('G${i.toString().padLeft(2, '0')} (USA)'), _g('G${i.toString().padLeft(2, '0')} (Europe)')]
    ];
    final (c, catalog) = await setUpCatalog({'psx': games});
    await load(catalog, _psx);
    final shown = c.read(catalogProvider).paginatedFilteredGames;
    expect(shown, hasLength(kDefaultCatalogDisplaySize));
    c.read(inFlightGameIdsProvider.notifier).state = {'psx/G03 (Europe).chd'};
    await until(() => c.read(catalogProvider).paginatedFilteredGames[3].title.contains('Europe'));
    final after = c.read(catalogProvider).paginatedFilteredGames;
    expect([for (final g in after) g.group!.title], [for (final g in shown) g.group!.title]);
    expect(after[3].title, 'G03 (Europe)');
    expect([
      for (var i = 0; i < after.length; i++)
        if (i != 3) after[i]
    ], [
      for (var i = 0; i < shown.length; i++)
        if (i != 3) shown[i]
    ], reason: 'only the changed entry is replaced');
    expect(c.read(catalogProvider).hasMoreItems, isTrue);
  });

  // Pages are separate filter runs; one list keeps one owned set.
  test('under a size sort, an owned change between two pages shows no game twice and loses none', () async {
    final games = [
      for (var i = 0; i < 70; i++) ...[
        _g('G${i.toString().padLeft(2, '0')} (USA)', size: 1000 - i * 10),
        _g('G${i.toString().padLeft(2, '0')} (Europe)', size: 5),
      ],
    ];
    final (c, catalog) = await setUpCatalog({'psx': games});
    await load(catalog, _psx);
    catalog.setSort(CatalogSort.sizeDesc);
    await catalog.updateFilteredGames(immediate: true);
    // G00's Europe version starts downloading after page 1 was listed.
    c.read(inFlightGameIdsProvider.notifier).state = {'psx/G00 (Europe).chd'};
    await until(() => c.read(catalogProvider).paginatedFilteredGames.first.title.contains('Europe'));
    await catalog.loadMoreItems();
    final titles = [for (final g in c.read(catalogProvider).paginatedFilteredGames) g.group!.title];
    expect(titles, hasLength(70));
    expect(titles.toSet(), hasLength(70), reason: 'every game once');
  });

  test('a title is parsed once: the same tags object comes back', () {
    final g = _g('Game (USA) (Rev 1)');
    expect(identical(tagsOf(g), tagsOf(g)), isTrue);
    expect(tagsOf(g), ['USA', 'Rev 1']);
  });

  test('groups are built once per list: typing reuses them, a new list rebuilds', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(
          ref,
          _FakeCatalogService({
            'psx': [_g('Game (USA)'), _g('Game (Europe)')],
            'ps2': [_g('Game (USA)', console: 'ps2')],
          }))),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).loaded;
    final catalog = container.read(catalogProvider.notifier);
    await catalog.loadCatalog(_psx);
    expect(catalog.debugGroupBuilds, 1);
    for (final text in ['G', 'Ga', 'Gam']) {
      catalog.updateFilterText(text);
      await catalog.updateFilteredGames(immediate: true);
    }
    expect(catalog.debugGroupBuilds, 1, reason: 'a keystroke reuses the groups');
    await catalog.loadCatalog(_ps2);
    expect(catalog.debugGroupBuilds, 2, reason: 'another console builds its own');
    await catalog.loadCatalog(_psx);
    expect(catalog.debugGroupBuilds, 3, reason: 'a reload is a new list');
    expect(container.read(catalogProvider).paginatedFilteredGames.single.consoleId, 'psx');
  });
}
