import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/launcher/desktop_finder.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/emulator_detector.dart';
import 'package:retro_toolbox/services/launcher/game_launcher.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/launcher_wizard_plan.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';

const _channel = MethodChannel('retro_toolbox/launcher');

final eden = LaunchPreset.fromJson({
  'id': 'eden',
  'name': 'Eden',
  'verified': true,
  'systems': {
    'switch': {'extensions': ['nsp', 'xci']},
  },
  'android': {
    'packages': ['dev.eden.eden_emulator'],
    'activity': 'org.yuzu.yuzu_emu.activities.EmulationActivity',
    'action': 'android.nfc.action.TECH_DISCOVERED',
    'rom': {'mode': 'provider'},
  },
});

final melonds = LaunchPreset.fromJson({
  'id': 'melonds',
  'name': 'melonDS',
  'systems': {
    'nds': {'extensions': ['nds', 'zip']},
  },
  'android': {
    'packages': ['me.magnum.melonds'],
    'activity': 'me.magnum.melonds.ui.emulator.EmulatorActivity',
    'action': 'me.magnum.melonds.LAUNCH_ROM',
    'rom': {'mode': 'provider', 'extra': 'uri'},
  },
  'linux': {
    'find': [
      {'type': 'path', 'names': ['melonDS']},
    ],
    'args': ['{rom}'],
  },
  'windows': {
    'find': [
      {'type': 'path', 'names': ['melonDS.exe']},
    ],
    'args': ['-f', '{rom}'],
  },
});

final gbc = LaunchPreset.fromJson({
  'id': 'gbc-emu',
  'name': 'GBC.emu',
  'systems': {
    'gb': {'extensions': ['gb']},
    'gbc': {'extensions': ['gbc']},
  },
  'android': {
    'packages': ['com.explusalpha.GbcEmu'],
    'activity': 'com.imagine.BaseActivity',
    'action': 'android.intent.action.VIEW',
    'rom': {'mode': 'provider'},
  },
});

/// No process runs: every `which` finds nothing.
class NoProcesses implements ProcessRunner {
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async => ProcessResult(0, 1, '', '');

  @override
  Future<Process> start(String executable, List<String> arguments) => throw ProcessException(executable, arguments);
}

const duo = ManualEmulator(variant: 'dev.igawa6.edenduo', label: 'Eden Duo', recipe: 'eden');
const viewer = ManualEmulator(
  variant: 'org.example.viewer',
  label: 'Viewer',
  recipe: ManualEmulator.generic,
  systems: ['psx', 'saturn'],
  activity: 'org.example.viewer.Open',
);

ManualEmulator? back(ManualEmulator m) => ManualEmulator.fromJson(jsonDecode(jsonEncode(m.toJson())));

