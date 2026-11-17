import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/game_update_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Queue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _Queue() : super(const TaskQueueState());
  final enqueued = <(String, TaskType, Map<String, dynamic>)>[];
  @override
  void enqueue(String taskId, TaskType type, Map<String, dynamic> params) => enqueued.add((taskId, type, params));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _game = Game(title: 'Base.zip', url: 'https://api.example.com/base', size: 1, consoleId: 'switch');
const _update = GameUpdate(label: 'v1', size: 1, url: 'https://api.example.com/update', fileName: 'Base [v1].nsz');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('t2scratch');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );
  tearDownAll(() => tmp.deleteSync(recursive: true));

  final roms = p.join(tmp.path, 'roms');

  setUpAll(() async {
    File(p.join(tmp.path, 'config', 'consoles.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'switch': {'name': 'Switch', 'decompress': 'unzip'},
      }));
    await CatalogService().getConsoles();
  });

  void prefs(Map<String, dynamic> consoles) => SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({
          'libraryEnabled': true,
          'generalSettings': {'downloadDir': roms},
          'consoleSettings': consoles,
        }),
      });

  Future<ProviderContainer> container(Map<String, dynamic> consoles, {_Queue? queue}) async {
    prefs(consoles);
    final c = ProviderContainer(overrides: [
      catalogProvider.overrideWith((_) => _FakeCatalog()),
      if (queue != null) taskQueueProvider.overrideWith((_) => queue),
    ]);
    addTearDown(c.dispose);
    await c.read(settingsProvider.notifier).loaded;
    return c;
  }

  // P2a: decompressFor ignores the catalog's decompress for updates.
  test('decompressFor: an update unpacks as the game unless the console chose', () async {
    var c = await container({});
    var n = c.read(settingsProvider.notifier);
    expect(n.decompressFor(_game), Decompress.unzip);
    expect(n.decompressFor(_update.toGame(_game)), Decompress.unzip);
    c = await container({
      'switch': {'updateDecompress': 'none'},
    });
    n = c.read(settingsProvider.notifier);
    expect(n.decompressFor(_game), Decompress.unzip);
    expect(n.decompressFor(_update.toGame(_game)), Decompress.none);
  });

  // P16: setSetting drops updatesDir.
  test('a chosen updates folder is kept', () async {
    final c = await container({});
    final n = c.read(settingsProvider.notifier);
    await n.setConsoleSetting<String>('switch', AppSettings.updatesDir, '/sd/u');
    expect(n.updatesDir('switch'), '/sd/u');
  });

  // P6: resolveState looks in the console folder for an update.
  test('an update reads as downloaded only when its file is in the updates folder', () async {
    File(p.join(roms, 'updates', _update.fileName)).createSync(recursive: true);
    File(p.join(roms, 'Elsewhere [v1].nsz')).createSync(recursive: true);
    addTearDown(() => Directory(roms).deleteSync(recursive: true));
    final c = await container({});
    final games = c.read(gameStateManagerProvider.notifier);
    final inUpdates = _update.toGame(_game);
    final inRoms = const GameUpdate(label: 'v1', size: 1, url: 'https://api.example.com/u2', fileName: 'Elsewhere [v1].nsz').toGame(_game);
    for (final g in [inUpdates, inRoms]) {
      games.registerTransientGame(g);
      games.resolveState(g.gameId);
    }
    Future<GameStatus> status(Game g) async {
      for (var i = 0; i < 200 && c.read(gameStateManagerProvider)[g.gameId]!.status == GameStatus.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return c.read(gameStateManagerProvider)[g.gameId]!.status;
    }

    expect(await status(inUpdates), GameStatus.downloaded);
    expect(await status(inRoms), isNot(GameStatus.downloaded));
  });

  // P8: startGameHandler asks the console, not the game.
  test('the handler queued after an update follows the update setting', () async {
    final queue = _Queue();
    final c = await container({
      'switch': {'additionalHandler': 'nsz_decompress', 'updateHandler': 'none'},
    }, queue: queue);
    final x = c.read(extractionProvider.notifier);
    x.startGameHandler('u', _update.toGame(_game), ['/r/a.nsz']);
    x.startGameHandler('g', _game, ['/r/a.nsz']);
    expect([for (final e in queue.enqueued) (e.$1, e.$3['handler'])], [('g', GameHandler.nszDecompress.id)]);
  });

  // P7: startDownloads enqueues every game with the console's folder.
  testWidgets('Download sends an update to the updates folder', (t) async {
    final queue = _Queue();
    prefs({});
    late WidgetRef ref;
    await t.pumpWidget(ProviderScope(
      overrides: [
        catalogProvider.overrideWith((_) => _FakeCatalog()),
        taskQueueProvider.overrideWith((_) => queue),
      ],
      child: MaterialApp(home: Consumer(builder: (_, r, __) {
        ref = r;
        return const SizedBox();
      })),
    ));
    await t.runAsync(() => ref.read(settingsProvider.notifier).loaded);
    final ctx = t.element(find.byType(SizedBox));
    await t.runAsync(() => TaskQueueService.startDownloads(ref, ctx, [_game, _update.toGame(_game)], 'switch'));
    expect([for (final e in queue.enqueued) e.$3['downloadDir']], [roms, p.join(roms, 'updates')]);
  });

  // P14: Game.copyWith drops isUpdate.
  test('a copy of an update is still an update', () {
    expect(_update.toGame(_game).copyWith(size: 2).isUpdate, isTrue);
  });

  // P15: changing the updates folder re-reads every game.
  test('choosing another updates folder resets the states', () async {
    final c = await container({});
    final games = c.read(gameStateManagerProvider.notifier);
    final u = _update.toGame(_game);
    games.registerTransientGame(u);
    games.resolveState(u.gameId);
    for (var i = 0; i < 200 && c.read(gameStateManagerProvider)[u.gameId]!.status == GameStatus.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.read(gameStateManagerProvider)[u.gameId]!.status, isNot(GameStatus.init));
    await c.read(settingsProvider.notifier).setConsoleSetting<String>('switch', AppSettings.updatesDir, '/sd/u');
    expect(c.read(gameStateManagerProvider)[u.gameId]!.status, GameStatus.init);
  });
}
