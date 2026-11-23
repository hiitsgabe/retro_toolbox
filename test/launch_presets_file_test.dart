import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_check.dart';

const _path = 'launch_presets/launch_presets.json';

void main() {
  test('the committed preset file passes the strict check', () {
    final body = File(_path).readAsStringSync();
    final check = checkPresetFile(body);
    expect(check.problems, isEmpty);
    final raw = (jsonDecode(body) as Map)['presets'] as List;
    expect(check.file!.presets, hasLength(raw.length));
  });

  test('every seed preset ships unverified until the device checklist passes', () {
    final check = checkPresetFile(File(_path).readAsStringSync());
    expect(check.file!.presets.where((p) => p.verified), isEmpty);
  });

  test('the seed covers the v1 Android systems and desktop emulators', () {
    final presets = checkPresetFile(File(_path).readAsStringSync()).file!.presets;
    final androidSystems = {for (final p in presets) if (p.android != null) ...p.systems.keys};
    expect(androidSystems, {
      'nes', 'snes', 'gb', 'gbc', 'gba', 'nds', '3ds', 'n64', 'gamecube', 'wii', 'switch',
      'psx', 'ps2', 'psp', 'genesis', 'saturn', 'dreamcast', 'arcade',
    });
    for (final os in ['linux', 'windows', 'macos']) {
      expect({for (final p in presets) if (p.desktopFor(os) != null) p.id},
          containsAll(['retroarch', 'duckstation', 'pcsx2', 'ppsspp', 'dolphin', 'melonds', 'azahar', 'flycast', 'cemu']),
          reason: os);
    }
  });

  test('pubspec bundles the preset file as the seed', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('    - $_path\n'));
  });
}
