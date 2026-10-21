import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// The Look step: shown only for games whose logos or screen art the patch
/// can change, with a switch per flag and a card per screen art slot.
void main() {
  const visual = PatcherInfo(
    gameId: 'g',
    platform: 'p',
    sport: 's',
    requiresSlotMapping: false,
    providers: ['x'],
    supportsLogos: true,
    supportsBlankUnused: true,
    imageSlots: ['title', 'menu', 'boot'],
  );
  const plain = PatcherInfo(gameId: 'g', platform: 'p', sport: 's', requiresSlotMapping: false, providers: ['x']);

  Future<void> pump(WidgetTester t, PatcherInfo info, {int step = 3}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 900);
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    final doc = RosterDoc(
      leagueRaw: {'name': 'L'},
      teams: [RosterTeam(teamRaw: {'id': 1, 'name': 'Team One'}, players: [], statsRaw: {}, extraRaw: {})],
    );
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: SportPatcherWizardScreen(info: info, initialDoc: doc, initialStep: step),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('the Look step lists the flags and one card per slot', (t) async {
    await pump(t, visual);
    expect(find.text('Look'), findsWidgets);
    expect(find.text('Team logos'), findsOneWidget);
    expect(find.text('Blank unused slots'), findsOneWidget);
    for (final name in ['Title screen', 'Main menu', 'Boot screens']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Replace'), findsNWidgets(3));
    // Nothing replaced yet: every card says so, no reset button.
    expect(find.text('Original'), findsNWidgets(3));
    expect(find.byIcon(Icons.restart_alt), findsNothing);
  });

  testWidgets('the switches toggle and Start moves on to Patch', (t) async {
    await pump(t, visual);
    final blank = find.byType(SwitchListTile).last;
    expect(t.widget<SwitchListTile>(blank).value, isFalse);
    await t.tap(blank);
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile).last).value, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    expect(find.text('Output folder'), findsOneWidget);
  });

  testWidgets('a game without visuals goes from ROM straight to Patch', (t) async {
    await pump(t, plain, step: 2);
    expect(find.text('Select ROM'), findsOneWidget);
    expect(find.text('Look'), findsNothing);
  });

  testWidgets('crests are buttons only when the patch draws logos', (t) async {
    await pump(t, visual, step: 1);
    expect(find.byTooltip('Replace logo'), findsOneWidget);
    await pump(t, plain, step: 1);
    expect(find.byTooltip('Replace logo'), findsNothing);
  });
}
