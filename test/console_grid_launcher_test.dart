import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/screens/app_drawer_screen.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/services/installed_apps.dart';
import 'package:retro_toolbox/widgets/header/header.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kit/kit_support.dart';
import 'screenshots/fakes.dart';

/// The drawer's apps: none, so it opens on its empty line.
class NoApps implements InstalledApps {
  const NoApps();

  @override
  Future<List<({String package, AppInfo info})>> launchable() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The console list under launcher mode [on]; the consoles in [withGames]
  /// have games on disk, and [checking] are still being checked. With
  /// [noCatalog] there is no console at all.
  Future<void> pump(WidgetTester t,
      {required bool on, Set<String> withGames = const {'snes', 'psx'}, Set<String> checking = const {}, bool home = false, bool noCatalog = false}) async {
    await pumpKit(t, const ConsoleGridScreen(), overrides: [
      if (noCatalog) appStateProvider.overrideWith((ref) => FakeApp(const AppState())) else ...consolesOverrides(),
      launcherModeProvider.overrideWithValue(on),
      homeModeProvider.overrideWithValue(home),
      installedAppsProvider.overrideWithValue(const NoApps()),
      gamesOnDiskProvider.overrideWith((ref, id) => checking.contains(id) ? Completer<bool>().future : Future.value(withGames.contains(id))),
    ]);
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('in launcher mode the list shows the consoles with games on disk', (t) async {
    await pump(t, on: true);
    expect(find.text('2 consoles'), findsOneWidget);
  });

  testWidgets('a console still being checked shows until it is known', (t) async {
    await pump(t, on: true, checking: {'n64'});
    expect(find.text('3 consoles'), findsOneWidget);
  });

  testWidgets('the Owned toggle shows them all again, and back', (t) async {
    await pump(t, on: true);
    await t.tap(find.byTooltip(ownedViewLabel));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('${consoles.length} consoles'), findsOneWidget);
    await t.tap(find.byTooltip(ownedViewLabel));
    // The checks dropped while every console showed run again first.
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('2 consoles'), findsOneWidget);
  });

  testWidgets('with no console holding a game: one line, and Show all', (t) async {
    await pump(t, on: true, withGames: const {});
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No console has games on disk yet'), findsOneWidget);
    await t.tap(find.text('Show all'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('${consoles.length} consoles'), findsOneWidget);
  });

  testWidgets('with launcher mode off every console shows, and there is no toggle', (t) async {
    await pump(t, on: false);
    expect(find.text('${consoles.length} consoles'), findsOneWidget);
    expect(find.byTooltip(ownedViewLabel), findsNothing);
  });

  testWidgets('as the home app the list ends with an Apps tile, which opens the app drawer', (t) async {
    await pump(t, on: true, home: true);
    expect(find.text('2 consoles'), findsOneWidget, reason: 'Apps is no console');
    // A cartridge's label is in capitals.
    await t.tap(find.text('APPS'));
    await t.pumpAndSettle();
    expect(find.byType(AppDrawerScreen), findsOneWidget);
  });

  testWidgets('not the home app: no Apps tile', (t) async {
    await pump(t, on: true);
    expect(find.text('APPS'), findsNothing);
  });

  // The empty states take their Apps action from the same gate as the tile.
  testWidgets('not the home app, with no console holding a game: no Apps button', (t) async {
    await pump(t, on: true, withGames: const {});
    expect(find.text('No console has games on disk yet'), findsOneWidget);
    expect(find.text('Apps'), findsNothing);
  });

  testWidgets('not the home app, with no catalog: no Apps button', (t) async {
    await pump(t, on: true, noCatalog: true);
    expect(find.text('No catalog configured. Add one in Settings.'), findsOneWidget);
    expect(find.text('Apps'), findsNothing);
  });

  testWidgets('as the home app with no console holding a game, Apps is still in reach', (t) async {
    await pump(t, on: true, withGames: const {}, home: true);
    expect(find.text('No console has games on disk yet'), findsOneWidget);
    await t.tap(find.text('Apps'));
    await t.pumpAndSettle();
    expect(find.byType(AppDrawerScreen), findsOneWidget);
  });
}
