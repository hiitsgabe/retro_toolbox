import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/smb_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/file_explorer_screen.dart';
import 'package:retro_toolbox/screens/ftp_screen.dart';
import 'package:retro_toolbox/screens/smb_screen.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:smb_connect/smb_connect.dart';

import 'support.dart';

/// The browser pattern: File Explorer on a phone-like storage tree (storage
/// list, list, grid, empty, selection, More, a paste waiting, a running and
/// a failed task, an error, the pad hints), and the SMB and FTP browsers.
///
///   SCREENSHOTS=1 flutter test test/screenshots/browser_test.dart --dart-define=DEVICE=odin2 --dart-define=OUT=/tmp/shots
///
/// ONLY: explorer, smb, ftp.

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

class _Smb extends StateNotifier<SmbState> implements SmbNotifier {
  _Smb(super.s);
  @override
  void toggleSelect(SmbFile entry) {
    final next = {...state.selected};
    next.contains(entry.path) ? next.remove(entry.path) : next.add(entry.path);
    state = state.copyWith(selected: next);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Ftp extends StateNotifier<FtpState> implements FtpNotifier {
  _Ftp(super.s);
  @override
  void setMode(FtpMode mode) {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

SmbFile _smb(String path, {bool dir = false, int size = 0}) => SmbFile(path, '', 'Games', 0, 0, 0, dir ? 0x10 : 0x20, size, true);

FTPEntry _ftp(String name, {bool dir = false, int size = 0}) => FTPEntry.parse('type=${dir ? 'dir' : 'file'};size=$size; $name', ListCommand.mlsd);

void main() {
  screenshotSetUp();
  final only = const String.fromEnvironment('ONLY');
  bool want(String name) => only.isEmpty || only.split(',').contains(name);

  late Directory base;
  late String internal, sd, downloads;
  setUpAll(() {
    base = Directory.systemTemp.createTempSync('rt_browser_');
    internal = '${base.path}/storage/emulated/0';
    sd = '${base.path}/storage/1A2B-3C4D';
    downloads = '$internal/Download';
    // Sparse: the listing only reads the length.
    void touch(String rel, [int size = 0]) {
      final f = File('$internal/$rel')..createSync(recursive: true);
      f.openSync(mode: FileMode.write)
        ..truncateSync(size)
        ..closeSync();
    }

    for (final t in [
      'Chrono Trigger (USA).sfc',
      'Donkey Kong Country (USA) (Rev 2).sfc',
      'EarthBound (USA).sfc',
      'F-Zero (USA).sfc',
      'Final Fantasy III (USA) (Rev 1).sfc',
      'Super Mario World (USA).sfc',
      'Super Metroid (Japan, USA) (En,Ja).sfc',
      'The Legend of Zelda - A Link to the Past (USA).sfc',
    ]) {
      touch('ROMs/snes/$t', 3 << 18);
    }
    touch('ROMs/snes/Super Mario World (USA).srm', 2048);
    Directory('$internal/ROMs/snes/Hacks').createSync(recursive: true);
    Directory('$internal/ROMs/snes/Translations').createSync(recursive: true);
    for (final c in ['gba', 'psx', 'n64', 'switch', 'ps2']) {
      Directory('$internal/ROMs/$c').createSync(recursive: true);
    }
    touch('ROMs/psx/Crash Bandicoot (USA).chd', 400 << 20);
    touch('Download/Chrono Trigger (USA).zip', 3 << 20);
    touch('Download/Celeste [0100A410000E0000][v0].nsz', 900 << 20);
    Directory('$sd/ROMs').createSync(recursive: true);
  });
  tearDownAll(() => base.deleteSync(recursive: true));

  Map<String, String> roots() => {internal: 'Internal', sd: 'SD card', downloads: 'Downloads'};
  String snes() => '$internal/ROMs/snes';

  Future<ProviderContainer> explorer(WidgetTester t, {String? at, List<Override> overrides = const [], Map<String, Object> extra = const {}}) async {
    final c = await launch(t, FileExplorerScreen(initialPath: at, roots: roots()), overrides: overrides, prefs: basePrefs(style: shotStyle, extra: extra));
    await realWait(t, 600);
    return c;
  }

  Future<void> tapText(WidgetTester t, String text) async {
    await t.tap(find.text(text).first);
    await realWait(t, 400);
  }

  if (want('explorer')) {
    testWidgets('explorer storage', (t) async {
      await explorer(t);
      await snap(t, 'explorer_storage');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer list', (t) async {
      await explorer(t, at: snes());
      await snap(t, 'explorer_list');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer grid', (t) async {
      await explorer(t, at: snes(), extra: {'file_browser_layout': 'grid'});
      await snap(t, 'explorer_grid');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer empty', (t) async {
      await explorer(t, at: '$internal/ROMs/n64');
      await snap(t, 'explorer_empty');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer selection and More', (t) async {
      await explorer(t, at: snes());
      await tapText(t, 'Chrono Trigger (USA).sfc');
      await tapText(t, 'EarthBound (USA).sfc');
      await snap(t, 'explorer_selection', keep: true);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('browser-selection')), matching: find.text('More')));
      await frames(t);
      await snap(t, 'explorer_more');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer paste waiting', (t) async {
      await explorer(t, at: snes());
      await tapText(t, 'Chrono Trigger (USA).sfc');
      await tapText(t, 'EarthBound (USA).sfc');
      await t.tap(find.descendant(of: find.byKey(const ValueKey('browser-selection')), matching: find.text('Copy')));
      await frames(t);
      await t.tap(find.descendant(of: find.byType(BrowserBar), matching: find.text('ROMs')));
      await realWait(t, 400);
      await snap(t, 'explorer_paste');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer task running and failed', (t) async {
      final later = DateTime.now().add(const Duration(minutes: 1));
      await explorer(t, at: snes(), overrides: [
        taskQueueProvider.overrideWith((ref) => _Queue([
              QueuedTask(id: 'z', type: TaskType.fileZip, status: TaskQueueStatus.running, createdAt: DateTime(2026), params: const {
                'taskId': 'z', 'source': 'explorer', 'verb': 'Zipping', 'label': 'snes.zip',
              }),
              QueuedTask(id: 'c', type: TaskType.fileCopy, status: TaskQueueStatus.failed, createdAt: DateTime(2026), completedAt: later,
                  error: "FileSystemException: Cannot copy file to '$sd/ROMs/EarthBound (USA).sfc' (OS Error: No space left on device, errno = 28)",
                  params: const {'taskId': 'c', 'source': 'explorer', 'verb': 'Copying', 'label': '2 items'}),
            ])),
        extractionProvider.overrideWith((ref) => _Work({'z': 0.42})),
      ]);
      await snap(t, 'explorer_task');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer error', (t) async {
      await explorer(t, at: '$internal/ROMs/missing');
      await snap(t, 'explorer_error');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer pad', (t) async {
      await explorer(t, at: snes(), overrides: [inputModeProvider.overrideWith((ref) => InputMode.gamepad)]);
      await snap(t, 'explorer_pad', keep: true);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await key(t, LogicalKeyboardKey.f2); // X; the Linux key map has no game buttons
      await snap(t, 'explorer_pad_selection');
    }, skip: !screenshotsEnabled);

    testWidgets('explorer folder options', (t) async {
      await explorer(t, at: snes());
      await t.tap(find.byTooltip('Folder options'));
      await frames(t);
      await snap(t, 'explorer_options');
    }, skip: !screenshotsEnabled);
  }

  if (want('smb')) {
    final files = [
      _smb('/Games/psx/Bios', dir: true),
      _smb('/Games/psx/Crash Bandicoot (USA).chd', size: 412 << 20),
      _smb('/Games/psx/Final Fantasy VII (USA) (Disc 1).chd', size: 610 << 20),
      _smb('/Games/psx/Final Fantasy VII (USA) (Disc 2).chd', size: 598 << 20),
      _smb('/Games/psx/Metal Gear Solid (USA) (Disc 1).chd', size: 540 << 20),
      _smb('/Games/psx/Spyro the Dragon (USA).chd', size: 380 << 20),
      _smb('/Games/psx/Tekken 3 (USA).chd', size: 450 << 20),
    ];
    testWidgets('smb browser', (t) async {
      final s = _Smb(SmbState(connected: true, host: '192.168.1.10', path: '/Games/psx', entries: files, selected: {files[1].path, files[2].path}));
      await launch(t, const SmbScreen(), overrides: [
        smbProvider.overrideWith((ref) => s),
        taskQueueProvider.overrideWith((ref) => _Queue([
              QueuedTask(id: 'd', type: TaskType.remoteTransfer, status: TaskQueueStatus.running, createdAt: DateTime(2026), params: const {
                'taskId': 'd', 'source': 'smb', 'verb': 'Downloading', 'label': 'Tekken 3 (USA).chd',
              }),
            ])),
        extractionProvider.overrideWith((ref) => _Work({'d': 0.7})),
      ]);
      await realWait(t, 400);
      await snap(t, 'smb_browser');
    }, skip: !screenshotsEnabled);

    testWidgets('smb shares', (t) async {
      final shares = [_smb('/Games', dir: true), _smb('/Backups', dir: true), _smb('/Public', dir: true)];
      await launch(t, const SmbScreen(), overrides: [
        smbProvider.overrideWith((ref) => _Smb(SmbState(connected: true, host: '192.168.1.10', entries: shares, error: 'SmbException: Access denied to share Backups'))),
      ]);
      await realWait(t, 400);
      await snap(t, 'smb_shares');
    }, skip: !screenshotsEnabled);
  }

  if (want('ftp')) {
    testWidgets('ftp browser', (t) async {
      await launch(t, const FtpScreen(), overrides: [
        ftpProvider.overrideWith((ref) => _Ftp(FtpState(connected: true, host: '192.168.1.50', path: '/data/ROMs/gba', entries: [
              _ftp('Hacks', dir: true),
              _ftp('Golden Sun (USA).gba', size: 8 << 20),
              _ftp('Metroid Fusion (USA).gba', size: 8 << 20),
              _ftp('Pokemon Emerald (USA).gba', size: 16 << 20),
            ]))),
      ]);
      await realWait(t, 400);
      await snap(t, 'ftp_browser');
    }, skip: !screenshotsEnabled);
  }
}
