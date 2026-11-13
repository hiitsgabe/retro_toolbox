import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

/// The shape the wizard writes, checked the way the wizard checks it: parsed
/// by the real parser, then grouped against a real listing.
Map<String, dynamic> authored({
  required String id,
  required UnitKind unit,
  required List<String> travels,
  List<String> local = const [],
}) =>
    {
      'schema': 1,
      'id': id,
      'name': 'Alpha Title',
      'status': 'draft',
      'packages': ['com.example.alpha'],
      'locations': [
        {'area': 'androidData', 'root': 'files/Saves'},
      ],
      'unit': unit.name,
      'include': [for (final t in travels) unit == UnitKind.folder ? '*/$t' : t],
      if (local.isNotEmpty) 'deviceLocal': [for (final t in local) unit == UnitKind.folder ? '*/$t' : t],
      'version': {'from': 'package', 'rule': 'sameBuild'},
    };

void main() {
  test('what the wizard writes parses, and never claims to be verified', () {
    final r = Recipe.parse(authored(id: 'alpha', unit: UnitKind.all, travels: ['save.dat'], local: ['save.bak']));
    expect(r.status, RecipeStatus.draft);
    expect(r.unit, UnitKind.all);
  });

  test('the files ticked travel and the rest stay', () {
    final r = Recipe.parse(authored(id: 'alpha', unit: UnitKind.all, travels: ['save.dat'], local: ['save.bak', 'settings.ini']));
    expect(groupUnits(r, ['save.dat', 'save.bak', 'settings.ini']), {
      'all': ['save.dat'],
    });
  });

  // The wart the wizard has to guard: a folder unit whose patterns carry no
  // slash parses cleanly and then matches nothing at all.
  test('a shape that would sync nothing is caught before it is saved', () {
    final bad = Recipe.parse({
      ...authored(id: 'alpha', unit: UnitKind.folder, travels: ['save.dat']),
      // A folder unit whose pattern names no folder: legal to the parser,
      // and it can never match anything.
      'include': ['save.dat'],
    });
    expect(groupUnits(bad, ['Slot_1/save.dat']), isEmpty, reason: 'this is what the wizard refuses to save');

    final good = Recipe.parse(authored(id: 'alpha', unit: UnitKind.folder, travels: ['save.dat']));
    expect(groupUnits(good, ['Slot_1/save.dat']), {
      'Slot_1': ['Slot_1/save.dat'],
    });
  });

  test('a recipe written here is read back as the owner\'s own', () async {
    final tmp = Directory.systemTemp.createTempSync('userrecipe');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final dir = Directory(p.join(tmp.path, 'recipes'))..createSync(recursive: true);
    File(p.join(dir.path, 'alpha.json'))
        .writeAsStringSync(jsonEncode(authored(id: 'alpha', unit: UnitKind.all, travels: ['save.dat'])));

    final load = await RecipeStore().loadUser(dir);
    expect(load.rejected, isEmpty);
    expect(load.recipes.single.id, 'alpha');
  });

  test('a file named differently from its id is refused, so ids cannot collide', () async {
    final tmp = Directory.systemTemp.createTempSync('userrecipe');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final dir = Directory(p.join(tmp.path, 'recipes'))..createSync(recursive: true);
    File(p.join(dir.path, 'beta.json'))
        .writeAsStringSync(jsonEncode(authored(id: 'alpha', unit: UnitKind.all, travels: ['save.dat'])));

    final load = await RecipeStore().loadUser(dir);
    expect(load.recipes, isEmpty);
    expect(load.rejected.values.single, contains('does not match the file name'));
  });
}
