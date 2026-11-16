import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index_builder.dart';

void main() {
  final stardew = File('save_recipes/stardew-valley.json').readAsStringSync();
  String variant(String id) => stardew.replaceFirst('"stardew-valley"', '"$id"');

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('recipe-index-builder'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // The index the app reads must describe the files beside it. CI regenerates
  // it on main; this catches a stale one before that.
  test('the committed index matches the folder', () {
    final built = buildRecipeIndex(Directory('save_recipes'));
    expect(built.problems, isEmpty);
    expect(built.json, File('save_recipes/index.json').readAsStringSync());
  });

  test('entries are sorted by id and carry packages, status and the sha256 of the file bytes', () {
    File('${tmp.path}/zeta.json').writeAsStringSync(variant('zeta'));
    File('${tmp.path}/alpha.json').writeAsStringSync(variant('alpha'));
    File('${tmp.path}/index.json').writeAsStringSync('stale, and never read as a recipe');

    final built = buildRecipeIndex(tmp);

    final recipes = (jsonDecode(built.json!) as Map<String, dynamic>)['recipes'] as List;
    expect([for (final r in recipes) r['id']], ['alpha', 'zeta']);
    expect(recipes.first['packages'], ['com.chucklefish.stardewvalley']);
    expect(recipes.first['status'], 'verified');
    expect(recipes.first['sha256'], sha256.convert(File('${tmp.path}/alpha.json').readAsBytesSync()).toString());
  });

  test('one broken recipe stops the whole index', () {
    File('${tmp.path}/alpha.json').writeAsStringSync(variant('alpha'));
    File('${tmp.path}/broken.json').writeAsStringSync('{');

    final built = buildRecipeIndex(tmp);

    expect(built.json, isNull);
    expect(built.problems.keys, ['broken.json']);
  });
}
