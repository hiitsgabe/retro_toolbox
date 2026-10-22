import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// The Look step: shown only for games whose logos or screen art the patch
/// can change, with a switch per flag and a card per screen art slot.
/// Steps: 0 ROM, 1 Rosters, 2 Teams, 3 Look, 4 Patch.
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

  final savedHandheld = Handheld.current;
  tearDown(() => Handheld.current = savedHandheld);

  Future<void> pump(
    WidgetTester t,
    PatcherInfo info, {
    int step = 3,
    String? romPath,
    Map<String, String>? images,
    Future<String> Function(String gameId, {String? romPath})? templatesZip,
  }) async {
    t.view.devicePixelRatio = 1;
    // Tall enough for every card (the list is lazy): Look now has a Kits card too.
    t.view.physicalSize = const Size(1200, 1400);
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
        home: SportPatcherWizardScreen(
          info: info,
          initialDoc: doc,
          initialStep: step,
          initialRomPath: romPath,
          initialImages: images,
          templatesZip: templatesZip,
        ),
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

  testWidgets('the template pack button comes with the screen art slots', (t) async {
    await pump(t, visual);
    expect(find.text('Download templates'), findsOneWidget);
    // Logos alone give a Look step, but no screen art and no templates.
    const logosOnly = PatcherInfo(gameId: 'g', platform: 'p', sport: 's', requiresSlotMapping: false, providers: ['x'], supportsLogos: true);
    await pump(t, logosOnly);
    expect(find.text('Team logos'), findsOneWidget);
    expect(find.text('Screen art'), findsNothing);
    expect(find.text('Download templates'), findsNothing);
  });

  testWidgets('the templates button is off while its job runs, then saves next to the ROM (handheld)', (t) async {
    Handheld.current = true;
    final dir = Directory.systemTemp.createTempSync('tpl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final zip = File('${dir.path}/src/g-templates.zip')..createSync(recursive: true);
    zip.writeAsStringSync('zip');
    final job = Completer<String>();
    // Previews given, so the ROM's art is not exported through the worker.
    await pump(t, visual, romPath: '${dir.path}/game.bin', images: const {}, templatesZip: (g, {romPath}) => job.future);
    final button = find.widgetWithText(TextButton, 'Download templates');
    await t.tap(button);
    await t.pump();
    expect(t.widget<TextButton>(button).onPressed, isNull); // in flight
    // The copy is real file IO, which only completes outside the fake async zone.
    await t.runAsync(() async {
      job.complete(zip.path);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(t.widget<TextButton>(button).onPressed, isNotNull);
    expect(File('${dir.path}/g-templates.zip').existsSync(), isTrue);
    expect(find.text('Templates saved to ${dir.path}/g-templates.zip'), findsOneWidget);
  });

  testWidgets('a game without visuals goes from Teams straight to Patch', (t) async {
    await pump(t, plain, step: 3);
    expect(find.text('Output folder'), findsOneWidget);
    expect(find.text('Look'), findsNothing);
  });

  testWidgets('crests are buttons only when the patch draws logos', (t) async {
    await pump(t, visual, step: 2);
    expect(find.byTooltip('Replace logo'), findsOneWidget);
    await pump(t, plain, step: 2);
    expect(find.byTooltip('Replace logo'), findsNothing);
  });
}
