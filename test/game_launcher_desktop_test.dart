import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/launcher/desktop_finder.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/game_launcher.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';

/// A started process that exits when [exit] completes, or never.
class FakeProcess implements Process {
  final exit = Completer<int>();
  final _out = StreamController<List<int>>();
  final _err = StreamController<List<int>>();

  void err(String lines) => _err.add(utf8.encode(lines));

  /// A real pipe fills and blocks the emulator on its next write unless a
  /// listener keeps reading it. isPaused alone is not enough: a controller
  /// whose listener cancelled reports not paused.
  bool get stdoutDrained => _out.hasListener && !_out.isPaused;
  bool get stderrDrained => _err.hasListener && !_err.isPaused;

  /// Closes the pipes without waiting: a pipe nobody listens to never
  /// finishes closing.
  void finish(int code) {
    _err.close();
    _out.close();
    exit.complete(code);
  }

  @override
  Future<int> get exitCode => exit.future;
  @override
  Stream<List<int>> get stdout => _out.stream;
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  int get pid => 4242;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class FakeRunner implements ProcessRunner {
  final started = <List<String>>[];
  FakeProcess process = FakeProcess();
  bool missing = false;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) => throw UnimplementedError();

  @override
  Future<Process> start(String executable, List<String> arguments) async {
    if (missing) throw ProcessException(executable, arguments, 'No such file or directory', 2);
    started.add([executable, ...arguments]);
    return process;
  }
}

final retroarch = LaunchPreset.fromJson({
  'id': 'retroarch',
  'name': 'RetroArch',
  'systems': {
    'snes': {'cores': ['snes9x', 'bsnes'], 'extensions': ['sfc']},
  },
  'linux': {'find': const [], 'args': ['-L', '{retroarch.core}', '{rom}']},
});

final duckstation = LaunchPreset.fromJson({
  'id': 'duckstation',
  'name': 'DuckStation',
  'systems': {
    'psx': {'extensions': ['chd']},
  },
  'linux': {'find': const [], 'args': ['-batch', '{rom}']},
});

void main() {
  late Directory tmp;
  late FakeRunner runner;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt-desktop-launch-');
    runner = FakeRunner();
  });
  tearDown(() => tmp.delete(recursive: true));

  String touch(String rel) => (File(p.join(tmp.path, rel))..createSync(recursive: true)).path;

  OwnedGame owned(String console, String path) =>
      OwnedGame(game: Game(title: 'g', url: 'https://example.com/${p.basename(path)}', size: 1, consoleId: console), dir: p.dirname(path), paths: [path]);

  Future<LaunchResult> launch(LaunchPreset preset, DetectedEmulator d, OwnedGame game, {String? core}) => GameLauncher(
        session: LauncherSession(presets: [preset], detected: [d]),
        systemSlugFor: (id) => id,
        os: 'linux',
        runner: runner,
        env: {'HOME': tmp.path},
        window: const Duration(milliseconds: 50),
      ).launch(game, LaunchChoice(presetId: preset.id, variant: d.variant, core: core));

  DetectedEmulator found(LaunchPreset preset, String exe, {List<String> prefixArgs = const [], String? variant}) =>
      DetectedEmulator(presetId: preset.id, variant: variant ?? exe, label: preset.name, systems: preset.systems.keys.toList(), exe: exe, prefixArgs: prefixArgs);

  test('the argv is the template with the ROM path and the core under ~/.config/retroarch/cores', () async {
    final rom = touch('roms/snes/Mario World.sfc');
    final core = touch('.config/retroarch/cores/snes9x_libretro.so');
    final r = await launch(retroarch, found(retroarch, '/usr/bin/retroarch'), owned('snes', rom));
    expect(r.code, LaunchCode.ok);
    expect(runner.started, [['/usr/bin/retroarch', '-L', core, rom]]);
  });

  test('a flatpak runs as flatpak run <id>, with the core from its own config dir', () async {
    final rom = touch('roms/snes/Mario World.sfc');
    final core = touch('.var/app/org.libretro.RetroArch/config/retroarch/cores/bsnes_libretro.so');
    await launch(retroarch, found(retroarch, 'flatpak', prefixArgs: ['run', 'org.libretro.RetroArch'], variant: 'org.libretro.RetroArch'), owned('snes', rom), core: 'bsnes');
    expect(runner.started, [['flatpak', 'run', 'org.libretro.RetroArch', '-L', core, rom]]);
  });

  test('a missing core is unsupportedFile with the core name, and nothing starts', () async {
    final rom = touch('roms/snes/Mario World.sfc');
    final r = await launch(retroarch, found(retroarch, '/usr/bin/retroarch'), owned('snes', rom));
    expect((r.code, r.core), (LaunchCode.unsupportedFile, 'snes9x'));
    expect(runner.started, isEmpty);
  });

  test('an exit 1 inside the window is crashed, with the last 20 lines of stderr', () async {
    final rom = touch('roms/psx/Crash.chd');
    final pending = launch(duckstation, found(duckstation, '/usr/bin/duckstation-qt'), owned('psx', rom));
    await Future<void>.delayed(Duration.zero);
    runner.process.err([for (var i = 1; i <= 25; i++) 'line $i'].join('\n'));
    runner.process.finish(1);
    final r = await pending;
    expect(r.code, LaunchCode.crashed);
    expect(r.message, [for (var i = 6; i <= 25; i++) 'line $i'].join('\n'));
    expect(runner.started.single, ['/usr/bin/duckstation-qt', '-batch', rom]);
  });

  test('a process still running when the window ends is ok', () async {
    final rom = touch('roms/psx/Crash.chd');
    final r = await launch(duckstation, found(duckstation, '/usr/bin/duckstation-qt'), owned('psx', rom));
    expect(r.code, LaunchCode.ok);
    expect(runner.process.exit.isCompleted, isFalse);
    expect(runner.process.stdoutDrained, isTrue, reason: 'stdout is drained for the whole life, not only the window');
    expect(runner.process.stderrDrained, isTrue, reason: 'stderr is drained for the whole life, not only the window');
  });

  test('exit 0 inside the window is ok', () async {
    final rom = touch('roms/psx/Crash.chd');
    final pending = launch(duckstation, found(duckstation, '/usr/bin/duckstation-qt'), owned('psx', rom));
    await Future<void>.delayed(Duration.zero);
    runner.process.finish(0);
    expect((await pending).code, LaunchCode.ok);
  });

  test('an executable that is gone is notInstalled', () async {
    runner.missing = true;
    final rom = touch('roms/psx/Crash.chd');
    expect((await launch(duckstation, found(duckstation, '/usr/bin/duckstation-qt'), owned('psx', rom))).code, LaunchCode.notInstalled);
  });

  test('a preset that is no longer detected is notInstalled', () async {
    final rom = touch('roms/psx/Crash.chd');
    final r = await GameLauncher(session: LauncherSession(presets: [duckstation], detected: const []), systemSlugFor: (id) => id, os: 'linux', runner: runner)
        .launch(owned('psx', rom), const LaunchChoice(presetId: 'duckstation', variant: '/usr/bin/duckstation-qt'));
    expect(r.code, LaunchCode.notInstalled);
  });
}
