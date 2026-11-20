import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_add_app_screen.dart';
import 'package:retro_toolbox/screens/save_sync_recipe_wizard_screen.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';

class FakeNotifier extends SaveSyncNotifier {
  FakeNotifier() {
    state = const SaveSyncState();
  }

  @override
  Future<void> refresh() async {}

  String? addError;

  @override
  Future<String?> addApps(Map<String, String?> packageToRecipe) async => addError;

  @override
  Future<({String root, List<({String name, bool isDir})> entries})?> probeSaveFolder(String package) async => null;

  @override
  Future<List<({String package, AppInfo info})>> launchableApps() async => const [
        (package: 'com.example.known', info: AppInfo('Known App', null)),
        (package: 'com.example.catalog', info: AppInfo('Catalog App', null)),
        (package: 'com.example.nothing', info: AppInfo('Unknown App', null)),
      ];
}

Future<void> pump(WidgetTester t, {RecipeCatalog? catalog, Map<String, String> known = const {}}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [saveSyncProvider.overrideWith((ref) => FakeNotifier())],
    child: MaterialApp(home: SaveSyncAddAppScreen(already: const {}, catalog: catalog, known: known)),
  ));
  await t.pumpAndSettle();
}

void main() {
  // The bug this pins: a build that ships a recipe for an app still told the
  // owner there was none, because only the catalog was consulted.
  testWidgets('a recipe already in hand reads as ready, not as missing', (t) async {
    await pump(t, known: {'com.example.known': 'known'});
    expect(find.text('Recipe ready'), findsOneWidget);
    expect(find.textContaining('No recipe yet'), findsNWidgets(2));
  });

  testWidgets('a recipe only the catalog knows still reads as available', (t) async {
    await pump(
      t,
      catalog: RecipeCatalog([
        const IndexEntry(id: 'catalog', packages: ['com.example.catalog'], status: 'verified'),
      ]),
    );
    expect(find.textContaining('Recipe available'), findsOneWidget);
    expect(find.textContaining('verified'), findsOneWidget);
  });

  testWidgets('with nothing anywhere, every app still offers to be described', (t) async {
    await pump(t);
    expect(find.textContaining('No recipe yet'), findsNWidgets(3));
  });

  testWidgets('an add whose recipe cannot be fetched says why and stays open', (t) async {
    final fake = FakeNotifier()..addError = 'Could not download the recipe for com.example.catalog';
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => SaveSyncAddAppScreen(
                already: const {},
                catalog: RecipeCatalog([const IndexEntry(id: 'catalog', packages: ['com.example.catalog'], status: 'draft')]),
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Catalog App'));
    await t.pump();
    await t.tap(find.text('ADD 1'));
    await t.pumpAndSettle();

    expect(find.text('Could not download the recipe for com.example.catalog'), findsOneWidget);
    expect(find.byType(SaveSyncAddAppScreen), findsOneWidget, reason: 'the screen must not close on a failed add');
  });

  // The website says to hold an app to describe it; a pad gets Y on the row.
  testWidgets('holding an app with no recipe opens Describe', (t) async {
    await pump(t);
    await t.longPress(find.text('Unknown App'));
    await t.pumpAndSettle();
    expect(find.byType(SaveSyncRecipeWizardScreen), findsOneWidget);
  });

  testWidgets('an app already added is marked, cannot be unmarked, and has nothing to describe', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => FakeNotifier())],
      child: const MaterialApp(home: SaveSyncAddAppScreen(already: {'com.example.known'})),
    ));
    await t.pumpAndSettle();
    expect(find.text('Already added'), findsOneWidget);
    await t.tap(find.text('Known App'));
    await t.longPress(find.text('Known App'));
    await t.pumpAndSettle();
    expect(find.byType(SaveSyncRecipeWizardScreen), findsNothing);
    expect(find.text('ADD'), findsOneWidget, reason: 'nothing new is marked');
  });
}
