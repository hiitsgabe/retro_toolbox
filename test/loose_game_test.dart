import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_target.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/services/launcher/owned_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _psx = Console(id: 'psx', name: 'PlayStation', urls: [], gameFilesFormat: ['.cue', '.bin'], additionalHandler: GameHandler.chdCompress);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt-loose-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  void touch(String rel) => File(p.join(tmp.path, rel)).createSync(recursive: true);

  /// A container whose PlayStation library dir is [tmp], with the loose games
  /// found there published as the catalog would.
  Future<(ProviderContainer, OwnedLibrary)> setUpLoose() async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final settings = c.read(settingsProvider.notifier);
    await settings.loaded;
    await settings.setSetting<String>(AppSettings.downloadDir, tmp.path, 'psx');
    final snapshot = await LibrarySnapshotNotifier(tmp.path).current();
    final lib = await OwnedLibrary.scan((consoleId: 'psx', dir: tmp.path, formats: _psx.onDiskFormats, snapshot: snapshot, catalog: const [], folders: true, skip: const {}));
    c.read(ownedLibraryProvider('psx').notifier).state = lib;
    return (c, lib);
  }

  test('a name sanitizeForFat changed resolves to its real file', () async {
    touch('Metroid Prime 4: Beyond (Disc 1).chd');
    touch('Metroid Prime 4: Beyond (Disc 2).chd');
    final snapshot = await LibrarySnapshotNotifier(tmp.path).current();
    final lib = await OwnedLibrary.scan((consoleId: 'psx', dir: tmp.path, formats: _psx.onDiskFormats, snapshot: snapshot, catalog: const [], folders: true, skip: const {}));
    final owned = OwnedGame.fromLoose(lib.games.single, tmp.path, lib.paths)!;
    final target = resolveLaunchTarget(owned, const PresetSystem(slug: 'psx', extensions: ['chd']));
    expect(target.path, p.join(tmp.path, 'Metroid Prime 4: Beyond (Disc 1).chd'));
  });

  test('ownedGameProvider reads a loose game\'s files from the side map', () async {
    touch('Metroid Prime 4: Beyond.chd');
    final (c, lib) = await setUpLoose();
    final owned = await c.read(ownedGameProvider(lib.games.single).future);
    expect(owned?.dir, tmp.path);
    expect(owned?.paths, [p.join(tmp.path, 'Metroid Prime 4: Beyond.chd')]);
  });

  test('a loose game the side map does not hold has no files', () async {
    final (c, _) = await setUpLoose();
    final gone = Game(title: 'Gone', url: localGameUrl('psx', 'Gone.chd'), size: 0, consoleId: 'psx');
    expect(await c.read(ownedGameProvider(gone).future), isNull);
  });

  test('a loose game reads as on disk, a folder as extracted, and one whose name sanitizeForFat changed never offers a download', () async {
    touch('Metroid Prime 4: Beyond.chd');
    touch('Spyro (USA).chd');
    touch('Vagrant Story/Vagrant Story.cue');
    final (c, lib) = await setUpLoose();
    final manager = c.read(gameStateManagerProvider.notifier);
    for (final game in lib.games) {
      manager.registerTransientGame(game);
      manager.resolveState(game.gameId);
    }
    bool resolving(Game g) => const {GameStatus.init, GameStatus.loading}.contains(c.read(gameStateManagerProvider)[g.gameId]?.status);
    for (var i = 0; i < 200 && lib.games.any(resolving); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    const expected = {'Metroid Prime 4: Beyond': GameStatus.downloaded, 'Spyro (USA)': GameStatus.downloaded, 'Vagrant Story': GameStatus.extracted};
    expect({for (final g in lib.games) g.title: c.read(gameStateManagerProvider)[g.gameId]?.status}, expected);
    for (final game in lib.games) {
      expect(c.read(gameStateManagerProvider)[game.gameId]!.availableActions, isNot(contains(GameAction.download)), reason: game.title);
    }
  });

  test('a catalog game not on disk still reads as ready, with its download', () async {
    final (c, _) = await setUpLoose();
    const game = Game(title: 'Crash (USA)', url: 'https://example.com/Crash%20(USA).chd', size: 1, consoleId: 'psx');
    final manager = c.read(gameStateManagerProvider.notifier)
      ..registerTransientGame(game)
      ..resolveState(game.gameId);
    for (var i = 0; i < 200 && c.read(gameStateManagerProvider)[game.gameId]?.status != GameStatus.ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(manager.state[game.gameId]?.availableActions, {GameAction.download});
  });
}
