import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;
  setUp(() {
    support = Directory.systemTemp.createTempSync('library_opt_in');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => support.path);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null);
    support.deleteSync(recursive: true);
  });

  void saved(bool? library) => SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode({'generalSettings': {}, if (library != null) 'libraryEnabled': library}),
      });

  Future<ProviderContainer> pump(WidgetTester t, Widget home) async {
    await t.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Load outside the fake-async zone: it touches the real file system.
    await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(home: home)));
    await t.pump(const Duration(milliseconds: 300));
    return c;
  }

  test('off unless saved on', () {
    expect(const AppSettings().isLibraryEnabled, isFalse);
    expect(AppSettings.fromJson({'libraryEnabled': true}).isLibraryEnabled, isTrue);
    expect(AppSettings.fromJson(const AppSettings(libraryEnabled: false).toJson()).libraryEnabled, isFalse);
  });

  testWidgets('first run without a user catalog: off and saved', (t) async {
    saved(null);
    final c = await pump(t, const MenuScreen());
    expect(c.read(settingsProvider).libraryEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('app_settings')!)['libraryEnabled'], isFalse);
  });

  testWidgets('first run with a user catalog already set up: on', (t) async {
    saved(null);
    File('${support.path}/config/consoles.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('[{"name":"A"}]');
    final c = await pump(t, const MenuScreen());
    expect(c.read(settingsProvider).libraryEnabled, isTrue);
  });

  testWidgets('menu: Games Library only when enabled', (t) async {
    saved(false);
    await pump(t, const MenuScreen());
    expect(find.text('Games Library'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);

    saved(true);
    await pump(t, const MenuScreen());
    expect(find.text('Games Library'), findsOneWidget);
  });

  testWidgets('settings: off hides library settings; enabling asks first', (t) async {
    // The Max Parallel dropdowns overflow with the wide test font (not with the app's).
    final onError = FlutterError.onError;
    FlutterError.onError = (d) => '${d.exception}'.contains('overflowed') ? null : onError?.call(d);
    addTearDown(() => FlutterError.onError = onError);
    saved(false);
    final c = await pump(t, const SettingsScreen(consoleId: null));
    expect(find.text('Games Library & downloads'), findsOneWidget);
    for (final l in ['Catalog Source', 'Download Directory', 'Accounts', 'Favorites', 'Console']) {
      expect(find.text(l), findsNothing, reason: l);
    }

    await t.tap(find.text('Games Library & downloads'));
    await t.pumpAndSettle();
    expect(find.text('Only download games you legally own, from your own sources.'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).isLibraryEnabled, isFalse);

    await t.tap(find.text('Games Library & downloads'));
    await t.pumpAndSettle();
    await t.tap(find.text('I understand, enable'));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).isLibraryEnabled, isTrue);
    expect(find.text('Catalog Source'), findsOneWidget);
  });
}
