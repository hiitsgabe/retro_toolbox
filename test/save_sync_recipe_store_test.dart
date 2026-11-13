import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';

void main() {
  test('every bundled recipe parses and its id matches the file name', () {
    final files = Directory('save_recipes').listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    final load = parseRecipeFiles({for (final f in files) f.uri.pathSegments.last: f.readAsStringSync()});
    expect(load.rejected, isEmpty);
    expect(load.recipes.map((r) => r.id), containsAll(['stardew-valley', 'sea-of-stars']));
  });

  test('a bad file is reported, the good ones still load', () {
    final load = parseRecipeFiles({
      'good.json': File('save_recipes/stardew-valley.json').readAsStringSync().replaceFirst('"stardew-valley"', '"good"'),
      'broken.json': '{',
      'wrong-id.json': File('save_recipes/stardew-valley.json').readAsStringSync(),
      'future.json': '{"schema": 9}',
    });
    expect(load.recipes.map((r) => r.id), ['good']);
    expect(load.rejected.keys, unorderedEquals(['broken.json', 'wrong-id.json']));
    expect(load.tooNew, ['future.json']);
  });

  test('pubspec bundles the folder', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('    - save_recipes/\n'));
  });

  test('Recipe parse of the bundled Stardew file keeps every field', () {
    final r = parseRecipeFiles({'stardew-valley.json': File('save_recipes/stardew-valley.json').readAsStringSync()}).recipes.single;
    expect(r.unit, UnitKind.folder);
    expect(r.deviceLocal, contains('EMERGENCY_SAVE'));
    expect(r.beforeRestore, hasLength(2));
  });
}
