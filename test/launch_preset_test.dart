import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';

Map<String, Object?> retroarch() => {
      'id': 'retroarch',
      'name': 'RetroArch',
      'verified': false,
      'systems': {
        'psx': {
          'cores': ['swanstation', 'pcsx_rearmed'],
          'extensions': ['chd', 'cue'],
        },
      },
      'android': {
        'packages': ['com.retroarch.aarch64', 'com.retroarch'],
        'activity': 'com.retroarch.browser.retroactivity.RetroActivityFuture',
        'action': 'android.intent.action.MAIN',
        'rom': {'mode': 'path', 'scopedMode': 'saf', 'extra': 'ROM'},
        'extras': [
          {'key': 'LIBRETRO', 'type': 'string', 'value': '{retroarch.core}'},
          {'key': 'resumeState', 'type': 'bool', 'value': false},
          {'key': 'slot', 'type': 'int', 'value': 2},
          {'key': 'AppStartParameters', 'type': 'stringArray', 'value': ['-r', '{rom}']},
        ],
        'flags': ['clearTask', 'clearTop'],
      },
      'linux': {
        'find': [
          {'type': 'path', 'names': ['retroarch']},
          {'type': 'flatpak', 'id': 'org.libretro.RetroArch'},
        ],
        'args': ['-L', '{retroarch.core}', '{rom}'],
      },
    };

void main() {
  test('a full preset parses into its fields', () {
    final p = LaunchPreset.fromJson(retroarch());
    expect(p.id, 'retroarch');
    expect(p.systems['psx']!.cores, ['swanstation', 'pcsx_rearmed']);
    expect(p.systems['psx']!.extensions, ['chd', 'cue']);
    final a = p.android!;
    expect(a.packages, ['com.retroarch.aarch64', 'com.retroarch']);
    expect(a.rom.mode, RomMode.path);
    expect(a.rom.scopedMode, RomMode.saf);
    expect(a.rom.multiFileMode, isNull);
    expect(a.rom.extra, 'ROM');
    expect(a.flags, [LaunchFlag.clearTask, LaunchFlag.clearTop]);
    expect([for (final e in a.extras) e.type], [ExtraType.string, ExtraType.bool, ExtraType.int, ExtraType.stringArray]);
    expect(a.extras[3].value, ['-r', '{rom}']);
    expect(p.desktopFor('linux')!.find.map((r) => r.type), [FindType.path, FindType.flatpak]);
    expect(p.desktopFor('windows'), isNull);
    expect(p.usesRetroarchCore, isTrue);
  });

  test('an unknown field is ignored, not an error', () {
    final j = retroarch()
      ..['addedLater'] = {'any': 1}
      ..['android'] = {...(retroarch()['android'] as Map), 'shortcut': true};
    expect(LaunchPreset.fromJson(j).id, 'retroarch');
  });

  test('a wrong type names the field', () {
    final j = retroarch();
    (j['android'] as Map<String, Object?>)['rom'] = {'mode': 'file'};
    expect(() => LaunchPreset.fromJson(j), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('android.rom.mode'))));
  });

  test('an extra whose value does not match its type is an error', () {
    final j = retroarch();
    (j['android'] as Map<String, Object?>)['extras'] = [
      {'key': 'resumeState', 'type': 'bool', 'value': 'false'},
    ];
    expect(() => LaunchPreset.fromJson(j), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('resumeState'))));
  });

  test('a preset with no RetroArch core placeholder says so', () {
    final j = retroarch()..remove('linux');
    (j['android'] as Map<String, Object?>)['extras'] = const [];
    expect(LaunchPreset.fromJson(j).usesRetroarchCore, isFalse);
  });
}
