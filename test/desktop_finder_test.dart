import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/desktop_finder.dart';
import 'package:retro_toolbox/services/launcher/emulator_detector.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';

/// Answers `run` from [answers] (argv joined by spaces to exit code and
/// stdout) and records every argv; `start` is never expected here.
class FakeRunner implements ProcessRunner {
  FakeRunner([this.answers = const {}]);

  final Map<String, (int, String)> answers;
  final ran = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final argv = [executable, ...arguments];
    ran.add(argv);
    final a = answers[argv.join(' ')];
    if (a == null) throw ProcessException(executable, arguments, 'not found', 2);
    return ProcessResult(1, a.$1, a.$2, '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) => throw UnimplementedError();
}

List<FindRule> rules(List<Map<String, Object?>> find) =>
    LaunchPreset.fromJson({'id': 'x', 'name': 'X', 'systems': const {}, 'linux': {'find': find, 'args': const []}}).linux!.find;

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('rt-finder-'));
  tearDown(() => tmp.delete(recursive: true));

  File touch(String rel) => File(p.join(tmp.path, rel))..createSync(recursive: true);

  test('a static glob matches in the file name, with %VAR% and ~ expanded', () async {
    touch('apps/RetroArch-Linux-x86_64.AppImage');
    touch('home/Applications/DuckStation-x64.AppImage');
    final finder = DesktopFinder(os: 'linux', runner: FakeRunner(), env: {'ROOT': tmp.path, 'HOME': p.join(tmp.path, 'home')});
    expect((await finder.find(rules([{'type': 'static', 'paths': ['%ROOT%/apps/RetroArch-Linux*.AppImage']}])))!.exe, p.join(tmp.path, 'apps', 'RetroArch-Linux-x86_64.AppImage'));
    expect((await finder.find(rules([{'type': 'static', 'paths': ['~/Applications/DuckStation*.AppImage']}])))!.exe, p.join(tmp.path, 'home', 'Applications', 'DuckStation-x64.AppImage'));
  });

  test('a path rule asks which, and the first rule that hits wins', () async {
    final runner = FakeRunner({'which retroarch': (0, '/usr/bin/retroarch\n')});
    final finder = DesktopFinder(os: 'linux', runner: runner, env: const {});
    final hit = await finder.find(rules([
      {'type': 'path', 'names': ['retroarch']},
      {'type': 'flatpak', 'id': 'org.libretro.RetroArch'},
    ]));
    expect(hit!.exe, '/usr/bin/retroarch');
    expect(runner.ran, [['which', 'retroarch']]);
  });

  test('a flatpak hit runs as flatpak run <id>', () async {
    final runner = FakeRunner({'flatpak info org.libretro.RetroArch': (0, 'ID: org.libretro.RetroArch')});
    final hit = await DesktopFinder(os: 'linux', runner: runner, env: const {}).find(rules([{'type': 'flatpak', 'id': 'org.libretro.RetroArch'}]));
    expect((hit!.exe, hit.variant), ('flatpak', 'org.libretro.RetroArch'));
    expect(hit.prefixArgs, ['run', 'org.libretro.RetroArch']);
  });

  test('an .app bundle runs its CFBundleExecutable', () async {
    touch('Applications/RetroArch.app/Contents/MacOS/RetroArch');
    File(p.join(tmp.path, 'Applications/RetroArch.app/Contents/Info.plist'))
        .writeAsStringSync('<plist><dict><key>CFBundleExecutable</key>\n\t<string>RetroArch</string></dict></plist>');
    final finder = DesktopFinder(os: 'macos', runner: FakeRunner(), env: {'ROOT': tmp.path});
    final hit = await finder.find(rules([{'type': 'app', 'paths': ['%ROOT%/Applications/RetroArch.app']}]));
    expect(hit!.exe, p.join(tmp.path, 'Applications/RetroArch.app/Contents/MacOS/RetroArch'));
  });

  test('a miss everywhere finds nothing, and a missing tool is a miss', () async {
    final finder = DesktopFinder(os: 'linux', runner: FakeRunner(), env: {'ROOT': tmp.path});
    expect(
        await finder.find(rules([
          {'type': 'path', 'names': ['retroarch']},
          {'type': 'flatpak', 'id': 'org.libretro.RetroArch'},
          {'type': 'static', 'paths': ['%ROOT%/nothing*.AppImage', '%ROOT%/none/retroarch']},
        ])),
        isNull);
  });

  test('the detector turns hits into detected emulators for this OS only', () async {
    final presets = [
      LaunchPreset.fromJson({
        'id': 'ra',
        'name': 'RetroArch',
        'systems': {'snes': {'extensions': ['sfc'], 'cores': ['snes9x']}},
        'linux': {'find': [{'type': 'path', 'names': ['retroarch']}], 'args': ['-L', '{retroarch.core}', '{rom}']},
      }),
      LaunchPreset.fromJson({
        'id': 'win',
        'name': 'Windows only',
        'systems': {'psx': {'extensions': ['chd']}},
        'windows': {'find': [{'type': 'path', 'names': ['x.exe']}], 'args': ['{rom}']},
      }),
    ];
    final finder = DesktopFinder(os: 'linux', runner: FakeRunner({'which retroarch': (0, '/usr/bin/retroarch\n')}), env: const {});
    final found = await EmulatorDetector(os: 'linux', finder: finder).detect(presets);
    expect([for (final d in found) (d.presetId, d.variant, d.exe, d.label)], [('ra', '/usr/bin/retroarch', '/usr/bin/retroarch', 'RetroArch')]);
    expect(found.single.systems, ['snes']);
  });
}
