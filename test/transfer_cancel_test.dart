import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/ftp_service.dart';
import 'package:retro_toolbox/services/smb_service.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/utils/remote_tree.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings(this.dir) : super(const AppSettings());
  final String dir;
  @override
  String getDownloadDir(String? consoleId) => dir;
  @override
  int getMaxParallelDownloads() => 5;
  @override
  int getMaxParallelExtractions() => 2;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDownloads extends StateNotifier<DownloadState> implements DownloadNotifier {
  _FakeDownloads() : super(const DownloadState());
  final cancelled = <String>[];
  @override
  Future<void> cancelTask(String taskId) async => cancelled.add(taskId);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _transfer = Game(title: 'net', url: 'https://manual/net-1.task', size: 0, consoleId: 'manual');
const _zip = Game(title: 'x', url: 'https://x/x.zip', size: 0, consoleId: 'manual');

void main() {
  late Directory dir;
  late _FakeDownloads downloads;
  late ProviderContainer c;
  late WidgetRef ref;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('cancel_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    downloads = _FakeDownloads();
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        catalogProvider.overrideWith((_) => _FakeCatalog()),
        settingsProvider.overrideWith((_) => _FakeSettings(dir.path)),
        downloadProvider.overrideWith((_) => downloads),
      ],
      child: Consumer(builder: (ctx, r, _) {
        ref = r;
        return const SizedBox();
      }),
    ));
    c = ProviderScope.containerOf(t.element(find.byType(SizedBox)));
  }

  // Lets the queue's own scheduling and the job's async failure run.
  Future<void> settle(WidgetTester t) => t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  Future<void> teardown(WidgetTester t) async {
    await t.pumpWidget(const SizedBox()); // disposes the queue's polling timer
  }

  List<QueuedTask> tasksOf(String id) => c.read(taskQueueProvider).tasks.where((x) => x.id == id).toList();
  GameState? stateOf(String id) => c.read(gameStateManagerProvider)[id];

  /// Enqueues a transfer whose job fails the way a closed SMB connection does.
  void enqueueDisconnected(String id) {
    final smb = SmbService(); // never connected
    c.read(gameStateManagerProvider.notifier).registerTransientGame(_transfer, isTransfer: true);
    c.read(taskQueueProvider.notifier).enqueue(id, TaskType.remoteTransfer, {
      'taskId': id,
      'source': 'smb',
      'verb': 'Downloading',
      'label': 'x',
      'run': (void Function(int, int) _) => smb.downloadParallel(const [], (_, __) {}),
    });
  }

  test('SMB and FTP services say so when not connected, with a plain message', () async {
    final smbErr = await SmbService().list('a').then<Object?>((_) => null, onError: (e) => e);
    expect(smbErr, isA<StateError>().having((e) => e.message, 'message', notConnectedMessage));
    expect(
      () => SmbService().downloadParallel(const [], (_, __) {}),
      throwsA(isA<StateError>().having((e) => e.message, 'message', notConnectedMessage)),
    );
    expect(
      () => FtpClientService().openAt('/'),
      throwsA(isA<StateError>().having((e) => e.message, 'message', notConnectedMessage)),
    );
    expect(() => FtpClientService().list(), throwsA(isA<StateError>()));
  });

  testWidgets('a transfer retried after Disconnect fails with the friendly text, not a null check', (t) async {
    await pump(t);
    final id = _transfer.gameId;
    enqueueDisconnected(id);
    await settle(t);
    expect(stateOf(id)!.status, GameStatus.downloadFailed);
    expect(stateOf(id)!.errorMessage, notConnectedMessage);
    expect(tasksOf(id).single.error, notConnectedMessage);

    TaskQueueService.retryTransfer(ref, id);
    await settle(t);
    // The stale failed attempt was replaced, not left beside the new one.
    expect(tasksOf(id).single.status, TaskQueueStatus.failed);
    expect(stateOf(id)!.errorMessage, notConnectedMessage);
    await teardown(t);
  });

  testWidgets('cancel on a failed transfer removes the task, its progress and its row', (t) async {
    await pump(t);
    final id = _transfer.gameId;
    enqueueDisconnected(id);
    await settle(t);
    expect(c.read(extractionProvider).tasks, contains(id));

    TaskQueueService.cancelTask(ref, _transfer, stateOf(id)!);
    expect(tasksOf(id), isEmpty);
    expect(c.read(extractionProvider).tasks, isNot(contains(id)));
    expect(stateOf(id), isNull);
    await teardown(t);
  });

  /// Parks the queue's single transfer slot so later transfers just wait.
  void occupySlot() {
    final blocker = Completer<void>();
    addTearDown(() => blocker.complete());
    c.read(taskQueueProvider.notifier).enqueue('blocker', TaskType.remoteTransfer, {
      'taskId': 'blocker',
      'source': 'smb',
      'verb': 'Downloading',
      'label': 'x',
      'run': (void Function(int, int) _) => blocker.future,
    });
  }

  /// Queues [_zip] behind the blocker (the type is incidental to cancelling).
  void queueZip() {
    c.read(gameStateManagerProvider.notifier).registerTransientGame(_zip);
    c.read(taskQueueProvider.notifier).enqueue(_zip.gameId, TaskType.remoteTransfer, {'taskId': _zip.gameId});
  }

  Future<void> settled(WidgetTester t) async {
    for (var i = 0; i < 40 && stateOf(_zip.gameId)!.status == GameStatus.loading; i++) {
      await settle(t);
    }
  }

  testWidgets('cancel on a failed extraction puts the game back to downloaded and keeps the file', (t) async {
    await pump(t);
    File('${dir.path}/${_zip.filename}').writeAsStringSync('zip');
    occupySlot();
    queueZip();
    c.read(taskQueueProvider.notifier).updateTaskStatus(_zip.gameId, TaskQueueStatus.failed, error: 'boom');
    c.read(gameStateManagerProvider.notifier).updateExtractionState(_zip.gameId, ExtractionStatus.failed, 0, error: 'boom');
    expect(stateOf(_zip.gameId)!.status, GameStatus.extractionFailed);
    expect(stateOf(_zip.gameId)!.errorMessage, 'boom');

    TaskQueueService.cancelTask(ref, _zip, stateOf(_zip.gameId)!);
    await settled(t);
    expect(tasksOf(_zip.gameId), isEmpty);
    expect(stateOf(_zip.gameId)!.status, GameStatus.downloaded);
    expect(stateOf(_zip.gameId)!.errorMessage, isNull);
    expect(File('${dir.path}/${_zip.filename}').existsSync(), isTrue);
    await teardown(t);
  });

  testWidgets('cancelling a waiting task and a normal game download still work as before', (t) async {
    await pump(t);
    c.read(gameStateManagerProvider.notifier).registerTransientGame(_zip);
    // A normal download goes through the download provider, not the queue.
    TaskQueueService.cancelTask(ref, _zip, GameState(game: _zip, status: GameStatus.downloading));
    expect(downloads.cancelled, [_zip.gameId]);

    // A waiting queued task is dropped and the game resolves from disk.
    occupySlot();
    queueZip();
    expect(tasksOf(_zip.gameId).single.status, TaskQueueStatus.waiting);
    TaskQueueService.cancelTask(ref, _zip, stateOf(_zip.gameId)!);
    await settled(t);
    expect(tasksOf(_zip.gameId), isEmpty);
    expect(stateOf(_zip.gameId)!.status, GameStatus.ready);
    await teardown(t);
  });
}
