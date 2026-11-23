import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/launcher/android_launch_plan.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/game_launcher.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/launcher/launch_target.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';

const _channel = MethodChannel('retro_toolbox/launcher');

final retroarch = LaunchPreset.fromJson({
  'id': 'retroarch',
  'name': 'RetroArch',
  'systems': {
    'snes': {'cores': ['snes9x', 'bsnes'], 'extensions': ['sfc']},
    'psx': {'cores': ['swanstation'], 'extensions': ['chd', 'cue']},
  },
  'android': {
    'packages': ['com.retroarch.aarch64', 'com.retroarch'],
    'activity': 'com.retroarch.browser.retroactivity.RetroActivityFuture',
    'action': 'android.intent.action.MAIN',
    'rom': {'mode': 'path', 'scopedMode': 'saf', 'extra': 'ROM'},
    'extras': [
      {'key': 'LIBRETRO', 'type': 'string', 'value': '{retroarch.core}'},
      {'key': 'CONFIGFILE', 'type': 'string', 'value': '{retroarch.config}'},
    ],
    'flags': ['clearTask', 'clearTop'],
  },
});

final azahar = LaunchPreset.fromJson({
  'id': 'azahar',
  'name': 'Azahar',
  'systems': {
    'psx': {'extensions': ['chd', 'cue']},
  },
  'android': {
    'packages': ['org.azahar_emu.azahar'],
    'activity': 'org.citra.citra_emu.activities.EmulationActivity',
    'action': 'android.intent.action.VIEW',
    'categories': ['android.intent.category.DEFAULT'],
    'mimeType': 'application/octet-stream',
    'rom': {'mode': 'provider'},
    'extras': [
      {'key': 'title', 'type': 'string', 'value': 'from {rom}'},
      {'key': 'args', 'type': 'stringArray', 'value': ['-r', '{rom.uri}']},
      {'key': 'resumeState', 'type': 'bool', 'value': false},
    ],
  },
});

final flycast = LaunchPreset.fromJson({
  'id': 'flycast',
  'name': 'Flycast',
  'systems': {
    'dreamcast': {'extensions': ['chd', 'gdi']},
  },
  'android': {
    'packages': ['com.flycast.emulator'],
    'activity': 'com.flycast.emulator.MainActivity',
    'action': 'android.intent.action.VIEW',
    'rom': {'mode': 'provider', 'multiFileMode': 'path', 'extra': 'game'},
  },
});

final dolphin = LaunchPreset.fromJson({
  'id': 'dolphin',
  'name': 'Dolphin',
  'systems': {
    'gamecube': {'extensions': ['rvz', 'm3u']},
  },
  'android': {
    'packages': ['org.dolphinemu.dolphinemu'],
    'activity': 'org.dolphinemu.dolphinemu.ui.main.MainActivity',
    'action': 'android.intent.action.MAIN',
    'rom': {'mode': 'provider', 'multiFileMode': 'provider', 'extra': 'AutoStartFile', 'clipDataDiscs': true},
  },
});

