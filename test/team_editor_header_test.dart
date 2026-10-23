import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// The team page's header (rename, logo) and moving players by d-pad.
void main() {
  const we = PatcherInfo(gameId: 'we2002', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn'], supportsLogos: true);
  const nhl = PatcherInfo(gameId: 'nhl94-snes', platform: 'snes', sport: 'hockey', requiresSlotMapping: false, providers: ['espn']);

  RosterTeam team({List<String> players = const ['Ann', 'Ben', 'Cal']}) => RosterTeam(
        teamRaw: {'id': 9, 'name': 'Galo', 'code': 'CAM'},
        // Negative ids: no headshot URL, so nothing reaches the network.
        players: [for (final n in players) RosterPlayer(raw: {'id': -n.codeUnitAt(0), 'name': n, 'position': 'F'})],
        statsRaw: {},
        extraRaw: {},
      );

  Future<void> pump(WidgetTester t, RosterTeam tm, {PatcherInfo info = we, Map<int, String>? logos}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1000, 1200);
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: key,
      builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
            builder: (_) => TeamEditorScreen(team: tm, gameId: info.gameId, sport: info.sport, info: info, teamLogos: logos),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  // The tooltip (or text) of the control holding focus.
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

  testWidgets('the header renames the team and its short name, and resets the logo, from the d-pad', (t) async {
    final tm = team();
    final logos = {9: '/logos/galo.png', 3: '/logos/other.png'};
    await pump(t, tm, logos: logos);
    expect(find.textContaining('CAM · 3 players · ROM uses'), findsOneWidget);

    // Up from the first player reaches the header's button.
    Focus.of(t.element(find.text('Ann'))).requestFocus();
    await t.pump();
    for (var i = 0; i < 6 && focused() != 'Rename or change logo'; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    expect(focused(), 'Rename or change logo');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Edit team'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextField, 'Name'), '  Atlético Mineiro ');
    await t.enterText(find.widgetWithText(TextField, 'Short name'), 'atl');
    await t.tap(find.text('Downloaded logo'));
    await t.pump();
    expect(find.text('Downloaded logo'), findsNothing);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    // What the patch reads: team.name, team.code, the wizard's logo map.
    expect(tm.name, 'Atlético Mineiro');
    expect(tm.toJson()['team'], containsPair('code', 'ATL'));
    expect(logos, {3: '/logos/other.png'});
    expect(find.text('Atlético Mineiro'), findsNWidgets(2)); // app bar and header
  });

  testWidgets('Cancel keeps everything; a blank name is not taken', (t) async {
    final tm = team();
    final logos = {9: '/logos/galo.png'};
    await pump(t, tm, logos: logos);
    await t.tap(find.byTooltip('Rename or change logo'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'X');
    await t.tap(find.text('Downloaded logo'));
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(tm.name, 'Galo');
    expect(logos, {9: '/logos/galo.png'});

    await t.tap(find.byTooltip('Rename or change logo'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), '   ');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(tm.name, 'Galo');
  });

  testWidgets('a game that slots teams by code renames only; no logos, no logo buttons; an empty squad still has the header', (t) async {
    final tm = team(players: const []);
    await pump(t, tm, info: nhl);
    expect(find.text('No players. Add one.'), findsOneWidget);
    await t.tap(find.byTooltip('Rename team'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Short name'), findsNothing);
    expect(find.text('Choose logo…'), findsNothing);
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Wild');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(tm.name, 'Wild');
    expect(tm.code, 'CAM'); // the slot key is untouched
  });

  testWidgets('d-pad: Right reaches a row\'s buttons; Move picks the row and its arrows move it', (t) async {
    final tm = team(players: const ['Ann', 'Ben', 'Cal', 'Dan']);
    await pump(t, tm, info: nhl);
    Focus.of(t.element(find.text('Ann'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Move or swap');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Remove');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // pick Ann
    await t.pumpAndSettle();
    expect(find.textContaining('swap with Ann'), findsOneWidget);
    expect(focused(), 'Ann');

    // Right to the arrows: Up is off at the top, so focus skips to Down.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Move down');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // focus stayed on Move down
    await t.pumpAndSettle();
    expect(tm.players.map((p) => p.name), ['Ben', 'Cal', 'Ann', 'Dan']);
    expect(focused(), 'Move down');
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // to the bottom: the row takes focus
    await t.pumpAndSettle();
    expect(tm.players.map((p) => p.name), ['Ben', 'Cal', 'Dan', 'Ann']);
    expect(focused(), 'Ann');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Move up');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(tm.players.map((p) => p.name), ['Ben', 'Cal', 'Ann', 'Dan']);

    // B ends the move; the order stays.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.textContaining('swap with'), findsNothing);
    expect(find.byType(TeamEditorScreen), findsOneWidget);
    expect(tm.players.map((p) => p.name), ['Ben', 'Cal', 'Ann', 'Dan']);
  });
}
