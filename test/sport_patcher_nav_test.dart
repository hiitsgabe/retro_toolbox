import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

void main() {
  late GlobalKey<NavigatorState> key;
  var popped = false;

  // Steps: 0 ROM, 1 Rosters, 2 Teams, 3 Patch (no Look for this game).
  Future<void> pump(WidgetTester t, {int step = 2}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 900);
    addTearDown(t.view.reset);
    key = GlobalKey<NavigatorState>();
    popped = false;
    final doc = RosterDoc(
      leagueRaw: {'name': 'L'},
      teams: [RosterTeam(teamRaw: {'id': 1, 'name': 'Team One'}, players: [], statsRaw: {}, extraRaw: {})],
    );
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              await Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => SportPatcherWizardScreen(
                  info: const PatcherInfo(
                      gameId: 'g', platform: 'p', sport: 's', requiresSlotMapping: false, providers: ['x']),
                  initialDoc: doc,
                  initialStep: step,
                  initialRomPath: '/roms/game.bin',
                ),
              ));
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('Start advances when the step can advance', (t) async {
    await pump(t);
    expect(find.descendant(of: find.byKey(const ValueKey('kit-primary')), matching: find.text('NEXT')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    // Now on the Patch step: the step advanced past Teams.
    expect(find.text('Add team'), findsNothing);
    expect(find.text('Output folder'), findsOneWidget);
  });

  testWidgets('Start pressed repeatedly advances step by step from a cold route', (t) async {
    await pump(t, step: 0);
    expect(find.text('Select ROM'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.f5); // a ROM is chosen: on to Rosters
    await t.pumpAndSettle();
    expect(find.text('Select ROM'), findsNothing);
    expect(find.text('Rosters'), findsWidgets);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    expect(find.text('Add team'), findsOneWidget); // Teams
    // A quiet button in the list's header, not a filled round one over the step.
    expect(find.ancestor(of: find.text('Add team'), matching: find.byWidgetPredicate((w) => w is TextButton)), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    expect(find.text('Output folder'), findsOneWidget); // Patch
  });

  testWidgets('B goes back a step instead of leaving; on step 0 it leaves', (t) async {
    await pump(t, step: 2);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Add team'), findsNothing); // back on Rosters
    expect(popped, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Select ROM'), findsOneWidget); // ROM step
    expect(popped, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(popped, isTrue);
  });

  Finder secondary(String label) => find.descendant(of: find.byKey(const ValueKey('kit-secondary')), matching: find.text(label));

  testWidgets('the header names the game and the step; Back and the step action are in the bar, never in the header', (t) async {
    await pump(t, step: 2);
    expect(find.text('Step 3 of 4 · Teams'), findsOneWidget);
    expect(find.byKey(const ValueKey('kit-back')), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(secondary('BACK'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kit-secondary')));
    await t.pumpAndSettle();
    expect(find.text('Step 2 of 4 · Rosters'), findsOneWidget);
  });

  // A desktop has no back key: the first step still has a way out.
  testWidgets('the first step offers Cancel, which leaves', (t) async {
    await pump(t, step: 0);
    expect(secondary('CANCEL'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kit-secondary')));
    await t.pumpAndSettle();
    expect(popped, isTrue);
  });

  testWidgets('an armed swap turns Back into Cancel swap', (t) async {
    await pump(t, step: 2);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pumpAndSettle();
    expect(secondary('CANCEL SWAP'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kit-secondary')));
    await t.pumpAndSettle();
    expect(secondary('BACK'), findsOneWidget);
    expect(find.text('Step 3 of 4 · Teams'), findsOneWidget);
  });

  testWidgets('the Patch step: Patch ROM in the bar, and with a pad the focus lands on the output folder', (t) async {
    await pump(t, step: 2);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    expect(find.text('Step 4 of 4 · Patch'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kit-primary')), matching: find.text('PATCH ROM')), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(focused.findAncestorWidgetOfExactType<Slot>()?.label, 'Output folder');
  });
}
