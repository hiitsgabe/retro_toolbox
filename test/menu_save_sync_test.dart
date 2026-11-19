import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;
  late bool handheld;
  setUp(() {
    handheld = Handheld.current;
    Handheld.current = false;
    support = Directory.systemTemp.createTempSync('menu_save_sync');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => support.path);
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({'generalSettings': {}, 'libraryEnabled': true}),
    });
  });
  tearDown(() {
    MenuScreen.saveSyncShownForTest = null;
    Handheld.current = handheld;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null);
    support.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Load outside the fake-async zone: it touches the real file system.
    await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(home: const MenuScreen())));
    await t.pump(const Duration(milliseconds: 300));
  }

  List<String> topLabels(WidgetTester t) => t.widget<MenuGrid>(find.byType(MenuGrid)).tiles.map((e) => e.label).toList();

  testWidgets('Save Sync sits right after Games Library with the ALPHA badge', (t) async {
    MenuScreen.saveSyncShownForTest = true;
    await pump(t);
    final labels = topLabels(t);
    expect(labels.indexOf('Save Sync'), labels.indexOf('Games Library') + 1);
    expect(t.widget<MenuGrid>(find.byType(MenuGrid)).tiles.firstWhere((e) => e.label == 'Save Sync').badge, 'ALPHA');
  });

  testWidgets('Tools no longer holds Save Sync', (t) async {
    MenuScreen.saveSyncShownForTest = true;
    await pump(t);
    // Cover flow: first tap centres the card, second opens it.
    await t.tap(find.text('Tools'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tools'));
    await t.pumpAndSettle();
    expect(find.text('M3U Playlists'), findsOneWidget);
    expect(find.text('Save Sync'), findsNothing);
  });

  testWidgets('hidden where it was hidden before', (t) async {
    MenuScreen.saveSyncShownForTest = false;
    await pump(t);
    expect(topLabels(t), isNot(contains('Save Sync')));
  });
}
