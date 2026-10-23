import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

void main() {
  final saved = Handheld.current;
  tearDown(() => Handheld.current = saved);

  late RosterDoc doc;

  Future<void> pump(WidgetTester t, {PatcherInfo info = const PatcherInfo(gameId: 'g', platform: 'p', sport: 's', requiresSlotMapping: false, providers: ['x'])}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 900);
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    doc = RosterDoc(
      leagueRaw: {'name': 'L'},
      teams: [
        for (final (i, n) in ['One', 'Two', 'Three'].indexed)
          RosterTeam(teamRaw: {'id': i + 1, 'name': 'Team $n'}, players: [], statsRaw: {}, extraRaw: {}),
      ],
    );
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => SportPatcherWizardScreen(
                info: info,
                initialDoc: doc,
                initialStep: 2, // Teams
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  List<String> names() => doc.teams.map((e) => e.name).toList();

  testWidgets('swap reorders two teams by keyboard', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(names(), ['Team Three', 'Team Two', 'Team One']);
  });

  testWidgets('B cancels a swap without leaving the step', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(names(), ['Team One', 'Team Two', 'Team Three']);
    expect(find.text('Team One'), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsWidgets); // back to normal rows
  });

  bool focusInRow() {
    var inRow = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
      inRow = e.widget is ListTile;
      return !inRow;
    });
    return inRow;
  }

  testWidgets('Y on a team row starts a swap', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first); // lands focus on a row
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape); // back to normal, focus stays on the row
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.swap_vert), findsWidgets);
    await t.sendKeyEvent(LogicalKeyboardKey.f3);
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.swap_vert), findsNothing); // swap mode hides row actions
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(names(), ['Team Two', 'Team One', 'Team Three']);
  });

  testWidgets('changing step drops an armed swap, so B steps back at once', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.f5); // Start: on to the ROM step
    await t.pumpAndSettle();
    expect(find.text('Add team'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Add team'), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsWidgets); // not armed
  });

  testWidgets('deleting a team asks first', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.delete_outline).first);
    await t.pumpAndSettle();
    expect(find.text('Remove team?'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // Cancel is focused
    await t.pumpAndSettle();
    expect(doc.teams.length, 3);
    await t.tap(find.byIcon(Icons.delete_outline).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(names(), ['Team Two', 'Team Three']);
    expect(focusInRow(), isTrue);
  });

  // The tooltip (or title) of the control holding focus.
  String? focused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    String? label;
    ctx?.visitAncestorElements((e) {
      final w = e.widget;
      if (w is Tooltip) label = w.message;
      if (w is ListTile) label = (w.title as Text?)?.data;
      return label == null;
    });
    return label;
  }

  testWidgets('d-pad: every button on a team row is reachable (logo, move, remove)', (t) async {
    Handheld.current = true;
    await pump(t, info: const PatcherInfo(gameId: 'we2002', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['x'], supportsLogos: true));
    Focus.of(t.element(find.text('Team Two'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'Replace logo');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Team Two');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Move or swap');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Remove');
    // Down stays in the column: the next row's Remove.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Remove Team Three from the roster?'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(doc.teams.length, 3);
  });

  testWidgets('d-pad: a picked team moves with its arrows, keeping focus, and B ends the move', (t) async {
    Handheld.current = true;
    await pump(t);
    Focus.of(t.element(find.text('Team One'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Move or swap');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(focused(), 'Team One');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // Move up is off at the top
    expect(focused(), 'Move down');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(names(), ['Team Two', 'Team One', 'Team Three']);
    expect(focused(), 'Move down');
    // Left retraces the way in (Flutter's directional history), to the row;
    // Right from the row is Move up, now on.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'Team One');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Move up');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(names(), ['Team One', 'Team Two', 'Team Three']);
    expect(focused(), 'Team One'); // at the top Move up is off: the row has focus
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
    expect(find.text('Add team'), findsOneWidget); // still on the step
  });

  testWidgets('drag handles are hidden on handhelds', (t) async {
    Handheld.current = true;
    await pump(t);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });

  testWidgets('an armed swap turns off long-press drag (phones)', (t) async {
    Handheld.current = false;
    await pump(t);
    bool dragOn() => t.widget<ReorderableListView>(find.byType(ReorderableListView)).buildDefaultDragHandles;
    expect(dragOn(), isTrue);
    await t.tap(find.byIcon(Icons.swap_vert).first);
    await t.pump();
    expect(dragOn(), isFalse);
  });

  const nhl94 = PatcherInfo(gameId: 'nhl94-snes', platform: 'snes', sport: 'hockey', requiresSlotMapping: false, providers: ['espn']);
  RosterTeam club(int id, String name, String code) =>
      RosterTeam(teamRaw: {'id': id, 'name': name, 'code': code}, players: [], statsRaw: {}, extraRaw: {});

  Future<void> pumpNhl(WidgetTester t, List<RosterTeam> teams, Future<RomInfo> Function({required String gameId, required String romPath, List<String> codes}) analyze,
      {int step = 2, PatchResult? result}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 2400);
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: SportPatcherWizardScreen(
          info: nhl94,
          initialDoc: RosterDoc(leagueRaw: {'name': 'NHL'}, teams: teams),
          initialStep: step,
          initialRomPath: '/roms/nhl94.sfc',
          analyzeRom: analyze,
          initialResult: result,
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets("NHL '94 opens a team with its slot's roster counts, and marks a team with no slot", (t) async {
    final asked = <List<String>>[];
    await pumpNhl(t, [club(1, 'Minnesota Wild', 'MIN'), club(2, 'Boston Bruins', 'BOS')], ({required gameId, required romPath, codes = const []}) async {
      asked.add(codes);
      return RomInfo(isValid: true, slots: const [], rosterCounts: const [[2, 9, 7], [2, 15, 7]], teamSlots: {'BOS': 1});
    });
    // Slotted by code: the list order is not the slot order.
    expect(find.textContaining('slot order'), findsNothing);
    expect(find.text('Each team goes to its own slot; tap to edit a squad.'), findsOneWidget);
    expect(find.text('no slot'), findsOneWidget);
    final min = t.widget<Opacity>(find.ancestor(of: find.text('Minnesota Wild'), matching: find.byType(Opacity)).first);
    expect(min.opacity, 0.5);
    await t.tap(find.text('Boston Bruins'));
    await t.pumpAndSettle();
    expect(find.textContaining('ROM uses 2 G, 15 F, 7 D'), findsOneWidget);
    expect(asked, [['BOS', 'MIN']]); // once, on arrival
  });

  testWidgets("NHL '94 asks for the slots again after a failure, one editor per tap", (t) async {
    var calls = 0;
    await pumpNhl(t, [club(2, 'Boston Bruins', 'BOS')], ({required gameId, required romPath, codes = const []}) async {
      if (++calls == 1) throw Exception('worker down');
      return RomInfo(isValid: true, slots: const [], rosterCounts: const [[2, 9, 7], [2, 15, 7]], teamSlots: {'BOS': 1});
    });
    expect(find.text('no slot'), findsNothing); // unknown is not "no slot"
    // A double tap opens one editor.
    await t.tap(find.text('Boston Bruins'));
    await t.tap(find.text('Boston Bruins'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byType(TeamEditorScreen), findsOneWidget);
    expect(find.textContaining('ROM uses 2 G, 15 F, 7 D'), findsOneWidget);
    expect(calls, 2); // the failure on arrival was not kept
  });

  testWidgets('the Done card lists what the patch left out', (t) async {
    await pumpNhl(t, [club(2, 'Boston Bruins', 'BOS')], ({required gameId, required romPath, codes = const []}) async => const RomInfo(isValid: true, slots: []),
        step: 3, // Patch (no Look step without logos or art)
        result: const PatchResult(
          outputPath: '/out/NHL 2026 - NHL 94.sfc',
          teamsPatched: 27,
          playersPatched: 610,
          notes: ["Anaheim Ducks skipped: 1 goalie(s) in the list, NHL 94 needs 2; the slot keeps the cartridge's team"],
        ));
    expect(find.text('Teams: 27   Players: 610'), findsOneWidget);
    expect(find.textContaining('Anaheim Ducks skipped'), findsOneWidget);
  });
}
