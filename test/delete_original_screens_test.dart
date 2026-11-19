import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/cia_convert_screen.dart';
import 'package:retro_toolbox/screens/nsz_decompress_screen.dart';
import 'package:retro_toolbox/screens/rar_decompress_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The native picker, answering every file pick with [path].
class _Picker extends FilePicker with MockPlatformInterfaceMixin {
  _Picker(this.path);
  final String path;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated('') bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([PlatformFile(name: path.split('/').last, size: 0, path: path)]);
}

class _FakeQueue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _FakeQueue() : super(const TaskQueueState());
  final enqueued = <(TaskType, Map<String, dynamic>)>[];
  @override
  void enqueue(String taskId, TaskType type, Map<String, dynamic> params) => enqueued.add((type, params));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({'nszKeysPath': '/keys/prod.keys', 'boot9Path': '/keys/boot9.bin', 'libraryEnabled': false}),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => '/tmp');
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));

  /// Opens [screen] over a home route (the tools pop back to it), with [picked]
  /// as the file every Choose returns.
  Future<_FakeQueue> open(WidgetTester t, Widget screen, String picked) async {
    FilePicker.platform = _Picker(picked);
    final queue = _FakeQueue();
    final c = ProviderContainer(overrides: [taskQueueProvider.overrideWith((_) => queue)]);
    addTearDown(c.dispose);
    await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(navigatorKey: nav, home: const Text('home'))));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => screen));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose').first);
    await t.pumpAndSettle();
    return queue;
  }

  Finder checkbox() => find.widgetWithText(CheckboxListTile, 'Delete original when done');

  Future<Map<String, dynamic>> enqueue(WidgetTester t, _FakeQueue queue, String button, {required bool tick}) async {
    expect(t.widget<CheckboxListTile>(checkbox()).value, isFalse); // off by default
    if (tick) {
      await t.tap(checkbox());
      await t.pump();
      expect(t.widget<CheckboxListTile>(checkbox()).value, isTrue);
    }
    await t.tap(find.text(button));
    await t.pump();
    return queue.enqueued.single.$2;
  }

  for (final tick in [true, false]) {
    testWidgets('NSZ Decompress sends deleteOriginals: $tick', (t) async {
      final queue = await open(t, const NszDecompressScreen(), '/roms/game.nsz');
      final params = await enqueue(t, queue, 'Add to task list', tick: tick);
      expect(queue.enqueued.single.$1, TaskType.nszDecompression);
      expect(params['nszFilePath'], '/roms/game.nsz');
      expect(params['deleteOriginals'], tick);
    });

    testWidgets('Rar Decompress sends deleteOriginals: $tick', (t) async {
      final queue = await open(t, const RarDecompressScreen(), '/roms/game.zip');
      final params = await enqueue(t, queue, 'Extract', tick: tick);
      expect(queue.enqueued.single.$1, TaskType.archiveExtraction);
      expect(params['archivePath'], '/roms/game.zip');
      expect(params['deleteOriginals'], tick);
    });

    testWidgets('3DS to CIA sends deleteOriginals: $tick', (t) async {
      final queue = await open(t, const CiaConvertScreen(), '/roms/game.3ds');
      final params = await enqueue(t, queue, 'Add to task list', tick: tick);
      expect(queue.enqueued.single.$1, TaskType.cia3dsConversion);
      expect(params['inputPath'], '/roms/game.3ds');
      expect(params['deleteOriginals'], tick);
    });
  }
}