void main() {
  group('ManualEmulator', () {
    test('its id is manual- and the variant made safe, so the same app twice is one entry', () {
      expect(duo.id, 'manual-dev.igawa6.edenduo');
      expect(manualId('/home/me/Apps/Eden Duo.AppImage'), 'manual--home-me-apps-eden-duo.appimage');
      expect(manualId(r'C:\Emus\melonDS_x64.exe'), 'manual-c--emus-melonds_x64.exe');
      expect(const ManualEmulator(variant: 'dev.igawa6.edenduo', label: 'Other', recipe: 'generic', systems: ['switch']).id, duo.id);
    });

    test('a recipe one and a generic one round-trip through JSON', () {
      final r = back(duo)!;
      expect((r.variant, r.label, r.recipe, r.activity, r.isGeneric), ('dev.igawa6.edenduo', 'Eden Duo', 'eden', null, false));
      expect(r.systems, isEmpty);
      expect(duo.toJson().containsKey('activity'), isFalse);
      final g = back(viewer)!;
      expect((g.recipe, g.activity, g.isGeneric), ('generic', 'org.example.viewer.Open', true));
      expect(g.systems, ['psx', 'saturn']);
    });

    test('anything that is not a saved manual emulator reads as null', () {
      final good = duo.toJson();
      expect(ManualEmulator.fromJson('junk'), isNull);
      expect(ManualEmulator.fromJson({...good, 'variant': 7}), isNull);
      expect(ManualEmulator.fromJson({...good, 'variant': ''}), isNull);
      expect(ManualEmulator.fromJson({...good, 'label': null}), isNull);
      expect(ManualEmulator.fromJson({...good, 'recipe': ''}), isNull);
      expect(ManualEmulator.fromJson({...good, 'systems': 'psx'}), isNull);
      expect(ManualEmulator.fromJson({...good, 'activity': 7}), isNull);
      expect(ManualEmulator.fromJson({...viewer.toJson(), 'systems': <String>[]}), isNull, reason: 'generic needs a console');
    });

    test("a missing systems field is the recipe's systems, and a slug that is not a string is skipped", () {
      expect(ManualEmulator.fromJson(const {'variant': 'a.b', 'label': 'A', 'recipe': 'eden'})!.systems, isEmpty);
      expect(ManualEmulator.fromJson({...viewer.toJson(), 'systems': ['psx', 7]})!.systems, ['psx']);
    });
  });

  group('presetsWithManual', () {
    test('a recipe is a copy of its preset under the manual id, label and package, after the file presets', () {
      final presets = presetsWithManual([eden, melonds], [duo], os: 'android');
      expect([for (final p in presets) p.id], ['eden', 'melonds', 'manual-dev.igawa6.edenduo']);
      final copy = presets.last;
      expect((copy.name, copy.verified), ('Eden Duo', true));
      expect(copy.systems.keys, ['switch']);
      expect(copy.systems['switch']!.extensions, ['nsp', 'xci']);
      final a = copy.android!;
      expect(a.packages, ['dev.igawa6.edenduo']);
      expect((a.activity, a.action, a.rom.mode, a.rom.extra), ('org.yuzu.yuzu_emu.activities.EmulationActivity', 'android.nfc.action.TECH_DISCOVERED', RomMode.provider, null));
      expect((copy.linux, copy.windows, copy.macos), (null, null, null));
    });

    test('on the desktop the copy finds its executable by path and keeps the recipe args, for this OS only', () {
      const mine = ManualEmulator(variant: r'C:\Emus\melonDS-fork.exe', label: 'melonDS-fork', recipe: 'melonds');
      final copy = presetsWithManual([melonds], [mine], os: 'windows').last;
      expect(copy.id, mine.id);
      expect(copy.windows!.args, ['-f', '{rom}']);
      final rule = copy.windows!.find.single;
      expect(rule.type, FindType.staticPaths);
      expect(rule.paths, [r'C:\Emus\melonDS-fork.exe']);
      expect((copy.android, copy.linux, copy.macos), (null, null, null));
    });

    test('a recipe gone from the file, or with no block for this OS, leaves the entry out', () {
      const gone = ManualEmulator(variant: 'org.example.x', label: 'X', recipe: 'gone');
      const edenOnLinux = ManualEmulator(variant: '/opt/eden', label: 'eden', recipe: 'eden');
      expect([for (final p in presetsWithManual([eden], [gone], os: 'android')) p.id], ['eden']);
      expect([for (final p in presetsWithManual([eden], [edenOnLinux], os: 'linux')) p.id], ['eden']);
    });

    test('systems keeps only the recipe systems it names', () {
      const mine = ManualEmulator(variant: 'org.example.gbc', label: 'GBC fork', recipe: 'gbc-emu', systems: ['gbc']);
      expect(presetsWithManual([gbc], [mine], os: 'android').last.systems.keys, ['gbc']);
    });

    test('generic Android: the stored activity, VIEW, our provider for every file and no extras; each console with the formats given, none where unknown', () {
      final g = presetsWithManual(const [], [viewer], os: 'android', extensions: {'psx': ['chd', 'cue']}).single;
      expect((g.id, g.name, g.verified), (viewer.id, 'Viewer', false));
      expect(g.systems['psx']!.extensions, ['chd', 'cue']);
      expect(g.systems['saturn']!.extensions, isEmpty);
      final a = g.android!;
      expect(a.packages, ['org.example.viewer']);
      expect((a.activity, a.action, a.mimeType), ('org.example.viewer.Open', 'android.intent.action.VIEW', null));
      expect((a.rom.mode, a.rom.extra, a.rom.scopedMode, a.rom.multiFileMode), (RomMode.provider, null, null, RomMode.provider));
      expect(a.extras, isEmpty);
      expect(a.categories, isEmpty);
    });

    test('generic Android never asks for a folder, even for a console whose games come as cue files', () {
      final g = presetsWithManual(const [], [viewer], os: 'android', extensions: {'psx': ['cue', 'chd']}).single;
      const d = DetectedEmulator(presetId: 'manual-org.example.viewer', variant: 'org.example.viewer', label: 'Viewer', systems: ['psx']);
      expect(needsFolderAccess(g, d, g.systems['psx']!), isFalse);
      expect(needsFolderAccess(g, d, const PresetSystem(slug: 'saturn', extensions: ['cue', 'chd'])), isFalse);
    });

    test('generic desktop: the file path as the only argument', () {
      const exe = ManualEmulator(variant: '/opt/viewer', label: 'viewer', recipe: ManualEmulator.generic, systems: ['psx']);
      final g = presetsWithManual(const [], [exe], os: 'linux').single;
      expect(g.linux!.args, ['{rom}']);
      expect(g.linux!.find.single.paths, ['/opt/viewer']);
      expect(g.android, isNull);
    });

    test('generic Android with no activity is left out', () {
      const bare = ManualEmulator(variant: 'org.example.viewer', label: 'Viewer', recipe: ManualEmulator.generic, systems: ['psx']);
      expect(presetsWithManual(const [], [bare], os: 'android'), isEmpty);
    });
  });

  group('through detection and launch', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('rt-manual-'));
    tearDown(() async {
      messenger.setMockMethodCallHandler(_channel, null);
      await tmp.delete(recursive: true);
    });

    test('Android: a manual emulator goes to detect as its one package with the recipe activity', () async {
      Object? sent;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        sent = call.arguments;
        return [
          {'id': duo.id, 'package': 'dev.igawa6.edenduo', 'label': 'Eden Duo', 'versionName': '0.1', 'targetSdk': 35, 'sdkInt': 35},
        ];
      });
      final found = await EmulatorDetector(os: 'android').detect(presetsWithManual([eden], [duo], os: 'android'));
      expect((sent as Map)['presets'], [
        {'id': 'eden', 'packages': ['dev.eden.eden_emulator'], 'activity': 'org.yuzu.yuzu_emu.activities.EmulationActivity'},
        {'id': duo.id, 'packages': ['dev.igawa6.edenduo'], 'activity': 'org.yuzu.yuzu_emu.activities.EmulationActivity'},
      ]);
      expect([for (final d in found) (d.presetId, d.variant, d.version)], [(duo.id, 'dev.igawa6.edenduo', '0.1')]);
      expect(found.single.systems, ['switch']);
    });

    test('desktop: a manual emulator is detected while its executable exists', () async {
      final exe = File(p.join(tmp.path, 'melonDS-fork'))..createSync();
      final mine = ManualEmulator(variant: exe.path, label: 'melonDS-fork', recipe: 'melonds');
      final presets = presetsWithManual([melonds], [mine], os: 'linux');
      final detector = EmulatorDetector(os: 'linux', finder: DesktopFinder(os: 'linux', runner: NoProcesses(), env: const {}));
      final found = await detector.detect(presets);
      expect([for (final d in found) (d.presetId, d.variant, d.exe, d.label)], [(mine.id, exe.path, exe.path, 'melonDS-fork')]);
      exe.deleteSync();
      expect(await detector.detect(presets), isEmpty);
    });

    Future<Map<String, Object?>> launch(List<LaunchPreset> presets, ManualEmulator m, String slug, String file) async {
      final rom = File(p.join(tmp.path, 'ROMs', slug, file))..createSync(recursive: true);
      final sent = <Object?>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        sent.add(call.arguments);
        return {'code': 'ok'};
      });
      final launcher = GameLauncher(
        session: LauncherSession(presets: presets, detected: [DetectedEmulator(presetId: m.id, variant: m.variant, label: m.label, systems: [slug])]),
        systemSlugFor: (_) => slug,
        os: 'android',
        primaryRoot: () async => tmp.path,
      );
      final game = OwnedGame(
        game: Game(title: p.basenameWithoutExtension(file), url: 'https://example.com/$file', size: 1, consoleId: slug),
        dir: rom.parent.path,
        paths: [rom.path],
      );
      final r = await launcher.launch(game, LaunchChoice(presetId: m.id, variant: m.variant));
      expect(r.code, LaunchCode.ok);
      return (sent.single as Map).cast<String, Object?>();
    }

    test("Play on a manual Eden Duo sends Eden's intent to the Eden Duo package", () async {
      final args = await launch(presetsWithManual([eden], [duo], os: 'android'), duo, 'switch', 'Zelda.nsp');
      expect((args['package'], args['activity'], args['action']), ('dev.igawa6.edenduo', 'org.yuzu.yuzu_emu.activities.EmulationActivity', 'android.nfc.action.TECH_DISCOVERED'));
      expect((args['rom'] as Map)['mode'], 'provider');
    });

    test('a generic Android launch is VIEW on the stored activity with the ROM from our provider in the data', () async {
      final args = await launch(presetsWithManual(const [], [viewer], os: 'android', extensions: {'psx': ['chd']}), viewer, 'psx', 'Crash.chd');
      expect((args['package'], args['activity'], args['action'], args['mimeType']), ('org.example.viewer', 'org.example.viewer.Open', 'android.intent.action.VIEW', null));
      final rom = args['rom'] as Map;
      expect((rom['mode'], rom['extra']), ('provider', null));
      expect(args['extras'], isEmpty);
    });

    test('a cue reaches a generic Android app as the cue alone, through our provider, with no folder URI', () async {
      final args = await launch(presetsWithManual(const [], [viewer], os: 'android', extensions: {'psx': ['cue', 'chd']}), viewer, 'psx', 'Spyro.cue');
      final rom = args['rom'] as Map;
      expect((rom['mode'], rom['uri']), ('provider', null));
    });
  });
}
