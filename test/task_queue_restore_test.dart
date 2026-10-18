import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => '/tmp');

  Game game(String name) => Game(title: name, url: 'https://h/$name', size: 10, consoleId: 'c');

  // No download slots: queued downloads stay waiting, nothing hits the downloader.
  Future<ProviderContainer> start() async {
    final c = ProviderContainer();
    await c.read(settingsProvider.notifier).loaded;
    await c.read(taskQueueProvider.notifier).restored;
    return c;
  }

  setUp(() => SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({
          'generalSettings': {'maxParallelDownloads': 0},
        }),
      }));

  test('downloads waiting in the queue come back after the app restarts', () async {
    final first = await start();
    for (final g in [game('a.zip'), game('b.zip')]) {
      first.read(gameStateManagerProvider.notifier).registerTransientGame(g);
      first.read(taskQueueProvider.notifier).enqueue(g.gameId, TaskType.download, {'game': g.toJson(), 'downloadDir': '/d', 'group': 'c'});
    }
    first.dispose(); // the app dies

    final second = await start();
    addTearDown(second.dispose);
    final waiting = second.read(taskQueueProvider).tasks.where((t) => t.status == TaskQueueStatus.waiting);
    expect(waiting.map((t) => t.id), ['c/a.zip', 'c/b.zip']);
    expect(waiting.first.params['downloadDir'], '/d');
    expect(second.read(gameStateManagerProvider)['c/a.zip']?.status, GameStatus.downloadQueued);
  });

  test('a cancelled queued download does not come back', () async {
    final first = await start();
    final g = game('a.zip');
    first.read(gameStateManagerProvider.notifier).registerTransientGame(g);
    first.read(taskQueueProvider.notifier).enqueue(g.gameId, TaskType.download, {'game': g.toJson(), 'downloadDir': '/d', 'group': 'c'});
    first.read(taskQueueProvider.notifier).cancelQueuedTask(g.gameId);
    first.dispose();

    final second = await start();
    addTearDown(second.dispose);
    expect(second.read(taskQueueProvider).tasks, isEmpty);
  });
}
