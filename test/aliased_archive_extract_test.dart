import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/library_snapshot_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
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
  @override
  void enqueue(String taskId, TaskType type, Map<String, dynamic> params) {}
  @override
  void updateTaskStatus(String taskId, TaskQueueStatus status, {String? error}) {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('aliased_extract');
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
        'psx': {'name': 'PlayStation', 'decompress': 'unzip'},
        'saturn': {'name': 'Saturn', 'decompress': 'unzip', 'extract_contents': false},
      }));
    await CatalogService().getConsoles();
  });

  // The zip came in from a disk that allows ':', so it is not under the
  // catalog game's filename, which sanitizeForFat made from the same name.
  for (final (console, folder) in [('psx', false), ('saturn', true)]) {
    test('a catalog archive on disk under a real name a FAT card could not hold extracts from that file${folder ? ', into the catalog game\'s folder' : ''}',
        () async {
      final dir = p.join(roms, console);
      final real = File(p.join(dir, 'Foo: Bar (USA).zip'))..createSync(recursive: true);
      real.writeAsBytesSync(ZipEncoder().encode(Archive()..add(ArchiveFile.bytes('Foo Bar (USA).bin', [1, 2, 3]))));
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({
          'libraryEnabled': true,
          'generalSettings': {'downloadDir': roms},
          'consoleSettings': {
            console: {'downloadDir': dir},
          },
        }),
      });
      final c = ProviderContainer(overrides: [
        catalogProvider.overrideWith((_) => _FakeCatalog()),
        taskQueueProvider.overrideWith((_) => _Queue()),
      ]);
      addTearDown(c.dispose);
      await c.read(settingsProvider.notifier).loaded;
      final game = Game(title: 'Foo: Bar (USA).zip', url: 'https://api.example.com/foo', size: 3, consoleId: console);
      expect(game.filename, 'Foo Bar (USA).zip');
      c.read(gameStateManagerProvider.notifier).registerTransientGame(game);
      final snap = c.read(librarySnapshotProvider(dir).notifier);
      expect(await snap.getStatus(game.filename), LibraryPresence.file, reason: 'the catalog game is on disk');

      await c.read(extractionProvider.notifier).extractFile(game.gameId);
      ExtractionStatus? st() => c.read(extractionProvider).tasks[game.gameId]?.status;
      for (var i = 0; i < 300 && st() == ExtractionStatus.extracting; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(st(), ExtractionStatus.completed);
      expect(File(p.joinAll([dir, if (folder) 'Foo Bar (USA)', 'Foo Bar (USA).bin'])).existsSync(), isTrue);
      expect(real.existsSync(), isFalse, reason: 'the archive goes once extracted');
      expect(await snap.getStatus(game.filename), LibraryPresence.extracted, reason: 'the archive is gone from the library too');
    });
  }
}
