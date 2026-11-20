import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/chd_convert_screen.dart';
import 'package:retro_toolbox/screens/cia_convert_screen.dart';
import 'package:retro_toolbox/screens/nsz_decompress_screen.dart';
import 'package:retro_toolbox/screens/rar_decompress_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The native picker, answering every file pick with [path].
class _Picker extends FilePicker with MockPlatformInterfaceMixin {
  _Picker(this.path);
  String path;
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

/// A task list that only records: enqueued tasks wait there, as in the app
/// before a slot frees.
class _Queue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _Queue([List<QueuedTask> tasks = const []]) : super(TaskQueueState(tasks: tasks));
  @override
  void enqueue(String taskId, TaskType type, Map<String, dynamic> params) =>
      state = state.copyWith(tasks: [...state.tasks, QueuedTask(id: taskId, type: type, params: params, createdAt: DateTime(2026))]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// One converter: the screen, its task type, the file it takes and the
/// label of its file slot.
typedef _Tool = ({String name, Widget Function() screen, TaskType type, String file, String slot, String primary});

final _tools = <_Tool>[
  (name: 'CHD', screen: () => ChdConvertScreen(chdmanAvailable: (_) async => true), type: TaskType.chdConversion, file: '/roms/psx/Crash.cue', slot: 'Disc image', primary: 'Compress to CHD'),
  (name: '3DS to CIA', screen: () => const CiaConvertScreen(), type: TaskType.cia3dsConversion, file: '/roms/3ds/Pokemon X.3ds', slot: '3DS image', primary: 'Convert to CIA'),
  (name: 'NSZ', screen: () => const NszDecompressScreen(), type: TaskType.nszDecompression, file: '/roms/switch/Celeste.nsz', slot: 'NSZ file', primary: 'Unpack to NSP'),
  (name: 'Rar', screen: () => const RarDecompressScreen(), type: TaskType.archiveExtraction, file: '/roms/snes/pack.zip', slot: 'Archive', primary: 'Extract'),
];

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  void prefs({bool keys = true}) => SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({if (keys) 'nszKeysPath': '/keys/prod.keys', if (keys) 'boot9Path': '/keys/boot9.bin', 'libraryEnabled': false}),
      });
  setUp(() {
    prefs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => '/tmp');
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));

  /// Opens [screen] over a home route, so a pop would show "home".
  Future<_Queue> open(WidgetTester t, Widget screen, {String picked = '/roms/x.cue', List<QueuedTask> tasks = const []}) async {
    FilePicker.platform = _Picker(picked);
    final queue = _Queue(tasks);
    final c = ProviderContainer(overrides: [taskQueueProvider.overrideWith((_) => queue)]);
    addTearDown(c.dispose);
    await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [DpadScope.routeObserver],
        theme: appTheme(CardStyle.switchStyle),
        builder: (context, child) => DpadScope(navigatorKey: nav, child: child!),
        home: const Scaffold(body: Text('home')),
      ),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => screen));
    await t.pumpAndSettle();
    return queue;
  }

  final primary = find.byKey(const ValueKey('kit-primary'));
  String primaryLabel(WidgetTester t) => t.widget<Text>(find.descendant(of: primary, matching: find.byType(Text))).data!;
  bool primaryEnabled(WidgetTester t) => t.widget<FilledButton>(primary).onPressed != null;

  for (final tool in _tools) {
    testWidgets('${tool.name}: the primary names the result, and Start leaves the screen open with the item queued', (t) async {
      final queue = await open(t, tool.screen(), picked: tool.file);
      expect(primaryEnabled(t), isFalse, reason: 'nothing picked yet');

      await t.tap(find.text(tool.slot));
      await t.pumpAndSettle();
      expect(primaryLabel(t), tool.primary);
      expect(primaryEnabled(t), isTrue);

      await t.tap(primary);
      await t.pumpAndSettle();
      expect(queue.state.tasks.single.type, tool.type);
      expect(find.text('home'), findsNothing, reason: 'the tool does not close itself');
      expect(find.byType(SnackBar), findsNothing);
      final status = find.byKey(const ValueKey('kit-status-working'));
      expect(find.descendant(of: status, matching: find.text(tool.file.split('/').last)), findsOneWidget);
      expect(find.descendant(of: status, matching: find.text('queued')), findsOneWidget);
      expect(t.widget<Slot>(find.byType(Slot).first).path, isNull, reason: 'the slot clears for the next file');
      expect(primaryEnabled(t), isFalse);
    });

    testWidgets('${tool.name}: Start runs the primary', (t) async {
      final queue = await open(t, tool.screen(), picked: tool.file);
      await t.tap(find.text(tool.slot));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
      await t.pumpAndSettle();
      expect(queue.state.tasks, hasLength(1));
    });

    testWidgets('${tool.name}: a finished task in the task list shows as done, a failed one as an error', (t) async {
      final params = {'inputPath': tool.file, 'nszFilePath': tool.file, 'archivePath': tool.file, 'outputDir': '/roms/out'};
      await open(t, tool.screen(), tasks: [QueuedTask(id: 'a', type: tool.type, status: TaskQueueStatus.completed, params: params, createdAt: DateTime(2026))]);
      expect(find.descendant(of: find.byKey(const ValueKey('kit-status-done')), matching: find.textContaining('ROMs › out')), findsOneWidget);

      await open(t, tool.screen(), tasks: [QueuedTask(id: 'a', type: tool.type, status: TaskQueueStatus.failed, params: params, createdAt: DateTime(2026), error: 'raw error')]);
      expect(find.byKey(const ValueKey('kit-status-error')), findsOneWidget);
      expect(find.text('raw error'), findsNothing, reason: 'the raw error is behind Details');
    });
  }

  testWidgets('CHD: a .chd extracts, and the button says so', (t) async {
    await open(t, ChdConvertScreen(chdmanAvailable: (_) async => true), picked: '/roms/psx/Crash.chd');
    await t.tap(find.text('Disc image'));
    await t.pumpAndSettle();
    expect(primaryLabel(t), 'Extract to CUE/BIN');
  });

  testWidgets('CHD: no chdman is a missing requirement beside the form, and blocks Start', (t) async {
    await open(t, ChdConvertScreen(chdmanAvailable: (_) async => false), picked: '/roms/psx/Crash.cue');
    final missing = find.byKey(const ValueKey('kit-status-missingRequirement'));
    expect(find.descendant(of: missing, matching: find.text('chdman not found')), findsOneWidget);
    expect(find.descendant(of: missing, matching: find.text('Locate chdman')), findsOneWidget);
    await t.tap(find.text('Disc image'));
    await t.pumpAndSettle();
    expect(t.widget<Slot>(find.byType(Slot).first).path, '/roms/psx/Crash.cue', reason: 'the slot works before the fix');
    expect(primaryEnabled(t), isFalse);
  });

  for (final (name, screen, title) in [
    ('3DS to CIA', const CiaConvertScreen(), '3DS keys needed'),
    ('NSZ', const NszDecompressScreen(), 'prod.keys needed'),
  ]) {
    testWidgets('$name: no keys is a missing requirement beside the form, and blocks Start', (t) async {
      prefs(keys: false);
      await open(t, screen, picked: '/roms/game.file');
      final missing = find.byKey(const ValueKey('kit-status-missingRequirement'));
      expect(find.descendant(of: missing, matching: find.text(title)), findsOneWidget);
      expect(find.descendant(of: missing, matching: find.text('Open Settings > Keys')), findsOneWidget);
      expect(find.byType(Slot), findsNWidgets(2), reason: 'the form stays visible');
      expect(primaryEnabled(t), isFalse);
    });
  }
}
