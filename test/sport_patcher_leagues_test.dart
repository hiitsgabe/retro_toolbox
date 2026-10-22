import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// Multi-league games: the Rosters step is a league checklist (tick order =
/// slot group order) and the Teams step has one section per league.
void main() {
  const info = PatcherInfo(
    gameId: 'pes2013-ps2',
    platform: 'ps2',
    sport: 'soccer',
    requiresSlotMapping: true,
    providers: ['espn'],
    supportsKits: true,
    supportsNationals: true,
    slotGroups: [SlotGroup('England', 0, 20), SlotGroup('France', 20, 2)],
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
  Future<void> pump(WidgetTester t, {int step = 1, List<RosterDoc>? docs}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 900);
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: SportPatcherWizardScreen(info: info, initialStep: step, initialLeagues: leagues, initialDocs: docs),
      ),
    ));
    await t.pumpAndSettle();
  }

  Finder box(String league) => find.ancestor(of: find.text(league), matching: find.byType(CheckboxListTile));

  testWidgets('ticked leagues are numbered by tick order and capped at the slot groups', (t) async {
    await pump(t);
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    expect(find.text('National teams'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNull);

    await t.tap(box('Liga MX · Mexico'));
    await t.pumpAndSettle();
    expect(find.text('Liga MX → Group 1 (England, 20 teams)'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNotNull);

    await t.tap(box('Brasileirão · Brazil'));
    await t.pumpAndSettle();
    expect(find.text('Brasileirão → Group 2 (France, 2 teams)'), findsOneWidget);
    // Two groups, two leagues: the third cannot be ticked.
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
    expect(find.text('slots 21–22'), findsOneWidget);
    // Tigres is the third team of a two-slot group.
    expect(find.text('no slot'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNWidgets(2));
  });
}
