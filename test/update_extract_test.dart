import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
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
  void updateTaskStatus(String taskId, TaskQueueStatus status, {String? error}) {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _game = Game(title: 'Base.zip', url: 'https://api.example.com/base', size: 1, consoleId: 'switch');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('t2extract');
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

  test('an update zip unpacks inside the updates folder and the zip goes', () async {
    final updates = p.join(roms, 'updates');
    final zip = File(p.join(updates, 'Base [v1].zip'))..createSync(recursive: true);
    final a = Archive()..add(ArchiveFile.bytes('Base [v1].nsp', [1, 2, 3]));
    zip.writeAsBytesSync(ZipEncoder().encode(a));
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'libraryEnabled': true,
        'generalSettings': {'downloadDir': roms},
        'consoleSettings': {},
      }),
    });
    final c = ProviderContainer(overrides: [
      catalogProvider.overrideWith((_) => _FakeCatalog()),
      taskQueueProvider.overrideWith((_) => _Queue()),
    ]);
    addTearDown(c.dispose);
    await c.read(settingsProvider.notifier).loaded;
    final u = const GameAddon(label: 'v1', size: 3, url: 'https://api.example.com/u', fileName: 'Base [v1].zip').toGame(_game);
    c.read(gameStateManagerProvider.notifier).registerTransientGame(u);
    final snap = c.read(librarySnapshotProvider(updates).notifier);
    await snap.getStatus('Base [v1].zip'); // the library has seen the download
    await c.read(extractionProvider.notifier).extractFile(u.gameId);
    ExtractionStatus? st() => c.read(extractionProvider).tasks[u.gameId]?.status;
    for (var i = 0; i < 300 && st() == ExtractionStatus.extracting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(st(), ExtractionStatus.completed);
    expect(File(p.join(updates, 'Base [v1].nsp')).existsSync(), isTrue);
    expect(zip.existsSync(), isFalse);
    expect(c.read(librarySnapshotProvider(updates))[updates]!.exactFiles, {'Base [v1].nsp'});
  });

  test('a failed update extraction leaves the updates folder alone', () async {
    final updates = p.join(roms, 'updates');
    final other = File(p.join(updates, 'Other [v2].nsz'))..createSync(recursive: true);
    File(p.join(updates, 'Bad [v1].zip')).writeAsBytesSync(ZipEncoder().encode(Archive()..add(ArchiveFile.bytes('Bad [v1].nsp', [1]))));
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'libraryEnabled': true,
        'generalSettings': {'downloadDir': roms},
        'consoleSettings': {},
      }),
    });
    final c = ProviderContainer(overrides: [
      catalogProvider.overrideWith((_) => _FakeCatalog()),
      taskQueueProvider.overrideWith((_) => _Queue()),
    ]);
    addTearDown(c.dispose);
    await c.read(settingsProvider.notifier).loaded;
    final u = const GameAddon(label: 'v1', size: 1 << 62, url: 'https://api.example.com/b', fileName: 'Bad [v1].zip').toGame(_game);
    c.read(gameStateManagerProvider.notifier).registerTransientGame(u);
    await c.read(extractionProvider.notifier).extractFile(u.gameId);
    ExtractionStatus? st() => c.read(extractionProvider).tasks[u.gameId]?.status;
    for (var i = 0; i < 300 && st() == ExtractionStatus.extracting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(st(), ExtractionStatus.failed);
    expect(other.existsSync(), isTrue);
  });
}
