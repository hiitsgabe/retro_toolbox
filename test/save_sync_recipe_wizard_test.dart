import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_recipe_wizard_screen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

class _Probe extends SaveSyncNotifier {
  _Probe(this.found) {
    state = const SaveSyncState();
  }

  final ({String root, List<({String name, bool isDir})> entries})? found;

  @override
  Future<void> refresh() async {}

  @override
  Future<({String root, List<({String name, bool isDir})> entries})?> probeSaveFolder(String package) async => found;
}

Future<void> _pumpWizard(WidgetTester t, _Probe probe) async {
  final nav = GlobalKey<NavigatorState>();
  await t.pumpWidget(ProviderScope(
    overrides: [saveSyncProvider.overrideWith((ref) => probe)],
    child: MaterialApp(
      navigatorKey: nav,
      builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
      home: const SaveSyncRecipeWizardScreen(package: 'com.example.alpha', label: 'Alpha'),
    ),
  ));
  await t.pumpAndSettle();
}

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

  // The three steps stay; the shell gives them Next on Start and Back on B.
  testWidgets('the wizard walks Folder, Shape and What travels with Start and B', (t) async {
    await _pumpWizard(t, _Probe((root: '/storage/emulated/0/Android/data/com.example.alpha/files/Saves', entries: [(name: 'save.dat', isDir: false), (name: 'save.bak', isDir: false)])));
    expect(find.text('Step 1 of 3 · Folder'), findsOneWidget);
    expect(find.text('save.dat'), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(find.text('Step 2 of 3 · Shape'), findsOneWidget);
    expect(find.text('Each folder here is a separate save'), findsOneWidget);

    // With a pad, the new step's first choice has focus, not the (i).
    expect(Focus.of(t.element(find.text('Each folder here is a separate save'))).hasPrimaryFocus, isTrue);

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(find.text('Step 1 of 3 · Folder'), findsOneWidget, reason: 'B goes back a step, not out of the wizard');

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(find.text('Step 3 of 3 · What travels'), findsOneWidget);
    expect(find.text('SAVE RECIPE'), findsOneWidget);
    expect(Focus.of(t.element(find.text('save.dat'))).hasPrimaryFocus, isTrue, reason: 'the first file, not the Name field above it');
    // The heuristic leaves the app's own backup unticked.
    expect(t.widget<OptionToggle>(find.widgetWithText(OptionToggle, 'save.dat')).value, isTrue);
    expect(t.widget<OptionToggle>(find.widgetWithText(OptionToggle, 'save.bak')).value, isFalse);
  });

  testWidgets('no folder found: the step says so, offers Look again, and Next waits', (t) async {
    await _pumpWizard(t, _Probe(null));
    expect(find.text('No save folder found for this app.'), findsOneWidget);
    expect(find.text('Look again'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNull);
  });
}
