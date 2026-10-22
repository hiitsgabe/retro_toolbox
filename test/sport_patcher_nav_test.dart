import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

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
    expect(find.text('Next'), findsOneWidget);
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
}
