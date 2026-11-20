import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/add_catalog_source_screen.dart';
import 'package:retro_toolbox/screens/collection_clean_screen.dart';
import 'package:retro_toolbox/screens/console_info_screen.dart';
import 'package:retro_toolbox/screens/link_download_screen.dart';
import 'package:retro_toolbox/screens/m3u_screen.dart';
import 'package:retro_toolbox/screens/steam_shortcut_screen.dart';
import 'package:retro_toolbox/services/link_inbox_server.dart';
import 'package:retro_toolbox/services/process_list.dart';
import 'package:retro_toolbox/services/steam_service.dart';
import 'package:retro_toolbox/services/system_info.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'fake_picker.dart';
import 'support.dart';

/// The folder and library tools (M3U, Collection Clean, Steam Shortcuts,
/// Download from link, New Catalog Source, Console Info) in the states their
/// status and results have: empty, filled, working, done and error.
///
///   SCREENSHOTS=1 flutter test test/screenshots/library_tools_test.dart --dart-define=DEVICE=odin2 --dart-define=OUT=/tmp/shots
///
/// ONLY: m3u, clean, steam, link, catalog, info.

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

class _Server implements LinkInboxServer {
  _Server({this.busy = false});
  final bool busy;
  final ctrl = StreamController<String>.broadcast();
  int? _port;
  @override
  Stream<String> get links => ctrl.stream;
  @override
  bool get running => _port != null;
  @override
  int? get port => _port;
  @override
  Future<void> start(int port) async {
    if (busy) throw const SocketException('busy');
    _port = port;
  }

  @override
  Future<void> stop() async => _port = null;
}

class _Steam extends SteamService {
  _Steam({this.offline = false});
  final bool offline;
  @override
  Future<SteamSearchPage> search(String query, {int start = 0}) async {
    if (offline) throw const SocketException('Failed host lookup: store.steampowered.com');
    return SteamSearchPage(results: start > 0 ? const [] : _steamGames, hasMore: false);
  }

  @override
  Future<Map<String, String>> createShortcuts(List<SteamGame> games, String folder) async => {
        for (final g in games)
          if (g.name == 'Hades') g.name: 'FileSystemException: Cannot create file, path = $folder/Hades.steam (OS Error: Permission denied, errno = 13)',
      };
}

const _steamGames = [
  SteamGame(appid: 504230, name: 'Celeste'),
  SteamGame(appid: 1145360, name: 'Hades'),
  SteamGame(appid: 367520, name: 'Hollow Knight'),
  SteamGame(appid: 1794680, name: 'Vampire Survivors'),
  SteamGame(appid: 413150, name: 'Stardew Valley'),
  SteamGame(appid: 646570, name: 'Slay the Spire'),
];

class _Reader extends SystemInfoReader {
  _Reader(this.empty);
  final bool empty;
  @override
  Future<SystemSnapshot> read() async => empty
      ? const SystemSnapshot()
      : const SystemSnapshot(
          deviceName: 'Anbernic RG35XX H',
          firmware: 'Knulli',
          osName: 'Knulli',
          osVersion: '2025.02',
          kernel: '4.9.170',
          cpuModel: 'Cortex-A53',
          cores: 4,
          hostname: 'knulli',
          mem: MemInfo(totalBytes: 1 << 30, availableBytes: 600 << 20),
          battery: BatteryInfo(percent: 87, charging: true),
          cpuTempC: 48.5,
        );
}

class _Procs extends ProcessList {
  @override
  Future<List<ProcessEntry>> list() async => const [
        ProcessEntry(pid: 812, ppid: 1, name: 'retroarch', cmdline: '/usr/bin/retroarch -L snes9x_libretro.so', rssBytes: 96 << 20, protected: false),
        ProcessEntry(pid: 640, ppid: 1, name: 'tailscaled', cmdline: '/usr/sbin/tailscaled --state=mem:', rssBytes: 30 << 20, protected: false),
        ProcessEntry(pid: 233, ppid: 1, name: 'gptokeyb', cmdline: '/usr/bin/gptokeyb -1 retro_toolbox', rssBytes: 4 << 20, protected: true),
      ];
}

/// A fresh folder of [files] for one shot, so a shot that writes leaves the
/// next one as it was.
String _folder(String name, List<String> files) {
  final dir = Directory.systemTemp.createTempSync('k3_').path;
  final out = Directory('$dir/ROMs/$name')..createSync(recursive: true);
  for (final f in files) {
    File('${out.path}/$f').writeAsBytesSync(List.filled(2048, 0));
  }
  return out.path;
}

