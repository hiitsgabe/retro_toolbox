import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_add_app_screen.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';

class FakeNotifier extends SaveSyncNotifier {
  FakeNotifier() {
    state = const SaveSyncState();
  }

  @override
  Future<void> refresh() async {}

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
        const IndexEntry(id: 'catalog', packages: ['com.example.catalog'], status: 'verified', updated: null),
      ]),
    );
    expect(find.textContaining('Recipe available'), findsOneWidget);
    expect(find.textContaining('verified'), findsOneWidget);
  });

  testWidgets('with nothing anywhere, every app still offers to be described', (t) async {
    await pump(t);
    expect(find.textContaining('No recipe yet'), findsNWidgets(3));
  });
}
