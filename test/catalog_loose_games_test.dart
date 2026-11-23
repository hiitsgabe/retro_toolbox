import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers [games], or throws [error] when it is set.
class _FakeCatalogService extends CatalogService {
  _FakeCatalogService(this.games, {this.error});
  final List<Game> games;
  final Object? error;

  @override
  Future<List<Game>> loadCatalog(String consoleId,
      {String? iaAccessKey,
      String? iaSecretKey,
      String? authToken,
      void Function(int done, int total)? onProgress,
      void Function(String status)? onStatus}) async {
    if (error != null) throw error!;
    return games;
  }
}

/// Records the titles each enrich got, and gives every game a genre so the
/// list shows it was enriched.
class _RecordingLaunchbox extends LaunchboxService {
  final enriched = <List<String>>[];

  @override
  Future<List<Game>> enrich(Console console, List<Game> games, {bool useCovers = false}) async {
    enriched.add([for (final g in games) g.title]);
    return [for (final g in games) g.copyWith(details: const GameDetails(genres: ['Action']))];
  }
}

class MemoryConfig implements LaunchConfigStore {
  MemoryConfig(this.enabled);
  final bool enabled;

  @override
  Future<LaunchConfig> load() async => LaunchConfig(enabled: enabled);

  @override
  Future<void> save(LaunchConfig config) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _psx = Console(id: 'psx', name: 'PlayStation', urls: [], originalFormat: ['.chd']);
const _crash = Game(title: 'Crash Bandicoot (USA)', url: 'https://example.com/Crash%20Bandicoot%20(USA).chd', size: 1, consoleId: 'psx');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late _RecordingLaunchbox launchbox;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt-loose-catalog-');
    launchbox = _RecordingLaunchbox();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  void touch(String name) => File(p.join(tmp.path, name)).writeAsStringSync('x');

