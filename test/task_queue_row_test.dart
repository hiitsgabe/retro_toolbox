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
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => '/tmp');

  // No download slots: the task stays queued, nothing hits the downloader.
  setUp(() => SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({
          'generalSettings': {'maxParallelDownloads': 0},
        }),
      }));

  test('a download of a game outside the loaded catalog gets a task-manager row', () async {
    // The sport patcher queues the game it found in the library without
    // browsing that console, so no catalog ever gave the game a state; the
    // download ran unseen and leaving the patcher lost its progress.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(settingsProvider.notifier).loaded;
    await c.read(taskQueueProvider.notifier).restored;
    const g = Game(title: 'NHL 2005', url: 'https://h/nhl05.zip', size: 10, consoleId: 'ps2');
    expect(c.read(gameStateManagerProvider)[g.gameId], isNull);

    c.read(taskQueueProvider.notifier).enqueue(g.gameId, TaskType.download, {'game': g.toJson(), 'downloadDir': '/d', 'group': 'ps2'});

    final row = c.read(gameStateManagerProvider)[g.gameId];
    expect(row?.status, GameStatus.downloadQueued);
    expect(row?.game.title, 'NHL 2005');
    expect(classifyTasks(c.read(gameStateManagerProvider).values).queued.map((s) => s.game.gameId), ['ps2/nhl05.zip']);
  });
}
