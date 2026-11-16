import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index_builder.dart';

void main() {
  final stardew = File('save_recipes/stardew-valley.json').readAsStringSync();
  String variant(String id, {String? package}) => stardew
      .replaceFirst('"stardew-valley"', '"$id"')
      .replaceFirst('"com.chucklefish.stardewvalley"', '"${package ?? 'com.example.$id'}"');

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
    expect(recipes.first['packages'], ['com.example.alpha']);
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

  // A file saved in another encoding is that file's problem, named, never a
  // crash that hides which file it was.
  test('a file that is not UTF-8 is a problem for that file', () {
    File('${tmp.path}/alpha.json').writeAsStringSync(variant('alpha'));
    File('${tmp.path}/latin.json').writeAsBytesSync([...utf8.encode('{"name": "Pok'), 0xE9, ...utf8.encode('mon"}')]);

    final built = buildRecipeIndex(tmp);

    expect(built.json, isNull);
    expect(built.problems.keys, ['latin.json']);
    expect(built.problems['latin.json'], contains('UTF-8'));
  });

  // Lookup on the device is by package, one entry each: two recipes claiming
  // one app would leave which one wins to the order of a map.
  test('two recipes naming one package stop the index, named on the second', () {
    File('${tmp.path}/alpha.json').writeAsStringSync(variant('alpha', package: 'com.example.shared'));
    File('${tmp.path}/zeta.json').writeAsStringSync(variant('zeta', package: 'com.example.shared'));

    final built = buildRecipeIndex(tmp);

    expect(built.json, isNull);
    expect(built.problems.keys, ['zeta.json']);
    expect(built.problems['zeta.json'], allOf(contains('com.example.shared'), contains('alpha')));
  });
}
