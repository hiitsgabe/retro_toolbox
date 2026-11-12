import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';

Map<String, dynamic> stardew() => {
      'schema': 1,
      'id': 'stardew-valley',
      'name': 'Stardew Valley',
      'status': 'verified',
      'packages': ['com.chucklefish.stardewvalley'],
      'locations': [
        {'area': 'androidData', 'root': 'files/Saves'},
      ],
      'unit': 'folder',
      'include': ['*/{folder}', '*/SaveGameInfo'],
      'deviceLocal': ['*/*_old', '*/*_SVBAK', '*/*_SVEMERG', '*/BACKUP_SAVE', 'EMERGENCY_SAVE'],
      'inProgress': ['*/*_STARDEWVALLEYSAVETMP', '*/*_tmp'],
      'beforeRestore': [
        {
          'moveAside': ['{folder}/BACKUP_SAVE', '{folder}/{folder}_SVBAK', '{folder}/{folder}_SVEMERG'],
        },
        {'moveAsideIfFirstStringIs': '{folder}', 'file': 'EMERGENCY_SAVE'},
      ],
      'checks': [
        {'file': '*/{folder}', 'xmlEndsWith': '</SaveGame>'},
      ],
      'version': {'file': '*/SaveGameInfo', 'xmlTag': 'gameVersion', 'parts': 3, 'rule': 'receiverAtLeastSave'},
      'nativeCloud': null,
    };

void main() {
  test('parses the Stardew recipe', () {
    final r = Recipe.parse(stardew());
    expect(r.id, 'stardew-valley');
    expect(r.status, RecipeStatus.verified);
    expect(r.unit, UnitKind.folder);
    expect(r.locations.single.area, Area.androidData);
    expect(r.locations.single.root, 'files/Saves');
    expect(r.beforeRestore.first, isA<MoveAside>());
    expect((r.beforeRestore.last as MoveAsideIfFirstStringIs).file, 'EMERGENCY_SAVE');
    expect(r.checks.single.xmlEndsWith, '</SaveGame>');
    expect(r.version!.rule, VersionRule.receiverAtLeastSave);
    expect(r.version!.parts, 3);
    expect(r.nativeCloud, isNull);
    expect(r.raw['id'], 'stardew-valley');
  });

  test('parses package versions and native cloud', () {
    final r = Recipe.parse({
      'schema': 1,
      'id': 'sea-of-stars',
      'name': 'Sea of Stars',
      'status': 'draft',
      'packages': ['com.playdigious.seaofstars'],
      'locations': [
        {'area': 'androidData', 'root': 'files'},
        {'area': 'internal', 'root': 'files'},
      ],
      'unit': 'all',
      'include': ['*.sos', 'Saves/*.sos'],
      'version': {'from': 'package', 'rule': 'sameBuild'},
      'nativeCloud': {'provider': 'googlePlayGames', 'defaultMode': 'backup'},
    });
    expect(r.version!.fromPackage, isTrue);
    expect(r.nativeCloud!.defaultMode, 'backup');
    expect(r.deviceLocal, isEmpty);
  });

  test('a newer schema is RecipeTooNew, not a parse error', () {
    expect(() => Recipe.parse({...stardew(), 'schema': 2}), throwsA(isA<RecipeTooNew>()));
  });

  test('rejects bad recipes with a reason', () {
    final cases = <String, Map<String, dynamic>>{
      'unknown field': {...stardew(), 'extra': 1},
      'checks not a list': {...stardew(), 'checks': <String, dynamic>{}},
      'beforeRestore not a list': {...stardew(), 'beforeRestore': 'x'},
      'bad id': {...stardew(), 'id': 'Stardew Valley'},
      'empty include': {...stardew(), 'include': <String>[]},
      'absolute root': {
        ...stardew(),
        'locations': [
          {'area': 'androidData', 'root': '/files'},
        ],
      },
      'traversal in pattern': {...stardew(), 'include': ['../x']},
      'file placeholder in a folder recipe': {...stardew(), 'include': ['{file}']},
      'unknown placeholder': {...stardew(), 'include': ['{slot}']},
      'bad package': {...stardew(), 'packages': ['stardew']},
      'bad area': {
        ...stardew(),
        'locations': [
          {'area': 'sdcard', 'root': 'files'},
        ],
      },
      'bad rule': {
        ...stardew(),
        'version': {'from': 'package', 'rule': 'newest'},
      },
      'missing schema': Map.of(stardew())..remove('schema'),
      'file unit with a pattern below the root': {
        ...stardew(),
        'unit': 'file',
        'include': ['Saves/*.sos'],
        'deviceLocal': <String>[],
        'inProgress': <String>[],
        'beforeRestore': <Object>[],
        'checks': <Object>[],
        'version': null,
      },
    };
    cases.forEach((why, json) {
      expect(() => Recipe.parse(json), throwsA(isA<RecipeError>()), reason: why);
    });
  });

  test('DevicePaths builds the area folders', () {
    const paths = DevicePaths();
    expect(paths.area(Area.androidData, 'a.b'), '/storage/emulated/0/Android/data/a.b');
    expect(paths.area(Area.internal, 'a.b'), '/data/data/a.b');
    expect(paths.saveSync, '/storage/emulated/0/RetroToolbox/SaveSync');
  });
}