DetectedEmulator detected(LaunchPreset preset, {bool pathAccess = true, String? dataDir}) => DetectedEmulator(
      presetId: preset.id,
      variant: preset.android!.packages.first,
      label: preset.name,
      systems: preset.systems.keys.toList(),
      pathAccess: pathAccess,
      dataDir: dataDir,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tmp;
  late String primary;
  late List<Object?> sent;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt-android-launch-');
    // The temp dir stands in for /storage/emulated/0, so real files resolve.
    primary = tmp.path;
    sent = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      sent.add(call.arguments);
      return {'code': 'ok'};
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(_channel, null);
    await tmp.delete(recursive: true);
  });

  String touch(String rel, [String body = '']) => (File(p.join(primary, rel))..createSync(recursive: true)..writeAsStringSync(body)).path;

  OwnedGame owned(String console, List<String> paths) => OwnedGame(
        game: Game(title: 'g', url: 'https://example.com/${p.basename(paths.first)}', size: 1, consoleId: console),
        dir: p.dirname(paths.first),
        paths: paths,
      );

  Future<LaunchResult> launch(LaunchPreset preset, DetectedEmulator d, OwnedGame game, {String? core}) => GameLauncher(
        session: LauncherSession(presets: [preset], detected: [d]),
        systemSlugFor: (id) => id,
        os: 'android',
        primaryRoot: () async => primary,
      ).launch(game, LaunchChoice(presetId: preset.id, variant: d.variant, core: core));

  Map<String, Object?> only() => (sent.single as Map).cast<String, Object?>();

  test('path mode: the path in the ROM extra, the core from dataDir, CONFIGFILE under our primary root', () async {
    final rom = touch('ROMs/snes/Mario World.sfc');
    final r = await launch(retroarch, detected(retroarch, dataDir: '/data/user/0/com.retroarch.aarch64'), owned('snes', [rom]));
    expect(r.code, LaunchCode.ok);
    expect(only(), {
      'package': 'com.retroarch.aarch64',
      'activity': 'com.retroarch.browser.retroactivity.RetroActivityFuture',
      'action': 'android.intent.action.MAIN',
      'categories': <String>[],
      'mimeType': null,
      'flags': ['clearTask', 'clearTop'],
      'rom': {'path': rom, 'mode': 'path', 'uri': null, 'extra': 'ROM', 'clipDataDiscs': false, 'discPaths': <String>[]},
      'extras': [
        {'key': 'LIBRETRO', 'type': 'string', 'value': '/data/user/0/com.retroarch.aarch64/cores/snes9x_libretro_android.so'},
        {'key': 'CONFIGFILE', 'type': 'string', 'value': '$primary/Android/data/com.retroarch.aarch64/files/retroarch.cfg'},
      ],
    });
  });

  test('LaunchChoice.core beats the first cores entry, and no dataDir sends the bare core name', () async {
    final rom = touch('ROMs/snes/Mario World.sfc');
    await launch(retroarch, detected(retroarch), owned('snes', [rom]), core: 'bsnes');
    expect((only()['extras'] as List).first, {'key': 'LIBRETRO', 'type': 'string', 'value': 'bsnes'});
  });

  test('no path access: scopedMode saf, a document URI in the extra, and no CONFIGFILE (Play RetroArch)', () async {
    final rom = touch('ROMs/snes/Mario World.sfc');
    await launch(retroarch, detected(retroarch, pathAccess: false, dataDir: '/data/user/0/com.retroarch'), owned('snes', [rom]));
    final romArgs = only()['rom'] as Map;
    expect(romArgs['mode'], 'saf');
    expect(romArgs['uri'], 'content://com.android.externalstorage.documents/document/primary%3AROMs%2Fsnes%2FMario%20World.sfc');
    expect([for (final e in only()['extras'] as List) (e as Map)['key']], ['LIBRETRO']);
  });

  test('provider mode: Dart leaves {rom} and {rom.uri} for the native side and renders the rest', () async {
    final rom = touch('ROMs/psx/Crash.chd');
    await launch(azahar, detected(azahar), owned('psx', [rom]));
    expect(only()['categories'], ['android.intent.category.DEFAULT']);
    expect(only()['mimeType'], 'application/octet-stream');
    expect(only()['rom'], {'path': rom, 'mode': 'provider', 'uri': null, 'extra': null, 'clipDataDiscs': false, 'discPaths': <String>[]});
    expect(only()['extras'], [
      {'key': 'title', 'type': 'string', 'value': 'from {rom}'},
      {'key': 'args', 'type': 'stringArray', 'value': ['-r', '{rom.uri}']},
      {'key': 'resumeState', 'type': 'bool', 'value': false},
    ]);
  });

  test('a multi-file target turns provider into saf when no multiFileMode is set', () async {
    final bin = touch('ROMs/psx/Spyro.bin');
    final cue = touch('ROMs/psx/Spyro.cue');
    await launch(azahar, detected(azahar), owned('psx', [bin, cue]));
    expect((only()['rom'] as Map)['mode'], 'saf');
    expect((only()['rom'] as Map)['path'], cue);
  });

  test('multiFileMode wins for a multi-file target', () async {
    final gdi = touch('ROMs/dc/Shenmue.gdi');
    await launch(flycast, detected(flycast), owned('dreamcast', [gdi]));
    expect((only()['rom'] as Map)['mode'], 'path');
  });

  test('Dolphin clipDataDiscs: an m3u goes out as its discs', () async {
    final d1 = touch('ROMs/gc/Tales (Disc 1).rvz');
    final d2 = touch('ROMs/gc/Tales (Disc 2).rvz');
    touch('ROMs/gc/Tales.m3u', 'Tales (Disc 1).rvz\nTales (Disc 2).rvz\n');
    await launch(dolphin, detected(dolphin), owned('gamecube', [d2]));
    final rom = only()['rom'] as Map;
    expect((rom['mode'], rom['clipDataDiscs'], p.basename(rom['path'] as String)), ('provider', true, 'Tales.m3u'));
    expect(rom['discPaths'], [d1, d2]);
  });

  test('a path or saf launch from our Android/data folder is romPrivate and sends nothing', () async {
    final rom = touch('Android/data/name.rafaismy.retrotoolbox/files/snes/Mario World.sfc');
    expect((await launch(retroarch, detected(retroarch), owned('snes', [rom]))).code, LaunchCode.romPrivate);
    expect((await launch(retroarch, detected(retroarch, pathAccess: false), owned('snes', [rom]))).code, LaunchCode.romPrivate);
    expect(sent, isEmpty);
  });

  test('a provider launch from Android/data goes ahead: our own process serves the file', () async {
    final rom = touch('Android/data/name.rafaismy.retrotoolbox/files/psx/Crash.chd');
    expect((await launch(azahar, detected(azahar), owned('psx', [rom]))).code, LaunchCode.ok);
    expect(sent, hasLength(1));
  });

  test('a file the preset system does not open is unsupportedFile, a missing one romUnreadable', () async {
    final zip = touch('ROMs/snes/Mario World.zip');
    final r = await launch(retroarch, detected(retroarch), owned('snes', [zip]));
    expect((r.code, r.extension), (LaunchCode.unsupportedFile, 'zip'));
    final gone = await launch(retroarch, detected(retroarch), owned('snes', [p.join(primary, 'ROMs/snes/Gone.sfc')]));
    expect(gone.code, LaunchCode.romUnreadable);
    expect(sent, isEmpty);
  });

  group('the saf document URI', () {
    final rom = PresetSystem(slug: 'psx', extensions: const ['chd']);
    ({Map<String, Object?>? args, LaunchResult? failure}) plan(String path) => planAndroidLaunch(
          preset: azahar,
          system: rom,
          detected: detected(azahar),
          target: LaunchTarget(path),
          choice: const LaunchChoice(presetId: 'azahar', variant: 'org.azahar_emu.azahar'),
          primary: '/storage/emulated/0',
        );
    final scoped = LaunchPreset.fromJson({
      'id': 'scoped',
      'name': 'Scoped',
      'systems': {'psx': {'extensions': ['chd']}},
      'android': {'packages': ['org.example.scoped'], 'activity': 'org.example.Main', 'action': 'android.intent.action.VIEW', 'rom': {'mode': 'saf'}},
    });
    ({Map<String, Object?>? args, LaunchResult? failure}) safPlan(String path) => planAndroidLaunch(
          preset: scoped,
          system: rom,
          detected: detected(scoped),
          target: LaunchTarget(path),
          choice: const LaunchChoice(presetId: 'scoped', variant: 'org.example.scoped'),
          primary: '/storage/emulated/0',
        );

    test('a primary path is primary:<rel>, encoded as Uri.encode does', () {
      expect((safPlan('/storage/emulated/0/ROMs/psx/Final Fantasy (Disc 1).chd').args!['rom'] as Map)['uri'],
          'content://com.android.externalstorage.documents/document/primary%3AROMs%2Fpsx%2FFinal%20Fantasy%20(Disc%201).chd');
    });

    test('an SD card path is <uuid>:<rel>', () {
      expect((safPlan('/storage/1A2B-3C4D/ROMs/psx/Crash.chd').args!['rom'] as Map)['uri'],
          'content://com.android.externalstorage.documents/document/1A2B-3C4D%3AROMs%2Fpsx%2FCrash.chd');
    });

    test('a path on no shared volume is romUnreadable', () {
      expect(safPlan('/data/local/tmp/Crash.chd').failure!.code, LaunchCode.romUnreadable);
    });

    test('provider mode builds no URI in Dart', () {
      expect((plan('/storage/emulated/0/ROMs/psx/Crash.chd').args!['rom'] as Map)['uri'], isNull);
    });
  });
}
