import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// Multi-league games: the Rosters step is a league checklist (tick order =
/// slot group order) and the Teams step has one section per league. Games
/// whose slot groups only describe the slots (WE2002) keep one league.
void main() {
  // Three groups, two leagues: the third group is not a league of its own.
  const info = PatcherInfo(
    gameId: 'pes2013-ps2',
    platform: 'ps2',
    sport: 'soccer',
    requiresSlotMapping: true,
    providers: ['espn'],
    supportsKits: true,
    supportsNationals: true,
    slotGroups: [SlotGroup('England', 0, 20), SlotGroup('France', 20, 2), SlotGroup('Other', 22, 10)],
    maxLeagues: 2,
  );
  const we2002 = PatcherInfo(
    gameId: 'we2002',
    platform: 'psx',
    sport: 'soccer',
    requiresSlotMapping: true,
    providers: ['espn'],
    supportsKits: true,
    slotGroups: [SlotGroup('Master League', 0, 32), SlotGroup('National only', 32, 31)],
  );
  const leagues = [
    League(id: 1, name: 'Brasileirão', country: 'Brazil'),
    League(id: 2, name: 'Liga MX', country: 'Mexico'),
    League(id: 3, name: 'MLS', country: 'USA'),
  ];

  RosterDoc doc(String league, List<String> names) => RosterDoc(
        leagueRaw: {'name': league},
        teams: [
          for (final (i, n) in names.indexed)
            RosterTeam(teamRaw: {'id': i + 1, 'name': n}, players: [], statsRaw: {}, extraRaw: {}),
        ],
      );

  // Steps: 0 ROM, 1 Rosters, 2 Teams.
  Future<void> pump(WidgetTester t, {int step = 1, List<RosterDoc>? docs, PatcherInfo game = info}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 900);
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: SportPatcherWizardScreen(info: game, initialStep: step, initialLeagues: leagues, initialDocs: docs),
      ),
    ));
    await t.pumpAndSettle();
  }

  Finder box(String league) => find.ancestor(of: find.text(league), matching: find.byType(CheckboxListTile));

  testWidgets('ticked leagues are numbered by tick order and capped at the game\'s leagues', (t) async {
    await pump(t);
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    expect(find.text('National teams'), findsOneWidget);
    expect(find.text('0 of 2 leagues'), findsOneWidget);
    expect(find.textContaining('holds up to 2 leagues'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNull);

    await t.tap(box('Liga MX · Mexico'));
    await t.pumpAndSettle();
    expect(find.text('Liga MX → Group 1 (England, 20 teams)'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNotNull);

    await t.tap(box('Brasileirão · Brazil'));
    await t.pumpAndSettle();
    expect(find.text('Brasileirão → Group 2 (France, 2 teams)'), findsOneWidget);
    // Two leagues at most, though there is a third group: MLS cannot be ticked.
    expect(find.text('2 of 2 leagues'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(box('MLS · USA')).enabled, isFalse);

    // Unticking the first moves the other up a group.
    await t.tap(box('Liga MX · Mexico'));
    await t.pumpAndSettle();
    expect(find.text('Brasileirão → Group 1 (England, 20 teams)'), findsOneWidget);
    expect(find.textContaining('Liga MX →'), findsNothing);
    expect(t.widget<CheckboxListTile>(box('MLS · USA')).enabled, isTrue);
  });

  testWidgets('the Teams step shows a section per league with its slots; extra teams get none', (t) async {
    await pump(t, step: 2, docs: [doc('Brasileirão', ['Flamengo', 'Palmeiras']), doc('Liga MX', ['América', 'Chivas', 'Tigres'])]);
    expect(find.text('Brasileirão'), findsOneWidget);
    expect(find.text('slots 1–20'), findsOneWidget);
    expect(find.text('Liga MX'), findsOneWidget);
    // Tigres is the third team of a two-slot group: greyed, and the section
    // says so.
    expect(find.text('slots 21–22 · 1 team gets no slot'), findsOneWidget);
    expect(find.text('no slot'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNWidgets(2));
  });

  testWidgets('WE2002 takes one league: a picker, and no nationals switch', (t) async {
    expect(we2002.multiLeague, isFalse);
    await pump(t, game: we2002);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining(RegExp(r'\d+ of \d+ leagues')), findsNothing);
    expect(find.text('National teams'), findsNothing);
    expect(find.text('Select a league'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNull);

    await t.tap(find.text('Select a league'));
    await t.pumpAndSettle();
    await t.tap(find.text('Liga MX · Mexico').last);
    await t.pumpAndSettle();
    expect(find.text('Liga MX · Mexico'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNotNull);
  });

  testWidgets('WE2002 Teams step: one list in slot order, every team with a slot', (t) async {
    final clubs = [for (var i = 0; i < 34; i++) 'Club $i'];
    await pump(t, game: we2002, step: 2, docs: [doc('Liga MX', clubs)]);
    expect(find.text('Liga MX'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.textContaining('slots '), findsNothing);
    // Past the 32 Master League slots the teams run on into the national-only
    // ones; none is dropped.
    await t.scrollUntilVisible(find.text('Club 33'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('no slot'), findsNothing);
    expect(find.text('Add team'), findsOneWidget);
  });
}
