import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/launcher_wizard_plan.dart';

LaunchPreset preset(
  String id, {
  List<String> systems = const ['psx'],
  List<String> extensions = const ['chd'],
  Map<String, Object?>? rom,
  bool android = true,
  bool linux = false,
}) =>
    LaunchPreset.fromJson({
      'id': id,
      'name': 'Preset $id',
      'systems': {for (final s in systems) s: {'extensions': extensions}},
      if (android)
        'android': {
          'packages': ['org.example.$id'],
          'activity': 'org.example.$id.Main',
          'action': 'android.intent.action.VIEW',
          'rom': rom ?? {'mode': 'saf'},
        },
      if (linux)
        'linux': {
          'find': [
            {'type': 'path', 'names': [id]},
          ],
          'args': ['{rom}'],
        },
    });

DetectedEmulator emu(String id, {List<String> systems = const ['psx'], bool pathAccess = true}) =>
    DetectedEmulator(presetId: id, variant: 'org.example.$id', label: 'Preset $id', systems: systems, pathAccess: pathAccess);

void main() {
  group('suggestEmulators', () {
    final presets = [
      preset('one', systems: ['psx']),
      preset('many', systems: ['psx', 'snes', 'gba']),
      preset('desktop', systems: ['psx', 'snes', 'gba', 'nds'], android: false, linux: true),
      preset('two', systems: ['snes', 'gba']),
      preset('other', systems: ['wii']),
      preset('also-one', systems: ['gba']),
    ];

    test('the three that open most of the systems, file order breaking ties, none that opens none', () {
      expect([for (final p in suggestEmulators(presets, {'psx', 'snes', 'gba'}, 'android')) p.id], ['many', 'two', 'one']);
      expect([for (final p in suggestEmulators(presets, {'wii'}, 'android')) p.id], ['other']);
      expect(suggestEmulators(presets, const {}, 'android'), isEmpty);
    });

    test('only presets with a block for this platform', () {
      expect([for (final p in suggestEmulators(presets, {'nds', 'psx'}, 'linux')) p.id], ['desktop']);
    });
  });

  group('preselect', () {
    final session = LauncherSession(presets: const [], detected: [emu('ra', systems: ['psx', 'snes']), emu('ds'), emu('melonds', systems: ['nds'])]);

    test('the saved default while its emulator is detected, with the variant detected now and its core', () {
      expect(preselect(session, 'psx', const LaunchChoice(presetId: 'ds', variant: 'old.package', core: 'x')), const LaunchChoice(presetId: 'ds', variant: 'org.example.ds', core: 'x'));
    });

    test('else the first detected emulator that opens the system', () {
      expect(preselect(session, 'psx', null), const LaunchChoice(presetId: 'ra', variant: 'org.example.ra'));
      expect(preselect(session, 'psx', const LaunchChoice(presetId: 'gone', variant: 'org.example.gone')), const LaunchChoice(presetId: 'ra', variant: 'org.example.ra'));
      expect(preselect(session, 'snes', const LaunchChoice(presetId: 'ds', variant: 'org.example.ds')), const LaunchChoice(presetId: 'ra', variant: 'org.example.ra'),
          reason: 'DuckStation does not open the SNES');
    });

    test('nothing for a system no detected emulator opens', () {
      expect(preselect(session, 'gba', null), isNull);
      expect(preselect(session, null, null), isNull);
    });
  });

  group('needsFolderAccess', () {
    PresetSystem system(LaunchPreset p) => p.systems.values.first;

    test('a saf preset does', () {
      final p = preset('ppsspp');
      expect(needsFolderAccess(p, emu('ppsspp'), system(p)), isTrue);
    });

    test('a path preset does only through its scoped mode, when the package has no path access', () {
      final p = preset('ra', rom: {'mode': 'path', 'scopedMode': 'saf', 'extra': 'ROM'});
      expect(needsFolderAccess(p, emu('ra'), system(p)), isFalse);
      expect(needsFolderAccess(p, emu('ra', pathAccess: false), system(p)), isTrue);
    });

    test('a provider preset does only for a system with multi-file games, which go over saf', () {
      final single = preset('melonds', extensions: ['nds'], rom: {'mode': 'provider'});
      final discs = preset('fpse', extensions: ['chd', 'cue'], rom: {'mode': 'provider'});
      expect(needsFolderAccess(single, emu('melonds'), system(single)), isFalse);
      expect(needsFolderAccess(discs, emu('fpse'), system(discs)), isTrue);
    });

    test('a provider preset whose multi-file mode stays provider does not', () {
      final p = preset('dolphin', extensions: ['rvz', 'm3u'], rom: {'mode': 'provider', 'multiFileMode': 'provider'});
      expect(needsFolderAccess(p, emu('dolphin'), system(p)), isFalse);
    });

    test('a desktop preset never does', () {
      final p = preset('pcsx2', android: false, linux: true);
      expect(needsFolderAccess(p, emu('pcsx2'), system(p)), isFalse);
    });
  });

  test('isAppPrivateDir: under our Android/data, and nothing else', () {
    const primary = '/storage/emulated/0';
    expect(isAppPrivateDir('/storage/emulated/0/Android/data/name.rafaismy.retrotoolbox/files/psx', primary), isTrue);
    expect(isAppPrivateDir('/storage/emulated/0/Android/data/../../ROMs/psx', primary), isFalse);
    expect(isAppPrivateDir('/storage/emulated/0/ROMs/psx', primary), isFalse);
    expect(isAppPrivateDir('/storage/emulated/0/Android/media/ROMs', primary), isFalse);
    expect(isAppPrivateDir('/storage/1234-ABCD/Android/data/x', primary), isFalse);
  });

  test('choiceName: the detected label, else the preset name, else the id, with the core', () {
    final session = LauncherSession(presets: [preset('ds')], detected: [emu('ra')]);
    expect(choiceName(session, const LaunchChoice(presetId: 'ra', variant: 'x', core: 'snes9x')), 'Preset ra (snes9x)');
    expect(choiceName(session, const LaunchChoice(presetId: 'ds', variant: 'x')), 'Preset ds');
    expect(choiceName(null, const LaunchChoice(presetId: 'gone', variant: 'x')), 'gone');
  });
}