  Future<(ProviderContainer, CatalogNotifier)> setUpCatalog({bool launcher = true, List<Game> games = const [_crash], Object? error, String? dir}) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService(games, error: error))),
      launcherAvailableProvider.overrideWithValue(true),
      launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(launcher))),
      launchboxServiceProvider.overrideWithValue(launchbox),
    ]);
    addTearDown(c.dispose);
    final settings = c.read(settingsProvider.notifier);
    await settings.loaded;
    await settings.setSetting<String>(AppSettings.downloadDir, dir ?? tmp.path, 'psx');
    return (c, c.read(catalogProvider.notifier));
  }

  List<String> shown(ProviderContainer c) => [for (final g in c.read(catalogProvider).paginatedFilteredGames) g.title];
  List<String> loose(ProviderContainer c) => [for (final g in c.read(catalogProvider).games) if (g.isLocal) g.title];

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('in launcher mode the loose games join the list before LaunchBox matching, in one enrich', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog();
    await catalog.loadCatalog(_psx);
    expect(launchbox.enriched, [
      ['Crash Bandicoot (USA)', 'Spyro (USA)'],
    ]);
    final spyro = c.read(catalogProvider).games.singleWhere((g) => g.isLocal);
    expect(spyro.details?.genres, ['Action']);
    expect(shown(c), ['Spyro (USA)'], reason: 'the owned view');
    expect(c.read(ownedLibraryProvider('psx')).paths[spyro.gameId], [p.join(tmp.path, 'Spyro (USA).chd')]);
  });

  test('a LaunchBox reapply matches the loose games again with the rest', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog();
    await catalog.loadCatalog(_psx);
    await catalog.reapplyLaunchbox();
    expect(launchbox.enriched.last, ['Crash Bandicoot (USA)', 'Spyro (USA)']);
    expect(c.read(catalogProvider).games.where((g) => g.isLocal), hasLength(1));
  });

  test('with launcher mode off no loose game is listed', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(launcher: false);
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).games.map((g) => g.title), ['Crash Bandicoot (USA)']);
  });

  test('an empty catalog with loose games shows the loose games, not the error', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(games: const []);
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).errorMessage, isEmpty);
    expect(shown(c), ['Spyro (USA)']);
  });

  test('a failed catalog with loose games shows the loose games; without any, the error', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(error: Exception('HTTP 503'));
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).errorMessage, isEmpty);
    expect(shown(c), ['Spyro (USA)']);
    File(p.join(tmp.path, 'Spyro (USA).chd')).deleteSync();
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).errorMessage, contains('HTTP 503'));
  });

  test('with launcher mode off a failed catalog is the error, as before', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(launcher: false, error: Exception('HTTP 503'));
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).errorMessage, 'Failed to load catalog: Exception: HTTP 503');
  });

  test('in launcher mode a library dir that cannot be read says so', () async {
    final locked = Directory(p.join(tmp.path, 'locked'))..createSync();
    Process.runSync('chmod', ['000', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
    final (c, catalog) = await setUpCatalog(dir: locked.path);
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).errorMessage, 'Cannot read ${locked.path}');
    expect(c.read(catalogProvider).loading, isFalse);
  });

  test('launcher mode turning off over a failed catalog shows the failure again, not the loose games it took away', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(error: Exception('HTTP 503'));
    await catalog.loadCatalog(_psx);
    expect(shown(c), ['Spyro (USA)']);
    await c.read(launchConfigProvider.notifier).setEnabled(false);
    await until(() => !c.read(catalogProvider).filter.ownedOnly);
    expect(c.read(catalogProvider).games, isEmpty);
    expect(shown(c), isEmpty, reason: 'the loose game is gone from the list, not only from the games');
    expect(c.read(catalogProvider).errorMessage, 'Failed to load catalog: Exception: HTTP 503');
  });

  test('launcher mode turning off over an empty catalog says it found no games, as it does with the mode off', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(games: const []);
    await catalog.loadCatalog(_psx);
    await c.read(launchConfigProvider.notifier).setEnabled(false);
    await until(() => c.read(catalogProvider).errorMessage.isNotEmpty);
    expect(c.read(catalogProvider).errorMessage, 'No games found for PlayStation. The catalog source may be unavailable, try again later.');
  });

  test('the last loose game of a failed catalog going away shows the failure again', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(error: Exception('HTTP 503'));
    await catalog.loadCatalog(_psx);
    expect(shown(c), ['Spyro (USA)']);
    File(p.join(tmp.path, 'Spyro (USA).chd')).deleteSync();
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    await until(() => c.read(catalogProvider).errorMessage.isNotEmpty);
    expect(c.read(catalogProvider).games, isEmpty);
    expect(shown(c), isEmpty);
    expect(c.read(catalogProvider).errorMessage, 'Failed to load catalog: Exception: HTTP 503');
  });

  test('launcher mode turning off takes the loose games and the owned view away, and a library change scans nothing', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog();
    await catalog.loadCatalog(_psx);
    expect(c.read(catalogProvider).filter.ownedOnly, isTrue);
    await c.read(launchConfigProvider.notifier).setEnabled(false);
    await until(() => shown(c).contains('Crash Bandicoot (USA)'));
    expect(loose(c), isEmpty);
    expect(c.read(catalogProvider).filter.ownedOnly, isFalse);
    expect(shown(c), ['Crash Bandicoot (USA)']);
    final scans = catalog.debugLooseScans;
    touch('Tekken 3 (USA).chd');
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(catalog.debugLooseScans, scans, reason: 'the listener reads the mode now, not at load');
    expect(loose(c), isEmpty);
  });

  test('launcher mode turning off while a library change is being scanned keeps what that scan finds away', () async {
    final (c, catalog) = await setUpCatalog();
    await catalog.loadCatalog(_psx);
    touch('Spyro (USA).chd');
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    await c.read(launchConfigProvider.notifier).setEnabled(false);
    await until(() => !c.read(catalogProvider).filter.ownedOnly);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(loose(c), isEmpty);
  });

  test('launcher mode turning on with a console loaded lists its loose games at the next library change', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(launcher: false);
    await catalog.loadCatalog(_psx);
    expect(loose(c), isEmpty);
    await c.read(launchConfigProvider.notifier).setEnabled(true);
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    // Shown, not only listed: the LaunchBox reapply after the relist has ended.
    await until(() => shown(c).contains('Spyro (USA)'));
    expect(loose(c), ['Spyro (USA)']);
  });

  test('each load replaces its library listener: a change scans once, however many loads came before', () async {
    final (c, catalog) = await setUpCatalog();
    await catalog.loadCatalog(_psx);
    await catalog.loadCatalog(_psx);
    final scans = catalog.debugLooseScans;
    touch('Spyro (USA).chd');
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    await until(() => shown(c).isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(catalog.debugLooseScans - scans, 1);
  });

  test('a rescan that finds a new loose file lists it, and one that finds the same set changes nothing', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog();
    await catalog.loadCatalog(_psx);
    final before = c.read(catalogProvider).games;
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(identical(c.read(catalogProvider).games, before), isTrue);
    touch('Tekken 3 (USA).chd');
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    for (var i = 0; i < 100 && shown(c).length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(shown(c), ['Spyro (USA)', 'Tekken 3 (USA)']);
    expect(launchbox.enriched.last, ['Crash Bandicoot (USA)', 'Spyro (USA)', 'Tekken 3 (USA)']);
  });

  test('rescanLibrary reads the loaded console\'s dir again, and the list follows', () async {
    final (c, catalog) = await setUpCatalog();
    await catalog.rescanLibrary();
    await catalog.loadCatalog(_psx);
    expect(shown(c), isEmpty);
    touch('Spyro (USA).chd');
    await catalog.rescanLibrary();
    for (var i = 0; i < 100 && shown(c).isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(shown(c), ['Spyro (USA)']);
  });
}
