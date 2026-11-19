import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
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
const _update = GameAddon(label: 'v1', size: 1, url: 'https://api.example.com/update', fileName: 'Base [v1].nsz');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('t2block');
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
        'switch': {'name': 'Switch', 'additional_handler': 'nsz_decompress'},
      }));
    await CatalogService().getConsoles();
  });

  Future<List<String>> download(WidgetTester t, Map<String, dynamic> console, List<Game> games) async {
    final queue = _Queue();
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'libraryEnabled': true,
        'generalSettings': {'downloadDir': roms},
        'consoleSettings': {'switch': console},
      }),
    });
    late WidgetRef ref;
    await t.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        catalogProvider.overrideWith((_) => _FakeCatalog()),
        taskQueueProvider.overrideWith((_) => queue),
      ],
      child: MaterialApp(home: Scaffold(body: Consumer(builder: (_, r, __) {
        ref = r;
        return const SizedBox();
      }))),
    ));
    await t.runAsync(() => ref.read(settingsProvider.notifier).loaded);
    final ctx = t.element(find.byType(SizedBox));
    await t.runAsync(() => TaskQueueService.startDownloads(ref, ctx, games, 'switch'));
    return [for (final e in queue.enqueued) e.$1];
  }

  testWidgets('an update kept as .nsz downloads without NSZ keys', (t) async {
    final u = _update.toGame(_game);
    expect(await download(t, {'updateHandler': 'none'}, [u]), [u.gameId]);
  });

  testWidgets('an update set to decompress NSZ needs the keys even when its game does not', (t) async {
    final u = _update.toGame(_game);
    expect(await download(t, {'additionalHandler': 'none', 'updateHandler': 'nsz_decompress'}, [u]), isEmpty);
  });
}
