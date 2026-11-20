import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/screens/add_catalog_source_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final key = GlobalKey<NavigatorState>();
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(CardStyle.switchStyle),
            navigatorKey: key,
            builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
            home: const AddCatalogSourceScreen(),
          ),
        ),
      );

  testWidgets('renders and the IA toggle swaps the URL field label', (tester) async {
    await pump(tester);
    expect(find.text('Directory listing URL'), findsOneWidget);

    await tester.tap(find.text('Internet Archive'));
    await tester.pump();
    expect(find.text('archive.org item ID or URL'), findsOneWidget);
  });

  testWidgets('Add with empty fields says what is missing under each field', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester);
    await tester.tap(find.text('Add to catalog'));
    await tester.pump();
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(find.text('Enter a URL or item ID.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // Typing in a field clears its message.
    await tester.enterText(find.widgetWithText(FieldSlot, 'Name'), 'SNES');
    await tester.pump();
    expect(find.text('Enter a name.'), findsNothing);
    expect(find.text('Enter a URL or item ID.'), findsOneWidget);
  });

  testWidgets('Start runs Add on a cold route (the validation message proves it ran)', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: appTheme(CardStyle.switchStyle),
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AddCatalogSourceScreen())),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(find.text('Enter a name.'), findsOneWidget);
  });

  testWidgets('format fields under Advanced: original, game files, platform; Decompress as choices', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester);
    expect(find.text('DECOMPRESS'), findsOneWidget);
    expect(find.text('Keep as downloaded'), findsOneWidget);
    expect(find.text('Unzip'), findsOneWidget);
    expect(find.text('Unrar'), findsOneWidget);
    expect(find.text('Original formats'), findsNothing, reason: 'Advanced starts closed');
    await tester.tap(find.text('Advanced'));
    await tester.pump();
    expect(find.text('Original formats'), findsOneWidget);
    expect(find.text('Game files formats (optional)'), findsOneWidget);
    expect(find.text('Platform (optional)'), findsOneWidget);
    expect(find.text('Extract contents'), findsOneWidget);
  });

  testWidgets('a console that is added: the screen stays, says so, and clears for the next one', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('catalog_add');
    addTearDown(() => dir.deleteSync(recursive: true));
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => dir.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester);
    await tester.enterText(find.widgetWithText(FieldSlot, 'Directory listing URL'), 'https://h/roms/snes/');
    await tester.enterText(find.widgetWithText(FieldSlot, 'Name'), 'My SNES');
    await tester.pump();
    await tester.tap(find.text('Add to catalog'));
    for (var i = 0; i < 100 && find.byKey(const ValueKey('kit-status-done')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('"My SNES" added to the catalog.'), findsOneWidget);
    expect(find.text('New Catalog Source'), findsOneWidget, reason: 'the screen does not close itself');
    expect(find.text('My SNES'), findsNothing, reason: 'the form is cleared');
  });
}
