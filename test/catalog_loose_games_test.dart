import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers [games] (a console in [others], its own), or throws [error] when
/// it is set.
class _FakeCatalogService extends CatalogService {
  _FakeCatalogService(this.games, {this.error, this.others = const {}});
  final List<Game> games;
  final Object? error;
  final Map<String, List<Game>> others;

  @override
  Future<List<Game>> loadCatalog(String consoleId,
      {String? iaAccessKey,
      String? iaSecretKey,
      String? authToken,
      void Function(int done, int total)? onProgress,
      void Function(String status)? onStatus}) async {
    if (error != null) throw error!;
    return others[consoleId] ?? games;
  }
}

/// Records the titles each enrich got, and gives every game a genre so the
/// list shows it was enriched. While [hold] is set, an enrich waits for it.
class _RecordingLaunchbox extends LaunchboxService {
  final enriched = <List<String>>[];
  Completer<void>? hold;

  @override
  Future<List<Game>> enrich(Console console, List<Game> games, {bool useCovers = false}) async {
    enriched.add([for (final g in games) g.title]);
    await hold?.future;
    return [for (final g in games) g.copyWith(details: const GameDetails(genres: ['Action']))];
  }
}

/// The app's console list, as the console grid reads it.
class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp(super.state);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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
const _snes = Console(id: 'snes', name: 'Super Nintendo', urls: [], originalFormat: ['.sfc']);
const _mario = Game(title: 'Super Mario World (USA)', url: 'https://example.com/Super%20Mario%20World%20(USA).sfc', size: 1, consoleId: 'snes');

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

  Future<(ProviderContainer, CatalogNotifier)> setUpCatalog(
      {bool launcher = true, List<Game> games = const [_crash], Object? error, String? dir, List<Console> consoles = const [_psx, _snes]}) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      appStateProvider.overrideWith((ref) => _FakeApp(AppState(consoles: {for (final c in consoles) c.id: c}))),
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService(games, error: error, others: const {'snes': [_mario]}))),
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

  /// Turns launcher mode [on] and returns once its listeners heard it: the
  /// catalog's included, since they are told together.
  Future<void> setMode(ProviderContainer c, bool on) async {
    var heard = false;
    final sub = c.listen<bool>(launcherModeProvider, (_, now) => heard = now == on);
    await c.read(launchConfigProvider.notifier).setEnabled(on);
    await until(() => heard);
    sub.close();
    expect(heard, isTrue);
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

  test('in a dir another console shares, a file of an extension both list is no loose game, as on the console grid', () async {
    const psx = Console(id: 'psx', name: 'PlayStation', urls: [], originalFormat: ['.chd', '.cue']);
    const ps2 = Console(id: 'ps2', name: 'PlayStation 2', urls: [], gameFilesFormat: ['.iso', '.chd']);
    touch('Spyro (USA).chd');
    touch('Tekken 3 (USA).cue');
    final (c, catalog) = await setUpCatalog(consoles: const [psx, ps2]);
    await c.read(settingsProvider.notifier).setSetting<String>(AppSettings.downloadDir, tmp.path, 'ps2');
    await catalog.loadCatalog(psx);
    expect(loose(c), ['Tekken 3 (USA)']);
    expect(await c.read(gamesOnDiskProvider('ps2').future), isFalse, reason: 'the grid agrees: the .chd is no one\'s');
  });

  test('a file whose real name sanitizeForFat turns into a catalog game\'s shows as that game, owned and launchable from its real path', () async {
    const metroid = Game(title: 'Metroid Prime 4 Beyond', url: 'https://example.com/Metroid%20Prime%204%20Beyond.chd', size: 1, consoleId: 'psx');
    touch('Metroid Prime 4: Beyond.chd');
    final (c, catalog) = await setUpCatalog(games: const [_crash, metroid]);
    await catalog.loadCatalog(_psx);
    expect(loose(c), isEmpty);
    expect(shown(c), ['Metroid Prime 4 Beyond'], reason: 'the owned view');
    expect(await catalog.ownedGameIds(), {metroid.gameId}, reason: 'Download all leaves it out, as any game on disk');
    final owned = await c.read(ownedGameProvider(metroid).future);
    expect(owned?.paths, [p.join(tmp.path, 'Metroid Prime 4: Beyond.chd')]);
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

  test('launcher mode turning off while a console loads leaves it with no loose game and no owned view', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog();
    final hold = launchbox.hold = Completer<void>();
    final load = catalog.loadCatalog(_psx);
    await until(() => launchbox.enriched.isNotEmpty);
    expect(launchbox.enriched.single, contains('Spyro (USA)'), reason: 'the load scanned in launcher mode');
    await setMode(c, false);
    hold.complete();
    await load;
    expect(loose(c), isEmpty);
    expect(c.read(catalogProvider).filter.ownedOnly, isFalse);
    expect(shown(c), ['Crash Bandicoot (USA)']);
  });

  test('launcher mode turning off while a failed catalog loads on its loose games shows the failure', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(error: Exception('HTTP 503'));
    final hold = launchbox.hold = Completer<void>();
    final load = catalog.loadCatalog(_psx);
    await until(() => launchbox.enriched.isNotEmpty);
    await setMode(c, false);
    hold.complete();
    await load;
    expect(c.read(catalogProvider).games, isEmpty);
    expect(c.read(catalogProvider).errorMessage, 'Failed to load catalog: Exception: HTTP 503');
    expect(c.read(catalogProvider).loading, isFalse);
  });

  test('launcher mode turning on while a console loads opens it on the owned view, with its loose games', () async {
    touch('Spyro (USA).chd');
    final (c, catalog) = await setUpCatalog(launcher: false);
    // Read before the load, as the app has it: the first read is a library
    // change the list would follow anyway.
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    final hold = launchbox.hold = Completer<void>();
    final load = catalog.loadCatalog(_psx);
    await until(() => launchbox.enriched.isNotEmpty);
    expect(launchbox.enriched.single, ['Crash Bandicoot (USA)'], reason: 'the load scanned nothing, the mode was off');
    await setMode(c, true);
    hold.complete();
    await load;
    expect(c.read(catalogProvider).filter.ownedOnly, isTrue);
    await until(() => shown(c).isNotEmpty);
    expect(loose(c), ['Spyro (USA)']);
    expect(shown(c), ['Spyro (USA)']);
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

  test('a library change still being scanned when another console opens never lists the first console\'s games there', () async {
    touch('Spyro (USA).chd');
    final snesDir = Directory(p.join(tmp.path, 'snes'))..createSync();
    final (c, catalog) = await setUpCatalog();
    await c.read(settingsProvider.notifier).setSetting<String>(AppSettings.downloadDir, snesDir.path, 'snes');
    await catalog.loadCatalog(_psx);
    expect(loose(c), ['Spyro (USA)']);
    touch('Tekken 3 (USA).chd');
    await c.read(librarySnapshotProvider(tmp.path).notifier).refresh();
    await catalog.loadCatalog(_snes);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(loose(c), isEmpty);
    expect(c.read(catalogProvider).games.map((g) => g.title), ['Super Mario World (USA)']);
  });

  test('a file that came or went outside the app changes what its game offers at the next rescan, not only the owned view', () async {
    final (c, catalog) = await setUpCatalog();
    c.read(gameStateManagerProvider);
    await catalog.loadCatalog(_psx);
    catalog.toggleOwnedOnly();
    final crash = c.read(catalogProvider).games.singleWhere((g) => g.title == _crash.title);
    final sub = c.listen(gameStateProvider(crash), (_, __) {});
    addTearDown(sub.close);
    GameState state() => c.read(gameStateProvider(crash));
    await until(() => state().status == GameStatus.ready);
    expect(state().availableActions, {GameAction.download}, reason: 'seen before the file came');

    touch(crash.filename);
    await catalog.rescanLibrary();
    await until(() => state().status != GameStatus.ready);
    expect(state().status, GameStatus.downloaded);
    expect(state().availableActions, isNot(contains(GameAction.download)));

    File(p.join(tmp.path, crash.filename)).deleteSync();
    await catalog.rescanLibrary();
    await until(() => state().status != GameStatus.downloaded);
    expect(state().status, GameStatus.ready);
    expect(state().availableActions, {GameAction.download});
  });

  test('a rescan leaves a game with a task running as the task has it', () async {
    final (c, catalog) = await setUpCatalog();
    c.read(gameStateManagerProvider);
    await catalog.loadCatalog(_psx);
    final crash = c.read(catalogProvider).games.singleWhere((g) => g.title == _crash.title);
    final sub = c.listen(gameStateProvider(crash), (_, __) {});
    addTearDown(sub.close);
    await until(() => c.read(gameStateProvider(crash)).status == GameStatus.ready);
    c.read(gameStateManagerProvider.notifier).updateQueueState(crash.gameId, TaskType.download);
    touch(crash.filename);
    await catalog.rescanLibrary();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.read(gameStateProvider(crash)).status, GameStatus.downloadQueued);
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
