import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = Console(id: 'a', name: 'Alpha', urls: []);
const _b = Console(id: 'b', name: 'Beta', urls: []);

class _FakeService extends CatalogService {
  @override
  Future<Map<String, Console>> getConsoles([String consolesFilePath = 'consoles.json']) async => {'a': _a, 'b': _b};
}

/// Records loads; `failWith` simulates a console whose catalog fails.
class _RecordingCatalog extends CatalogNotifier {
  final loaded = <String>[];
  String? failWith;
  _RecordingCatalog(Ref ref) : super(ref, CatalogService());

  @override
  Future<void> loadCatalog(Console console) async {
    loaded.add(console.id);
    state = state.copyWith(loading: false, errorMessage: failWith ?? '');
  }
}

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  String getDownloadDir(String? consoleId) => '/downloads';
  @override
  Future<void> get loaded async {}
  @override
  int getMaxParallelDownloads() => 1;
  @override
  int getMaxParallelExtractions() => 1;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGames extends StateNotifier<Map<String, GameState>> implements GameStateManager {
  _FakeGames() : super({});
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _RecordingCatalog catalog;

  Future<void> pumpApp(WidgetTester t, {String? failWith, Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      overrides: [
        catalogProvider.overrideWith((ref) => catalog = _RecordingCatalog(ref)..failWith = failWith),
        appStateProvider.overrideWith((ref) => AppStateNotifier(ref, _FakeService(), ref.read(catalogProvider.notifier))),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: const ConsoleGridScreen(),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('console page lists consoles and loads no catalog, even with a saved console', (t) async {
    await pumpApp(t, prefs: {'selected_console': 'b'});
    expect(catalog.loaded, isEmpty);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('console page keeps the list while a catalog is loading or has failed', (t) async {
    await pumpApp(t);
    catalog.state = catalog.state.copyWith(loading: true, errorMessage: 'Failed to load catalog: timeout');
    await t.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Failed to load catalog: timeout'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('picking a console opens its games and loads only that catalog', (t) async {
    await pumpApp(t);
    await t.tap(find.text('Beta'));
    await t.pumpAndSettle();
    expect(catalog.loaded, ['b']);
  });

  testWidgets('a failed console offers Retry and Choose another console (autofocused) that returns to the list', (t) async {
    await pumpApp(t, failWith: 'No games found for Beta.');
    await t.tap(find.text('Beta'));
    await t.pumpAndSettle();

    expect(find.text('No games found for Beta.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Choose another console'), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(find.descendant(of: find.byWidget(focused.widget), matching: find.text('Choose another console')), findsOneWidget);

    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(catalog.loaded, ['b', 'b']);

    await t.tap(find.text('Choose another console'));
    await t.pumpAndSettle();
    expect(find.byType(ConsoleGridScreen), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('No games found for Beta.'), findsNothing);
  });
}
