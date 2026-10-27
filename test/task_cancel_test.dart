import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/file_ops.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Directory root;

String at(String rel) => p.join(root.path, rel);

File random(String rel, int bytes) {
  final r = Random(1);
  return File(at(rel))
    ..createSync(recursive: true)
    ..writeAsBytesSync([for (var i = 0; i < bytes; i++) r.nextInt(256)]);
}

void stop(int done, int total) => throw const TaskCancelledException();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('cancel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('a cancelled copy stops, leaves no partial copy and keeps the source', () async {
    random('src/big.bin', 1 << 20);
    await expectLater(FileOps.copyInto([at('src/big.bin')], at('dst'), onProgress: stop), throwsA(isA<TaskCancelledException>()));
    expect(File(at('src/big.bin')).lengthSync(), 1 << 20);
    expect(File(at('dst/big.bin')).existsSync(), isFalse);
  });

  test('a cancelled zip stops and deletes the partial zip', () async {
    random('src/big.bin', 4 << 20);
    await expectLater(FileOps.zip([at('src/big.bin')], at('out.zip'), onProgress: stop), throwsA(isA<TaskCancelledException>()));
    expect(File(at('out.zip')).existsSync(), isFalse);
  });

  /// Waits (in real time, a full suite can be slow) until [done] holds.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 250 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
  }

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('cancelling a running job removes it at once, stops it at its next progress, and reports no failure', () async {
    final c = container();
    const game = Game(title: 'Copy x', url: 'https://manual/op-1.task', size: 0, consoleId: 'manual');
    c.read(gameStateManagerProvider.notifier).registerTransientGame(game);
    final gate = Completer<void>();
    Object? stoppedWith;
    c.read(taskQueueProvider.notifier).enqueue(game.gameId, TaskType.remoteTransfer, {
      'taskId': game.gameId,
      'verb': 'Copying',
      'label': 'x',
      'run': (FileOpsProgress onProgress) async {
        onProgress(1, 10);
        await gate.future;
        try {
          onProgress(2, 10);
        } catch (e) {
          stoppedWith = e;
          rethrow;
        }
      },
    });
    await until(() => c.read(taskQueueProvider).tasks.single.status == TaskQueueStatus.running);

    c.read(extractionProvider.notifier).cancel(game.gameId);
    expect(c.read(taskQueueProvider).tasks, isEmpty);

    gate.complete();
    await until(() => stoppedWith != null);
    await pumpEventQueue();
    expect(stoppedWith, isA<TaskCancelledException>());
    expect(c.read(taskQueueProvider).tasks, isEmpty); // no failed row
    expect(c.read(extractionProvider).tasks, isEmpty);
  });

  test('cancelling an extraction stops it and removes its output folder', () async {
    random('src/big.bin', 24 << 20);
    await FileOps.zip([at('src/big.bin')], at('big.zip'));
    final c = container();
    final notifier = c.read(extractionProvider.notifier);
    final out = Directory(at('big'));
    unawaited(notifier.archiveExtract(taskId: 't', archivePath: at('big.zip'), outputDir: out.path));
    await until(out.existsSync); // the extraction started writing

    notifier.cancel('t');
    await until(() => !out.existsSync());
    expect(c.read(extractionProvider).tasks, isEmpty); // neither completed nor failed
  });
}
