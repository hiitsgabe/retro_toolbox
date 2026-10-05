import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/setup_wizard_screen.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late bool saved;
  setUp(() => saved = Handheld.current);
  tearDown(() => Handheld.current = saved);

  Future<void> pumpSetup(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('copy');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 900);
    addTearDown(t.view.reset);
    await t.pumpWidget(const ProviderScope(child: MaterialApp(home: SetupWizardScreen(initialStep: 0))));
    await t.pump();
  }

  testWidgets('setup wizard: handheld copy does not mention pasting', (t) async {
    Handheld.current = true;
    await pumpSetup(t);
    expect(find.textContaining('paste'), findsNothing);
    expect(find.textContaining('Import a JSON file or load one from a URL'), findsOneWidget);
  });

  testWidgets('setup wizard: other platforms still mention pasting', (t) async {
    Handheld.current = false;
    await pumpSetup(t);
    expect(find.textContaining('paste it directly'), findsOneWidget);
  });

  Future<void> openAddTeam(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 900);
    addTearDown(t.view.reset);
    final doc = RosterDoc(leagueRaw: {'name': 'L'}, teams: []);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: SportPatcherWizardScreen(
          info: const PatcherInfo(gameId: 'g', platform: 'p', sport: 's', requiresSlotMapping: false, providers: ['x']),
          initialDoc: doc,
          initialStep: 1,
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.text('Add team'));
    await t.pumpAndSettle();
  }

  testWidgets('team dialog: handheld copy does not mention pasting', (t) async {
    Handheld.current = true;
    await openAddTeam(t);
    expect(find.text('Or import team JSON'), findsOneWidget);
    await t.tap(find.text('Add'));
    await t.pump();
    expect(find.text('Enter a name or import a file'), findsOneWidget);
    expect(find.textContaining('paste'), findsNothing);
  });

  testWidgets('team dialog: other platforms keep paste wording', (t) async {
    Handheld.current = false;
    await openAddTeam(t);
    expect(find.text('Or paste / import team JSON'), findsOneWidget);
  });
}
