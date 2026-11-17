import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/stepper_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeLaunchbox extends StateNotifier<LaunchboxState> implements LaunchboxNotifier {
  _FakeLaunchbox() : super(const LaunchboxState(loading: false));
  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDualScreen extends StateNotifier<DualScreenState> implements DualScreenNotifier {
  _FakeDualScreen() : super(const DualScreenState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _psx = Console(id: 'psx', name: 'PlayStation', urls: [], gameFilesFormat: ['.chd']);
const _snes = Console(id: 'snes', name: 'Super Nintendo', urls: [], gameFilesFormat: ['.sfc']);

void main() {
  final nav = GlobalKey<NavigatorState>();

  void saved({bool library = true, Map<String, dynamic> general = const {}, Map<String, dynamic> consoles = const {}}) =>
      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({'libraryEnabled': library, 'generalSettings': general, 'consoleSettings': consoles}),
      });

  /// Settings over a home page, so leaving Settings has somewhere to go.
  Future<ProviderContainer> pump(WidgetTester t, {Size size = const Size(1280, 900), String? consoleId}) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = ProviderContainer(overrides: [
      appStateProvider.overrideWith((ref) => _FakeApp(const AppState(consoles: {'psx': _psx, 'snes': _snes}))),
      catalogProvider.overrideWith((ref) => _FakeCatalog()),
      launchboxProvider.overrideWith((ref) => _FakeLaunchbox()),
      favoritesProvider.overrideWith((ref) => _FakeFavorites()),
      dualScreenProvider.overrideWith((ref) => _FakeDualScreen()),
    ]);
    addTearDown(c.dispose);
    // Outside the fake-async zone: it reads the (mocked) preferences.
    await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(consoleId: consoleId))),
                child: const Text('open settings'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open settings'));
    await t.pumpAndSettle();
    return c;
  }

  Finder rail(String label) => find.byKey(ValueKey('rail $label'));

  group('model', () {
    test('setting one key for a console leaves the others following the general ones', () {
      final s = const BaseSettings().setSetting(AppSettings.groupDiscs, true);
      expect(s.groupDiscs, isTrue);
      expect(s.autoExtract, isNull);
      expect(s.maxParallelDownloads, isNull);
      expect(s.getSetting<bool>(AppSettings.autoExtract), isNull);
    });

    test('cleared drops only that key', () {
      final s = const BaseSettings(groupDiscs: true, downloadDir: '/x', authToken: 't').cleared(AppSettings.groupDiscs);
      expect(s.groupDiscs, isNull);
      expect(s.downloadDir, '/x');
      expect(s.authToken, 't');
    });

    testWidgets('a saved value equal to the general one is not a change; a different one is', (t) async {
      saved(general: {
        'autoExtract': false
      }, consoles: {
        'psx': {'autoExtract': false, 'groupDiscs': true, 'downloadDir': '/roms/psx'},
        'snes': {'autoExtract': true},
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
      final n = c.read(settingsProvider.notifier);
      expect(n.changedKeys('psx'), [AppSettings.downloadDir, AppSettings.groupDiscs]);
      expect(n.changedKeys('snes'), [AppSettings.autoExtract]);
      await t.runAsync(() => n.resetConsoleSettings('psx', n.changedKeys('psx')));
      expect(n.changedKeys('psx'), isEmpty);
      expect(c.read(settingsProvider).consoleSettings['psx']!.groupDiscs, isNull);
      expect(c.read(settingsProvider).consoleSettings['psx']!.autoExtract, isFalse); // not a change: kept
    });
  });

  group('wide', () {
    testWidgets('the rail lists the sections; picking one shows its rows', (t) async {
      saved();
      await pump(t);
      for (final s in ['library', 'downloads', 'consoles', 'network', 'sports', 'storage']) {
        expect(rail(s), findsOneWidget, reason: s);
      }
      expect(find.text('Games Library & downloads'), findsOneWidget);
      expect(find.text('Parallel downloads'), findsNothing);

      await t.tap(rail('downloads'));
      await t.pumpAndSettle();
      expect(find.text('Parallel downloads'), findsOneWidget);
      expect(find.text('Games Library & downloads'), findsNothing);

      await t.tap(rail('network'));
      await t.pumpAndSettle();
      expect(find.text('Tinfoil (Switch)'), findsOneWidget);
    });

    testWidgets('with the library off, Downloads and Consoles are not offered', (t) async {
      saved(library: false);
      await pump(t);
      expect(rail('library'), findsOneWidget);
      expect(rail('downloads'), findsNothing);
      expect(rail('consoles'), findsNothing);
      expect(rail('accounts'), findsNothing); // nothing in it off Android
      expect(rail('sports'), findsOneWidget);
    });

    testWidgets('R1 and L1 change section, and stop at the ends', (t) async {
      saved();
      await pump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
      await t.pumpAndSettle();
      expect(find.text('Parallel downloads'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
      await t.pumpAndSettle();
      expect(find.text('USING THE DEFAULTS'), findsOneWidget); // Consoles
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
      await t.pumpAndSettle();
      expect(find.text('Games Library & downloads'), findsOneWidget);
    });

    testWidgets('right goes into the rows, B back to the rail, B again leaves', (t) async {
      saved();
      await pump(t);
      await t.tap(rail('downloads'));
      await t.pumpAndSettle();
      // The tap put focus on the first row; walk back to the rail and in again by d-pad.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, Focus.of(t.element(find.descendant(of: rail('downloads'), matching: find.text('Downloads')))));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, Focus.of(t.element(find.text('Download folder'))));

      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, Focus.of(t.element(find.descendant(of: rail('downloads'), matching: find.text('Downloads')))));

      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
    });

    testWidgets('a d-pad walk down the rail shows each section', (t) async {
      saved();
      await pump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(find.text('Parallel downloads'), findsOneWidget);
    });

    testWidgets('steppers move by one with left and right, from 1 to 20', (t) async {
      saved(general: {'maxParallelDownloads': 19, 'maxParallelExtractions': 1});
      final c = await pump(t);
      await t.tap(rail('downloads'));
      await t.pumpAndSettle();

      Focus.of(t.element(find.text('Parallel downloads'))).requestFocus();
      await t.pump();
      for (var i = 0; i < 3; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
      }
      expect(c.read(settingsProvider).generalSettings.maxParallelDownloads, 20);
      expect(find.byType(SettingsScreen), findsOneWidget); // right stayed on the row

      Focus.of(t.element(find.text('Parallel extractions'))).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(c.read(settingsProvider).generalSettings.maxParallelExtractions, 1);
      expect(FocusManager.instance.primaryFocus, Focus.of(t.element(find.text('Parallel extractions'))), reason: 'left at 1 stays on the row');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(c.read(settingsProvider).generalSettings.maxParallelExtractions, 2);

      await t.tap(find.byTooltip('Less').first);
      await t.pump();
      expect(c.read(settingsProvider).generalSettings.maxParallelDownloads, 19);
      expect(t.widget<SettingsStepperRow>(find.byType(SettingsStepperRow).first).value, 19);
    });

    testWidgets('dependent rows show only while what they depend on is on', (t) async {
      saved();
      await pump(t);
      await t.tap(rail('downloads'));
      await t.pumpAndSettle();
      expect(find.text('Extract into a subfolder'), findsOneWidget);
      expect(find.text('Download every disc'), findsNothing);

      await t.tap(find.text('Extract archives'));
      await t.pump();
      expect(find.text('Extract into a subfolder'), findsNothing);

      await t.tap(find.text('Group multi-disc games'));
      await t.pump();
      expect(find.text('Download every disc'), findsOneWidget);
    });

    testWidgets('Consoles lists the changed consoles first, with what they change', (t) async {
      saved(consoles: {
        'psx': {'groupDiscs': true, 'downloadDir': '/roms/psx'},
      });
      await pump(t);
      await t.tap(rail('consoles'));
      await t.pumpAndSettle();
      expect(find.text('2 changes'), findsOneWidget);
      expect(find.text('Folder, grouping'), findsOneWidget);
      expect(find.text('Defaults'), findsOneWidget); // Super Nintendo
      expect(t.getTopLeft(find.text('PlayStation')).dy, lessThan(t.getTopLeft(find.text('Super Nintendo')).dy));
    });

    testWidgets("a console's page marks its changes with the default, and Reset follows Downloads again", (t) async {
      saved(consoles: {
        'psx': {'groupDiscs': true, 'downloadDir': '/roms/psx'},
      });
      final c = await pump(t, consoleId: 'psx');
      expect(find.text('PlayStation'), findsWidgets);
      expect(find.byType(ChangedChip), findsNWidgets(2));
      expect(find.text('Default: off'), findsOneWidget);
      expect(find.text(followingDownloadsText), findsWidgets);

      final groupRow = find.ancestor(of: find.text('Group multi-disc games'), matching: find.byType(SettingsRowFrame));
      await t.tap(find.descendant(of: groupRow, matching: find.text('Reset')));
      await t.pump();
      expect(c.read(settingsProvider).consoleSettings['psx']!.groupDiscs, isNull);
      expect(find.byType(ChangedChip), findsOneWidget);
      expect(c.read(settingsProvider).consoleSettings['psx']!.downloadDir, '/roms/psx');
    });

    testWidgets('Reset all puts every change back', (t) async {
      saved(consoles: {
        'psx': {'groupDiscs': true, 'downloadDir': '/roms/psx'},
      });
      final c = await pump(t, consoleId: 'psx');
      await t.tap(find.text('Reset all 2'));
      await t.pump();
      expect(find.byType(ChangedChip), findsNothing);
      expect(c.read(settingsProvider.notifier).changedKeys('psx'), isEmpty);
    });

    testWidgets('X resets the focused row', (t) async {
      saved(consoles: {
        'psx': {'groupDiscs': true, 'downloadDir': '/roms/psx'},
      });
      final c = await pump(t, consoleId: 'psx');
      Focus.of(t.element(find.text('Group multi-disc games'))).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
      await t.pump();
      expect(c.read(settingsProvider).consoleSettings['psx']!.groupDiscs, isNull);
      expect(c.read(settingsProvider).consoleSettings['psx']!.downloadDir, '/roms/psx');
    });

    testWidgets('B from a console page goes back to Consoles, not out', (t) async {
      saved();
      await pump(t, consoleId: 'snes');
      expect(find.text('Super Nintendo'), findsWidgets);
      expect(find.text('Extract archives'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('USING THE DEFAULTS'), findsOneWidget);
      expect(rail('library'), findsOneWidget);
    });
  });

  group('narrow', () {
    testWidgets('a list of sections, each opening its own page', (t) async {
      saved();
      await pump(t, size: const Size(400, 800));
      expect(rail('library'), findsNothing);
      expect(find.byKey(const ValueKey('section downloads')), findsOneWidget);
      expect(find.text('Folder, extraction, discs'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('section downloads')));
      await t.pumpAndSettle();
      expect(find.text('Parallel downloads'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Downloads'), findsOneWidget);
    });

    testWidgets("a console id opens that console's page", (t) async {
      saved(consoles: {
        'psx': {'groupDiscs': true},
      });
      await pump(t, size: const Size(400, 800), consoleId: 'psx');
      expect(find.widgetWithText(AppBar, 'PlayStation'), findsOneWidget);
      expect(find.byType(ChangedChip), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Consoles'), findsOneWidget);
    });
  });
}

const followingDownloadsText = 'Following Downloads';
