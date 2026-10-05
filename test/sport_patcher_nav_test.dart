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

  Future<void> pump(WidgetTester t, {int step = 1}) async {
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
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // focus lands in the screen
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    // Now on the ROM step: Back is still there and the step advanced past Teams.
    expect(find.text('Add team'), findsNothing);
  });

  testWidgets('B goes back a step instead of leaving; on step 0 it leaves', (t) async {
    await pump(t, step: 2);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Add team'), findsOneWidget); // back on Teams
    expect(popped, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Add team'), findsNothing); // rosters step
    expect(popped, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(popped, isTrue);
  });
}
