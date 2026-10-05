import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/screens/setup_wizard_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a console uses the Internet Archive through an IA url or IA auth', () {
    expect(const Console(id: 'a', name: 'A', urls: ['https://archive.org/download/item']).usesInternetArchive, isTrue);
    expect(const Console(id: 'b', name: 'B', urls: ['https://example.com/list'], auth: {'type': 'ia_s3'}).usesInternetArchive, isTrue);
    expect(const Console(id: 'c', name: 'C', urls: ['https://example.com/list']).usesInternetArchive, isFalse);
  });

  testWidgets('the connections step hides the IA login when no console uses IA', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('setup');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SetupWizardScreen(initialStep: 2))));
    await tester.pump();

    expect(find.text('Internet Archive'), findsNothing);
    expect(find.text('No accounts needed for this catalog.'), findsOneWidget);
  });

  Future<List<String>> pumpWizard(WidgetTester tester, {required int step, required List<bool> popped}) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('setup');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 600);
    addTearDown(tester.view.reset);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              await Navigator.of(ctx).push(
                  MaterialPageRoute<void>(builder: (_) => SetupWizardScreen(initialStep: step)));
              popped.add(true);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return [];
  }

  testWidgets('Start advances a step; B goes back; B on step 0 marks seen and leaves', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 1, popped: popped);
    expect(find.text('2/3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('3/3 · Connections'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('2/3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('1/3 · Catalog'), findsOneWidget);
    expect(popped, isEmpty);
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
    expect((await SharedPreferences.getInstance()).getBool(SetupWizardScreen.seenKey), isTrue);
  });

  testWidgets('Start on the last step finishes (marks seen)', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 2, popped: popped);
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
    expect((await SharedPreferences.getInstance()).getBool(SetupWizardScreen.seenKey), isTrue);
  });

  testWidgets('Start pressed repeatedly walks the wizard from a cold route', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 0, popped: popped);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('2/3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('3/3 · Connections'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
  });

  testWidgets('two quick backs on step 0 leave once (the page below stays)', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 0, popped: popped);
    // Two backs in one turn, both before markSeen returns (on device it is
    // slow enough for two quick presses).
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await tester.runAsync(() async {
      nav.maybePop();
      nav.maybePop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
    expect(find.text('open'), findsOneWidget);
  });
}
