import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';

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
}
