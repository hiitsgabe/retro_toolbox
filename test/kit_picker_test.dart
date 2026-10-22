import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';
import 'package:retro_toolbox/services/sports_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit_picker.dart';

/// The team editor's Kits section and the picker it opens, with the preview
/// job stubbed out.
void main() {
  const info = PatcherInfo(
    gameId: 'pes2013-ps2',
    platform: 'ps2',
    sport: 'soccer',
    requiresSlotMapping: true,
    providers: ['espn'],
    supportsKits: true,
  );

  // A player, because the editor's header (colours, kits) only shows above a squad.
  RosterTeam team() => RosterTeam(
        teamRaw: {'id': 7, 'name': 'Flamengo', 'color': 'C60000', 'alternate_color': '000000'},
        players: [
          RosterPlayer(raw: {'id': 1, 'name': 'Ann', 'position': 'GK'})
        ],
        statsRaw: {},
        extraRaw: {},
      );

  final savedHandheld = Handheld.current;
  tearDown(() => Handheld.current = savedHandheld);

  final requested = <({Map<String, dynamic> kits, Map<String, int>? slots, Map<String, String>? which, Map<String, List<String>>? colours})>[];
  // Header previews get a path naming the choice, so a refresh is visible by key.
  Future<KitPreviews> fakeLoader(Map<String, dynamic> kits,
      {bool templates = false, Map<String, int>? slots, Map<String, String>? which, Map<String, List<String>>? colours}) async {
    requested.add((kits: kits, slots: slots, which: which, colours: colours));
    return (
      kits: {
        for (final k in kits.keys)
          if (k.startsWith('current_')) k: '/p/$k=${kitLabel(kits[k])}.png'
      },
      templates: <KitTemplate>[],
    );
  }

  Iterable<Map<String, dynamic>> patternJobs() => requested.map((r) => r.kits).where((k) => k.length == 16);

  setUp(requested.clear);

  Future<void> pump(WidgetTester t, Widget page) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1000, 1400);
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: key,
      builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => page)),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  Widget editor(
    RosterTeam tm, {
    PatcherInfo? game = info,
    String? romPath = '/roms/pes.iso',
    int? slot = 3,
    KitPreviewLoader? loader,
    Future<String> Function(String, {required String romPath, required int slot, int? template})? zip,
  }) =>
      TeamEditorScreen(
        team: tm,
        gameId: game?.gameId ?? 'pes2013-ps2',
        sport: 'soccer',
        info: game,
        romPath: romPath,
        slot: slot,
        kitLoader: loader ?? fakeLoader,
        kitTemplateZip: zip,
      );

  testWidgets('Home kit row opens the picker; Right + Enter stores stripes', (t) async {
    final tm = team();
    await pump(t, editor(tm));
    expect(find.text('Home kit'), findsOneWidget);
    expect(find.text('Away kit'), findsOneWidget);
    expect(find.text('Default'), findsNWidgets(2));
    // The raw (default) choice goes with the team's colours, slot and side.
    final first = requested.single;
    expect(first.kits, {'home': null, 'away': null});
    expect(first.slots, {'home': 3, 'away': 3});
    expect(first.which, {'home': 'home', 'away': 'away'});
    expect(first.colours, {
      'home': ['#c60000', '#000000'],
      'away': ['#c60000', '#000000']
    });

    await t.tap(find.text('Home kit'));
    await t.pumpAndSettle();
    expect(find.text('Flamengo kits'), findsOneWidget);
    // Sixteen previews asked for: eight patterns in the home colours, eight away.
    expect(patternJobs().single['away_hoops'], containsPair('shirt', '#000000'));
    // The header shows the current (default) choice, mounted on this slot.
    expect(find.byKey(const ValueKey('/p/current_home=Default.png')), findsOneWidget);
    final header = requested.last;
    expect(header.kits, {'current_home': null});
    expect(header.slots, {'current_home': 3});
    expect(header.which, {'current_home': 'home'});
    expect(header.colours, {
      'current_home': ['#c60000', '#000000']
    });
    // The grid's specs come with the colours too.
    expect(patternJobs().length, 1);
    expect(requested.firstWhere((r) => r.kits.length == 16).colours?['home_stripes'], ['#c60000', '#000000']);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // Plain is autofocused
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    final kits = tm.extraRaw['kits'] as Map;
    expect(kits['home']['pattern'], 'stripes');
    expect(kits['home']['shirt'], '#c60000');
    expect(kits['away'], isNull);
    // The header was re-rendered for the new choice.
    expect(find.byKey(const ValueKey('/p/current_home=Stripes.png')), findsOneWidget);
    expect(find.byKey(const ValueKey('/p/current_home=Default.png')), findsNothing);
    expect(requested.last.kits['current_home'], containsPair('pattern', 'stripes'));

    final before = requested.length;
    await t.sendKeyEvent(LogicalKeyboardKey.escape); // closes the picker
    await t.pumpAndSettle();
    expect(find.byType(KitPickerSheet), findsNothing);
    expect(find.text('Stripes'), findsOneWidget); // the row shows the choice
    expect(requested.length, before + 1); // the rows re-rendered on return
    expect(requested.last.kits['home'], containsPair('pattern', 'stripes'));
  });

  testWidgets('without a ROM the default is still the worker\'s, drawn from the colours sent', (t) async {
    await pump(t, editor(team(), romPath: null));
    final first = requested.single;
    expect(first.kits, {'home': null, 'away': null});
    expect(first.colours?['away'], ['#c60000', '#000000']);
    expect(first.slots, {'home': 3, 'away': 3});
  });

  testWidgets('a game design the worker did not render shows its own thumbnail; a missing preview is dropped', (t) async {
    const we =
        PatcherInfo(gameId: 'we2002', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn'], supportsKits: true, kitTemplates: true);
    var calls = 0;
    Future<KitPreviews> loader(Map<String, dynamic> kits,
        {bool templates = false, Map<String, int>? slots, Map<String, String>? which, Map<String, List<String>>? colours}) async {
      calls++;
      return (
        // No preview for a design; after the first call none for the away kit either.
        kits: {
          for (final e in kits.entries)
            if ((e.value is! Map || e.value['template'] == null) && !(e.key == 'away' && calls > 1)) e.key: '/p/${e.key}$calls.png',
        },
        templates: templates ? const [KitTemplate(index: 44, name: 'Design 44', path: '/t/44.png')] : const <KitTemplate>[],
      );
    }

    final tm = team();
    await pump(t, editor(tm, game: we, loader: loader));
    expect(find.byKey(const ValueKey('/p/home1.png')), findsOneWidget);
    expect(find.byKey(const ValueKey('/p/away1.png')), findsOneWidget);

    await t.tap(find.text('Home kit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Design 44'));
    await t.pumpAndSettle();
    expect((tm.extraRaw['kits'] as Map)['home'], {'template': 44});
    // The header falls back to the design's thumbnail (the grid tile has it too).
    expect(find.byKey(const ValueKey('/t/44.png')), findsNWidgets(2));

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Design 44'), findsOneWidget); // the row label
    expect(find.byKey(const ValueKey('/t/44.png')), findsOneWidget); // the home row
    expect(find.byKey(const ValueKey('/p/home1.png')), findsNothing); // not the stale render
    expect(find.byKey(const ValueKey('/p/away1.png')), findsNothing); // dropped, not kept
    expect(find.byKey(ValueKey('/p/away$calls.png')), findsNothing);
  });

  testWidgets('the kit template button is off while its job runs, then saves next to the ROM (handheld)', (t) async {
    Handheld.current = true;
    final dir = Directory.systemTemp.createTempSync('kit_tpl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final zip = File('${dir.path}/src/we2002-kits.zip')..createSync(recursive: true);
    zip.writeAsStringSync('zip');
    final job = Completer<String>();
    final args = <(String, int, int?)>[];
    Future<String> fakeZip(String gameId, {required String romPath, required int slot, int? template}) {
      args.add((romPath, slot, template));
      return job.future;
    }

    final tm = team();
    tm.extraRaw['kits'] = {
      'home': {'template': 7},
      'away': null
    };
    await pump(t, editor(tm, romPath: '${dir.path}/we2002.bin', zip: fakeZip));
    final button = find.widgetWithText(TextButton, 'Download kit template');
    await t.tap(button);
    await t.pump();
    expect(args, [('${dir.path}/we2002.bin', 3, 7)]);
    expect(t.widget<TextButton>(button).onPressed, isNull); // in flight
    // The copy is real file IO, which only completes outside the fake async zone.
    await t.runAsync(() async {
      job.complete(zip.path);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(t.widget<TextButton>(button).onPressed, isNotNull);
    expect(File('${dir.path}/we2002-kits.zip').existsSync(), isTrue);
    expect(find.text('Kit template saved to ${dir.path}/we2002-kits.zip'), findsOneWidget);
  });

  testWidgets('the Away row opens on the away side; Back to default clears it', (t) async {
    final tm = team();
    await pump(t, editor(tm));
    await t.tap(find.text('Away kit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hoops'));
    await t.pumpAndSettle();
    expect((tm.extraRaw['kits'] as Map)['away']['pattern'], 'hoops');
    expect((tm.extraRaw['kits'] as Map)['home'], isNull);
    await t.tap(find.text('Back to default'));
    await t.pumpAndSettle();
    expect((tm.extraRaw['kits'] as Map)['away'], isNull);
  });

  testWidgets('a colour change becomes a spec and re-renders; PES shows the PNG note', (t) async {
    final tm = team();
    await pump(t, KitPickerSheet(team: tm, info: info, loader: fakeLoader, initialHome: false));
    await t.tap(find.text('Shorts'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect((tm.extraRaw['kits'] as Map)['away']['shorts'], '#c2185b');
    expect(patternJobs().length, 2); // the grid re-rendered in the new colours
    expect(find.byKey(const ValueKey('/p/current_away=Plain.png')), findsOneWidget);
    expect(find.text('PES uses the picture for its colours and pattern only.'), findsOneWidget);
  });

  testWidgets('no Kits section without supportsKits', (t) async {
    await pump(t, editor(team(), game: null));
    expect(find.text('Home kit'), findsNothing);
    expect(find.text('Download kit template'), findsNothing);
    expect(requested, isEmpty);
    const noKits = PatcherInfo(gameId: 'pes2013-ps2', platform: 'ps2', sport: 'soccer', requiresSlotMapping: true, providers: ['espn']);
    await pump(t, editor(team(), game: noKits));
    expect(find.text('Home kit'), findsNothing);
  });

  testWidgets('the kit template button needs a ROM and a slot', (t) async {
    await pump(t, editor(team()));
    final button = find.widgetWithText(TextButton, 'Download kit template');
    expect(button, findsOneWidget);
    expect(t.widget<TextButton>(button).onPressed, isNotNull);
    await pump(t, editor(team(), romPath: null));
    expect(t.widget<TextButton>(find.widgetWithText(TextButton, 'Download kit template')).onPressed, isNull);
  });

  testWidgets('without a ROM the picker says where the game designs come from', (t) async {
    const we =
        PatcherInfo(gameId: 'we2002', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn'], supportsKits: true, kitTemplates: true);
    await pump(t, KitPickerSheet(team: team(), info: we, loader: fakeLoader));
    expect(find.text('Pick the ROM first to see the game\'s own designs.'), findsOneWidget);
    await pump(t, KitPickerSheet(team: team(), info: we, loader: fakeLoader, romPath: '/roms/we.bin'));
    expect(find.textContaining('Pick the ROM first'), findsNothing);
  });

  testWidgets('the picker\'s Template tile downloads this slot\'s kit template', (t) async {
    const we =
        PatcherInfo(gameId: 'we2002', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn'], supportsKits: true, kitTemplates: true);
    final args = <(String, String, int, int?)>[];
    Future<String> fakeZip(String gameId, {required String romPath, required int slot, int? template}) async {
      args.add((gameId, romPath, slot, template));
      throw StateError('no worker');
    }

    final tm = team();
    tm.extraRaw['kits'] = {
      'home': {'template': 7},
      'away': null
    };
    InkWell tile() => t.widget<InkWell>(find.ancestor(of: find.text('Template'), matching: find.byType(InkWell)).first);

    await pump(t, KitPickerSheet(team: tm, info: we, loader: fakeLoader, romPath: '/roms/we.bin', slot: 5, kitTemplateZip: fakeZip));
    expect(find.text('Template'), findsOneWidget);
    expect(find.text('Choose…'), findsOneWidget);
    expect(tile().onTap, isNotNull);
    await t.tap(find.text('Template'));
    await t.pumpAndSettle();
    expect(args, [('we2002', '/roms/we.bin', 5, 7)]); // the home kit's design
    expect(find.text('Kit template: Bad state: no worker'), findsOneWidget);
    expect(tile().onTap, isNotNull); // re-enabled after the job

    // The away kit is a plain default: no design goes with it.
    await t.tap(find.text('Away'));
    await t.pumpAndSettle();
    await t.tap(find.text('Template'));
    await t.pumpAndSettle();
    expect(args.last, ('we2002', '/roms/we.bin', 5, null));

    await pump(t, KitPickerSheet(team: tm, info: we, loader: fakeLoader, slot: 5, kitTemplateZip: fakeZip));
    expect(tile().onTap, isNull); // no ROM
  });

  test('kitLabel and the default spec', () {
    expect(kitLabel(null), 'Default');
    expect(kitLabel({'pattern': 'sash', 'shirt': '#fff'}), 'Sash');
    expect(kitLabel({'template': 3}), 'Design 3');
    expect(kitLabel({'image': 'a.png'}), 'Custom PNG');
    final white = RosterTeam(teamRaw: {'id': 1, 'color': 'FFFFFF', 'alternate_color': '112233'}, players: [], statsRaw: {}, extraRaw: {});
    final home = defaultKitSpec(white, home: true);
    expect(home['shirt'], '#ffffff');
    expect(home['shorts'], '#112233'); // white shirt: shorts take the secondary
    expect(home['socks'], '#ffffff');
    final away = defaultKitSpec(white, home: false);
    expect(away['shirt'], '#112233');
    expect(away['shorts'], '#ffffff');
    expect(away['socks'], '#112233');
  });

  test('a missing alternate colour is the shirt\'s contrast, as in the library', () {
    RosterTeam t(String color) => RosterTeam(teamRaw: {'id': 1, 'color': color}, players: [], statsRaw: {}, extraRaw: {});
    expect(teamColours(t('102030')), ['#102030', '#ffffff']); // dark shirt: white
    expect(teamColours(t('FFFF00')), ['#ffff00', '#000000']); // light shirt: black
    expect(teamColours(t('')), ['#777777', '#ffffff']);
    final home = defaultKitSpec(t('FFFFFF'), home: true);
    expect(home['secondary'], '#000000');
    expect(home['shorts'], '#000000'); // white shirt, so the (contrast) secondary
    expect(defaultKitSpec(t('FFFFFF'), home: false)['shirt'], '#000000');
    expect(kitTemplatePath({'template': 2}, const [KitTemplate(index: 2, name: 'x', path: '/t/2.png')]), '/t/2.png');
    expect(kitTemplatePath({'template': 9}, const []), isNull);
    expect(kitTemplatePath({'pattern': 'plain'}, const []), isNull);
  });
}
