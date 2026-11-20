import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/chd_convert_screen.dart';
import 'package:retro_toolbox/screens/cia_convert_screen.dart';
import 'package:retro_toolbox/screens/nsz_decompress_screen.dart';
import 'package:retro_toolbox/screens/rar_decompress_screen.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'fake_picker.dart';
import 'support.dart';

/// The four converters in each state their status panel has: requirement
/// missing, a file picked, work in the task list, done (with a failure) and
/// an error. The task list is a fake holding sample tasks.
///
///   SCREENSHOTS=1 flutter test test/screenshots/converters_test.dart --dart-define=DEVICE=odin2 --dart-define=OUT=/tmp/shots
///
/// ONLY: chd, cia, nsz, rar.

class _Queue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _Queue(List<QueuedTask> tasks) : super(TaskQueueState(tasks: tasks));
  @override
  void enqueue(String taskId, TaskType type, Map<String, dynamic> params) =>
      state = state.copyWith(tasks: [...state.tasks, QueuedTask(id: taskId, type: type, params: params, createdAt: DateTime(2026))]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Work extends StateNotifier<ExtractionState> implements ExtractionNotifier {
  _Work(Map<String, double> progress)
      : super(ExtractionState(tasks: {
          for (final e in progress.entries) e.key: ExtractionTaskState(taskId: e.key, status: ExtractionStatus.extracting, progress: e.value),
        }));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _roms = '/storage/emulated/0/ROMs';

typedef _Tool = ({Widget Function(bool ready) screen, TaskType type, String key, String dir, List<String> files, String fixture});

final _tools = <String, _Tool>{
  'chd': (
    screen: (ready) => ChdConvertScreen(chdmanAvailable: (_) async => ready),
    type: TaskType.chdConversion,
    key: 'inputPath',
    dir: '$_roms/psx',
    files: ['Final Fantasy VII (USA) (Disc 1).cue', 'Final Fantasy VII (USA) (Disc 2).cue', 'Metal Gear Solid (USA) (Disc 1).cue'],
    fixture: 'psx/Crash Bandicoot (USA).cue',
  ),
  'cia': (
    screen: (_) => const CiaConvertScreen(),
    type: TaskType.cia3dsConversion,
    key: 'inputPath',
    dir: '$_roms/3ds',
    files: ['Pokemon X (USA).3ds', 'Super Mario 3D Land (USA).3ds', 'Mario Kart 7 (USA).3ds'],
    fixture: '3ds/Pokemon X (USA).3ds',
  ),
  'nsz': (
    screen: (_) => const NszDecompressScreen(),
    type: TaskType.nszDecompression,
    key: 'nszFilePath',
    dir: '$_roms/switch',
    files: ['Celeste [0100A410000E0000][v0].nsz', 'Hollow Knight [0100633007D48000][v0].nsz', 'Hades [0100535012974000][v0].nsz'],
    fixture: 'switch/Celeste [0100A410000E0000][v0].nsz',
  ),
  'rar': (
    screen: (_) => const RarDecompressScreen(),
    type: TaskType.archiveExtraction,
    key: 'archivePath',
    dir: '$_roms/snes',
    files: ['SNES Hacks Pack.zip', 'Chrono Trigger (USA).rar', 'EarthBound (USA).zip'],
    fixture: 'snes/SNES Hacks Pack.zip',
  ),
};

QueuedTask _task(_Tool tool, int i, TaskQueueStatus status, {String? error}) => QueuedTask(
      id: '${tool.type.name}$i',
      type: tool.type,
      status: status,
      params: {tool.key: '${tool.dir}/${tool.files[i]}', 'outputDir': tool.dir},
      createdAt: DateTime(2026),
      error: error,
    );

/// The sample task list for [state].
List<QueuedTask> _tasks(_Tool tool, String state) => switch (state) {
      'working' => [_task(tool, 2, TaskQueueStatus.completed), _task(tool, 0, TaskQueueStatus.running), _task(tool, 1, TaskQueueStatus.waiting)],
      'done' => [_task(tool, 0, TaskQueueStatus.completed), _task(tool, 1, TaskQueueStatus.completed), _task(tool, 2, TaskQueueStatus.failed, error: 'Not enough space on the device')],
      'error' => [_task(tool, 0, TaskQueueStatus.failed, error: 'Error: file not found: ${tool.files[0]} (Track 2).bin\n  at run (worker.dart:88)')],
      _ => const [],
    };

Map<String, Object> _prefs(AppStyle style, {required bool keys}) => {
      ...basePrefs(style: style),
      'app_settings': jsonEncode({
        'generalSettings': {'downloadDir': _roms, 'autoExtract': true},
        'libraryEnabled': true,
        if (keys) 'nszKeysPath': '/data/keys/prod.keys',
        if (keys) 'boot9Path': '/data/keys/boot9.bin',
      }),
    };

void main() {
  screenshotSetUp();
  late FakePicker picker;
  setUp(() => FilePicker.platform = picker = FakePicker());

  const only = String.fromEnvironment('ONLY');
  final states = ['missing', 'filled', 'working', 'done', 'error'];

  for (final cards in [CardStyle.classic, CardStyle.switchStyle]) {
    for (final MapEntry(key: name, value: tool) in _tools.entries) {
      if (only.isNotEmpty && !only.split(',').contains(name)) continue;
      for (final state in states) {
        // Rar has no requirement: its "missing" is the empty form.
        final modes = state == 'filled' ? InputMode.values : [InputMode.touch];
        for (final mode in modes) {
          testWidgets('converter $name $state ${cards.name} ${mode.name}', (t) async {
            final style = AppStyle(cards: cards);
            final missing = state == 'missing';
            final c = await launch(t, const Scaffold(), style: style, prefs: _prefs(style, keys: !missing), overrides: [
              taskQueueProvider.overrideWith((ref) => _Queue(_tasks(tool, state))),
              extractionProvider.overrideWith((ref) => _Work({'${tool.type.name}0': 0.62})),
            ]);
            await push(t, tool.screen(!missing));
            await realWait(t, 300);
            if (state != 'missing') {
              final root = romFixtures();
              picker.file = '$root/${tool.fixture}';
              await withNativePicker(() async {
                await t.tap(find.byType(Slot).first);
                await realWait(t, 400);
              });
            }
            c.read(inputModeProvider.notifier).state = mode;
            if (mode == InputMode.gamepad) await key(t, LogicalKeyboardKey.shiftLeft);
            c.read(inputModeProvider.notifier).state = mode;
            await frames(t, 3);
            await snap(t, 'converter_${name}_${state}_${cards.name}_${mode.name}');
          }, skip: !screenshotsEnabled);
        }
      }
    }
  }
}