const _psx = [
  'Final Fantasy VII (USA) (Disc 1).cue',
  'Final Fantasy VII (USA) (Disc 2).cue',
  'Final Fantasy VII (USA) (Disc 3).cue',
  'Metal Gear Solid (USA) (Disc 1).cue',
  'Metal Gear Solid (USA) (Disc 2).cue',
  'Parasite Eve II (USA) (Disc 1).chd',
  'Parasite Eve II (USA) (Disc 2).chd',
  'Crash Bandicoot (USA).cue',
];

const _snes = [
  'Super Mario World (USA).sfc',
  'Super Mario World (USA) (Rev 1).sfc',
  'Super Mario World (Europe).sfc',
  'Chrono Trigger (USA) [!].sfc',
  'Chrono Trigger.sfc',
  'EarthBound (USA) (Virtual Console).sfc',
  '.DS_Store',
  'Thumbs.db',
];

void main() {
  screenshotSetUp();
  late FakePicker picker;
  setUp(() {
    FilePicker.platform = picker = FakePicker();
    PackageInfo.setMockInitialValues(appName: 'Retro Toolbox', packageName: 'name.rafaismy.retrotoolbox', version: '0.7.7', buildNumber: '77', buildSignature: '');
  });

  const only = String.fromEnvironment('ONLY');
  bool want(String name) => only.isEmpty || only.split(',').contains(name);

  /// Opens [screen] over a home route in [cards], runs [act], and snaps it in
  /// each of [modes].
  void shot(String name, String state, Widget Function() screen, {Future<void> Function(WidgetTester t, ProviderContainer c)? act, List<Override> overrides = const [], bool pad = false}) {
    if (!want(name)) return;
    for (final cards in [CardStyle.classic, CardStyle.switchStyle]) {
      for (final mode in pad ? InputMode.values : [InputMode.touch]) {
        testWidgets('k3 $name $state ${cards.name} ${mode.name}', (t) async {
          final style = AppStyle(cards: cards);
          final c = await launch(t, const Scaffold(), style: style, prefs: basePrefs(style: style, extra: {'steam_shortcut_last_dir': '/storage/emulated/0/ROMs/steam'}), overrides: overrides);
          c.read(inputModeProvider.notifier).state = mode;
          await push(t, screen());
          await realWait(t, 300);
          await act?.call(t, c);
          if (mode == InputMode.gamepad) await key(t, LogicalKeyboardKey.shiftLeft);
          c.read(inputModeProvider.notifier).state = mode;
          await frames(t, 3);
          await snap(t, 'k3_${name}_${state}_${cards.name}_${mode.name}');
        }, skip: !screenshotsEnabled);
      }
    }
  }

  Future<void> pickFolder(WidgetTester t, String dir, String slotText) async {
    picker.dir = dir;
    await withNativePicker(() async {
      await t.tap(find.text(slotText));
      await realWait(t, 1200);
    });
  }

  // M3U Playlists.
  shot('m3u', 'empty', () => const M3uScreen());
  shot('m3u', 'filled', () => const M3uScreen(), pad: true, act: (t, c) async {
    final dir = _folder('psx', _psx);
    File('$dir/Metal Gear Solid (USA).m3u').writeAsStringSync('Metal Gear Solid (USA) (Disc 1).cue\nMetal Gear Solid (USA) (Disc 2).cue\n');
    await pickFolder(t, dir, 'Choose the folder with the discs');
  });
  shot('m3u', 'done', () => const M3uScreen(), act: (t, c) async {
    await pickFolder(t, _folder('psx', _psx), 'Choose the folder with the discs');
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    await realWait(t, 300);
  });
  shot('m3u', 'none', () => const M3uScreen(), act: (t, c) async => pickFolder(t, _folder('gba', ['Metroid Fusion (USA).gba']), 'Choose the folder with the discs'));

  // Collection Clean.
  shot('clean', 'empty', () => const CollectionCleanScreen());
  shot('clean', 'filled', () => const CollectionCleanScreen(), pad: true, act: (t, c) async => pickFolder(t, _folder('snes', _snes), 'Choose folder'));
  shot('clean', 'done', () => const CollectionCleanScreen(), act: (t, c) async {
    await pickFolder(t, _folder('snes', _snes), 'Choose folder');
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    await frames(t, 4);
    await t.tap(find.widgetWithText(FilledButton, 'Apply'));
    await realWait(t, 1500);
  });

  // Steam Shortcuts.
  Future<void> steamSearch(WidgetTester t) async {
    await t.enterText(find.byType(TextField), 'indie');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await realWait(t, 300);
  }

  Future<void> steamMark(WidgetTester t) async {
    for (final name in ['Celeste', 'Hades']) {
      await t.tap(find.text(name));
      await frames(t, 2);
    }
  }

  shot('steam', 'empty', () => SteamShortcutScreen(service: _Steam()));
  shot('steam', 'filled', () => SteamShortcutScreen(service: _Steam()), pad: true, act: (t, c) async {
    await steamSearch(t);
    await steamMark(t);
  });
  shot('steam', 'done', () => SteamShortcutScreen(service: _Steam()), act: (t, c) async {
    await steamSearch(t);
    await steamMark(t);
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    await realWait(t, 300);
  });
  shot('steam', 'error', () => SteamShortcutScreen(service: _Steam(offline: true)), act: (t, c) async => steamSearch(t));

  // Download from link.
  const archive = '/storage/emulated/0/Download/Chrono Trigger (USA).zip';
  QueuedTask link(String id, String label, TaskQueueStatus status, {String? error}) =>
      QueuedTask(id: id, type: TaskType.remoteTransfer, status: status, params: {'source': 'link', 'label': label}, createdAt: DateTime(2026), error: error);
  shot('link', 'empty', () => LinkDownloadScreen(server: _Server(), addresses: () async => ['192.168.1.42']));
  late _Server server;
  shot('link', 'filled', () => LinkDownloadScreen(server: server = _Server(), addresses: () async => ['192.168.1.42']), pad: true, act: (t, c) async {
    server.ctrl.add('https://example.invalid/files/Chrono%20Trigger%20(USA).zip?token=8f1c2a9e77d04b6f');
    await realWait(t, 800);
  });
  shot('link', 'working', () => LinkDownloadScreen(server: _Server(), addresses: () async => ['192.168.1.42']), overrides: [
    taskQueueProvider.overrideWith((ref) => _Queue([
          link('l0', 'EarthBound (USA).zip', TaskQueueStatus.completed),
          link('l1', 'Chrono Trigger (USA).zip', TaskQueueStatus.running),
          link('l2', 'Secret of Mana (USA).zip', TaskQueueStatus.waiting),
        ])),
    extractionProvider.overrideWith((ref) => _Work({'l1': 0.42})),
  ]);
  shot('link', 'done', () => LinkDownloadScreen(server: _Server(), addresses: () async => ['192.168.1.42']), overrides: [
    taskQueueProvider.overrideWith((ref) => _Queue([])),
  ], act: (t, c) async {
    const game = Game(title: 'Chrono Trigger (USA).zip', url: 'https://manual/net-1.task', size: 0, consoleId: 'manual');
    c.read(gameStateManagerProvider.notifier).registerTransientGame(game, isTransfer: true, outputPath: archive);
    c.read(gameStateManagerProvider.notifier).updateExtractionState(game.gameId, ExtractionStatus.completed, 1);
    c.read(taskQueueProvider.notifier).state = TaskQueueState(tasks: [
      link(game.gameId, 'Chrono Trigger (USA).zip', TaskQueueStatus.completed),
      link('x', 'Big Pack.zip', TaskQueueStatus.failed, error: 'HttpException: 404 Not Found'),
    ]);
    await frames(t, 3);
  });
  shot('link', 'error', () => LinkDownloadScreen(server: _Server(busy: true), addresses: () async => ['192.168.1.42']), act: (t, c) async {
    await t.enterText(find.byType(TextField).first, 'ftp://example.invalid/a.zip');
    await frames(t, 3);
  });

  // New Catalog Source.
  shot('catalog', 'empty', () => const AddCatalogSourceScreen(), pad: true);
  shot('catalog', 'filled', () => const AddCatalogSourceScreen(), act: (t, c) async {
    await t.enterText(find.widgetWithText(FieldSlot, 'Directory listing URL'), 'https://myserver.lan/roms/snes/');
    await t.enterText(find.widgetWithText(FieldSlot, 'Name'), 'Super Nintendo');
    await frames(t, 2);
    await t.tap(find.text('Advanced'));
    await frames(t, 3);
  });
  shot('catalog', 'error', () => const AddCatalogSourceScreen(), act: (t, c) async {
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    await frames(t, 3);
  });

  // Console Info.
  Widget info({bool empty = false}) => ConsoleInfoScreen(
        reader: _Reader(empty),
        processes: _Procs(),
        mounts: () async => empty ? const [] : [(label: 'System', mount: '/', total: 8 << 30, free: 2 << 30), (label: 'ROMs', mount: '/userdata', total: 128 << 30, free: 9 << 30)],
        addresses: () async => empty ? const [] : ['192.168.1.20'],
        ssid: () async => empty ? null : 'HomeWiFi',
      );
  shot('info', 'filled', () => info(), pad: true);
  shot('info', 'unknown', () => info(empty: true));
  shot('info', 'processes', () => info(), act: (t, c) async {
    await t.scrollUntilVisible(find.text('Advanced'), 200);
    await t.tap(find.text('Advanced'));
    await realWait(t, 300);
    await t.scrollUntilVisible(find.text('gptokeyb'), 200);
  });
}
