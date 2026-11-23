import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_check.dart';

Map<String, Object?> good(String id, {String pkg = 'org.example.emu'}) => {
      'id': id,
      'name': 'Example $id',
      'systems': {
        'psx': {
          'extensions': ['chd', 'cue'],
        },
      },
      'android': {
        'packages': [pkg],
        'activity': 'org.example.emu.EmulationActivity',
        'action': 'android.intent.action.VIEW',
        'rom': {'mode': 'saf'},
        'extras': [
          {'key': 'bootPath', 'type': 'string', 'value': '{rom}'},
        ],
      },
    };

String file(List<Object?> presets, {Object? schema = 1, Object? version = 3}) =>
    jsonEncode({if (schema != null) 'schema': schema, if (version != null) 'version': version, 'presets': presets});

/// [bad] next to a good preset: the app keeps the good one, the strict
/// check reports the bad one.
void expectDropped(Map<String, Object?> bad, String problem) {
  final check = checkPresetFile(file([bad, good('other', pkg: 'org.example.other')]));
  expect(check.file!.presets.map((p) => p.id), ['other']);
  expect(check.problems, [contains(problem)]);
}

void main() {
  test('a valid file has no problems and keeps every preset', () {
    final check = checkPresetFile(file([good('a'), good('b', pkg: 'org.example.b')]));
    expect(check.problems, isEmpty);
    expect(check.file!.presets.map((p) => p.id), ['a', 'b']);
    expect(check.file!.version, 3);
    expect(check.usable, isTrue);
  });

  group('each rule has a failing fixture', () {
    test('id is unique', () {
      final check = checkPresetFile(file([good('a'), good('a', pkg: 'org.example.b')]));
      expect(check.file!.presets, hasLength(1));
      expect(check.problems, [contains('id "a" is used by an earlier preset')]);
    });

    test('every systems key is a known slug', () {
      expectDropped(good('vita')..['systems'] = {'psvita': {'extensions': ['vpk']}}, 'system "psvita" is not a known console slug');
    });

    test('extensions are lowercase', () {
      expectDropped(good('upper')..['systems'] = {'psx': {'extensions': ['CHD']}}, 'extension "CHD" must be lowercase');
    });

    test('extensions carry no dot', () {
      expectDropped(good('dot')..['systems'] = {'psx': {'extensions': ['.chd']}}, 'extension ".chd" must be lowercase with no dot');
    });

    test('an Android package is claimed by at most one preset', () {
      final check = checkPresetFile(file([good('a'), good('b')]));
      expect(check.file!.presets.map((p) => p.id), ['a']);
      expect(check.problems, [contains('package org.example.emu is already claimed by a')]);
    });

    test('an Android preset has an action', () {
      final bad = good('noaction');
      (bad['android'] as Map).remove('action');
      expectDropped(bad, 'android.action is required');
    });

    test('an Android preset has an activity', () {
      final bad = good('noactivity');
      (bad['android'] as Map).remove('activity');
      expectDropped(bad, 'android.activity is required');
    });

    test('the activity is fully qualified', () {
      final bad = good('relative');
      (bad['android'] as Map)['activity'] = '.EmulationActivity';
      expectDropped(bad, 'android.activity must be fully qualified');
    });

    for (final field in ['mode', 'scopedMode', 'multiFileMode']) {
      test('rom.$field is a valid mode', () {
        final bad = good('badmode');
        (bad['android'] as Map)['rom'] = {'mode': 'saf', 'extra': 'x', field: 'file'};
        expectDropped(bad, 'android.rom.$field "file" is not one of path, provider, saf');
      });
    }

    test('path mode needs an extra', () {
      final bad = good('pathdata');
      (bad['android'] as Map)['rom'] = {'mode': 'saf', 'scopedMode': 'path'};
      expectDropped(bad, 'path mode, which needs rom.extra');
    });

    test('placeholders are known', () {
      final bad = good('placeholder');
      (bad['android'] as Map)['extras'] = [
        {'key': 'bootPath', 'type': 'string', 'value': '{file.uri}'},
      ];
      expectDropped(bad, 'unknown placeholder {file.uri}');
    });

    test('placeholders in desktop args are checked too', () {
      expectDropped(good('desk')..['linux'] = {'find': [], 'args': ['{tags.id}']}, 'unknown placeholder {tags.id}');
    });

    test('{retroarch.core} needs cores for every system', () {
      final bad = good('ra')
        ..['systems'] = {
          'psx': {'extensions': ['chd'], 'cores': ['swanstation']},
          'snes': {'extensions': ['sfc']},
        };
      (bad['android'] as Map)['extras'] = [
        {'key': 'LIBRETRO', 'type': 'string', 'value': '{retroarch.core}'},
      ];
      expectDropped(bad, 'systems.snes needs cores');
    });
  });

  group('the file as a whole', () {
    test('a newer schema is refused whole', () {
      final check = checkPresetFile(file([good('a')], schema: supportedPresetSchema + 1));
      expect(check.file, isNull);
      expect(check.usable, isFalse);
      expect(check.problems, [contains('schema 2 is newer than 1')]);
    });

    test('no version, no schema or no JSON at all is refused', () {
      expect(checkPresetFile(file([good('a')], version: null)).file, isNull);
      expect(checkPresetFile(file([good('a')], schema: null)).file, isNull);
      expect(checkPresetFile('<html>').file, isNull);
    });

    test('a file with no valid preset is not usable', () {
      final check = checkPresetFile(file([good('a')..['systems'] = {'psvita': {'extensions': ['vpk']}}]));
      expect(check.file!.presets, isEmpty);
      expect(check.usable, isFalse);
    });
  });

  test('the parser and validator import no Flutter, directly or through another file', () {
    final seen = <String>{};
    final flutter = <String>[];
    void walk(String path) {
      if (!seen.add(path)) return;
      for (final m in RegExp(r'''^(?:import|export)\s+'([^']+)'[^;]*;''', multiLine: true).allMatches(File(path).readAsStringSync())) {
        final uri = m[1]!;
        if (uri.startsWith('package:flutter')) flutter.add('$path imports $uri');
        if (uri.startsWith('package:retro_toolbox/')) walk('lib/${uri.substring('package:retro_toolbox/'.length)}');
        if (!uri.contains(':')) walk(File(path).parent.uri.resolve(uri).toFilePath());
      }
    }

    walk('lib/services/launcher/launch_preset_check.dart');
    expect(seen, containsAll(['lib/services/launcher/launch_preset.dart', 'lib/utils/console_slugs.dart']));
    expect(flutter, isEmpty);
  });
}
