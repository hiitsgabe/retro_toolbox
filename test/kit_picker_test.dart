import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

  final requested = <({Map<String, dynamic> kits, Map<String, int>? slots, Map<String, String>? which, Map<String, List<String>>? colours, Map<String, dynamic>? home})>[];
  // What the worker resolves a null kit to, by side; empty: an older worker.
  var defaults = <String, Map<String, dynamic>>{};
  // Header previews get a path naming the choice, so a refresh is visible by key.
  Future<KitPreviews> fakeLoader(Map<String, dynamic> kits,
      {bool templates = false,
      Map<String, int>? slots,
      Map<String, String>? which,
      Map<String, List<String>>? colours,
      Map<String, Map<String, Object?>>? teams,
      Map<String, dynamic>? home}) async {
    requested.add((kits: kits, slots: slots, which: which, colours: colours, home: home));
    return (
      kits: {
        for (final k in kits.keys)
          if (k.startsWith('current_')) k: '/p/$k=${kitLabel(kits[k])}.png'
      },
      defaults: {
        for (final k in kits.keys)
          if (kits[k] == null && defaults[(which?[k] ?? 'home')] != null) k: defaults[which?[k] ?? 'home']!
      },
      templates: <KitTemplate>[],
    );
  }

  Iterable<Map<String, dynamic>> patternJobs() => requested.map((r) => r.kits).where((k) => k.length == 16);

  setUp(() {
    requested.clear();
    defaults = {};
  });

  // A tile is drawn picked with a thick border.
  bool picked(WidgetTester t, String label) => t
      .widgetList<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)))
      .any((c) => (c.decoration as BoxDecoration?)?.border?.top.width == 3);

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
    // The away kit learns the home choice: on ISS it wears the home kit's chest design.
    expect(first.home, {'away': null});
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
    final header = requested.lastWhere((r) => r.kits.containsKey('current_home'));
    expect(header.kits, {'current_home': null});
    expect(header.slots, {'current_home': 3});
    expect(header.which, {'current_home': 'home'});
    expect(header.colours, {
      'current_home': ['#c60000', '#000000']
    });
    // The grid's specs come with the colours too.
    expect(patternJobs().length, 1);
    expect(requested.firstWhere((r) => r.kits.length == 16).colours?['home_stripes'], ['#c60000', '#000000']);
    // The worker sent no default (an older one): the team's colours, plain.
    expect(picked(t, 'Plain'), isTrue);

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
    expect(requested.last.home?['away'], containsPair('pattern', 'stripes'));
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
        {bool templates = false,
        Map<String, int>? slots,
        Map<String, String>? which,
        Map<String, List<String>>? colours,
        Map<String, Map<String, Object?>>? teams,
        Map<String, dynamic>? home}) async {
      calls++;
      return (
        // No preview for a design; after the first call none for the away kit either.
        kits: {
          for (final e in kits.entries)
            if ((e.value is! Map || e.value['template'] == null) && !(e.key == 'away' && calls > 1)) e.key: '/p/${e.key}$calls.png',
        },
        defaults: const <String, Map<String, dynamic>>{},
        templates: templates ? const [KitTemplate(index: 44, name: 'Design 44', path: '/t/44.png')] : const <KitTemplate>[],
      );
    }

    final tm = team();
    await pump(t, editor(tm, game: we, loader: loader));
    expect(find.byKey(const ValueKey('/p/home1.png')), findsOneWidget);
    expect(find.byKey(const ValueKey('/p/away1.png')), findsOneWidget);

    await t.tap(find.text('Home kit'));
    await t.pumpAndSettle();
    await t.tap(find.text('Model'));
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
    // The team page has no download of its own: it moved to the picker's Custom tab.
    expect(find.text('Download kit template'), findsNothing);
    await t.tap(find.text('Change kits'));
    await t.pumpAndSettle();
    await t.tap(find.text('Custom'));
    await t.pumpAndSettle();
    final button = find.ancestor(of: find.text('Download kit template'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    await t.tap(button);
    await t.pump();
    expect(args, [('${dir.path}/we2002.bin', 3, 7)]);
    expect(t.widget<ButtonStyleButton>(button).onPressed, isNull); // in flight
    // The copy is real file IO, which only completes outside the fake async zone.
    await t.runAsync(() async {
      job.complete(zip.path);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(t.widget<ButtonStyleButton>(button).onPressed, isNotNull);
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
    expect(find.text('PES uses the picture for its colours and pattern only.'), findsNothing); // Custom tab only
    await t.tap(find.text('Custom'));
    await t.pumpAndSettle();
    expect(find.text('PES uses the picture for its colours and pattern only.'), findsOneWidget);
  });

  testWidgets('ISS 2000 takes colours only: no tabs, and a colour change redraws the preview', (t) async {
    const iss = PatcherInfo(gameId: 'iss2000-n64', platform: 'n64', sport: 'soccer', requiresSlotMapping: true, providers: ['espn'], supportsKits: true);
    final tm = team();
    await pump(t, KitPickerSheet(team: tm, info: iss, loader: fakeLoader, initialHome: false));
    expect(find.text('Pattern'), findsNothing);
    expect(find.text('Custom'), findsNothing);
    expect(find.text('Stripes'), findsNothing);
    expect(patternJobs(), isEmpty);
    await t.tap(find.text('Shorts'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect((tm.extraRaw['kits'] as Map)['away']['shorts'], '#c2185b');
    expect(find.byKey(const ValueKey('/p/current_away=Plain.png')), findsOneWidget);
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
    final button = find.ancestor(of: find.text('Download kit template'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    for (final (rom, slot, on) in [('/roms/pes.iso', 3, true), (null, 3, false), ('/roms/pes.iso', null, false)]) {
      await pump(t, KitPickerSheet(team: team(), info: info, loader: fakeLoader, romPath: rom, slot: slot));
      await t.tap(find.text('Custom'));
      await t.pumpAndSettle();
      expect(t.widget<ButtonStyleButton>(button).onPressed != null, on, reason: '$rom $slot');
    }
  });

  testWidgets('without a ROM the picker says where the game designs come from', (t) async {
    const we =
        PatcherInfo(gameId: 'we2002', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn'], supportsKits: true, kitTemplates: true);
    await pump(t, KitPickerSheet(team: team(), info: we, loader: fakeLoader));
    await t.tap(find.text('Model'));
    await t.pumpAndSettle();
    expect(find.text('Pick the ROM first to see the game\'s own designs.'), findsOneWidget);
    // With the ROM but no designs exported (yet): no Model tab at all.
    await pump(t, KitPickerSheet(team: team(), info: we, loader: fakeLoader, romPath: '/roms/we.bin'));
    expect(find.text('Model'), findsNothing);
    expect(find.textContaining('Pick the ROM first'), findsNothing);
    // A game without designs (ISS, PES here) has Pattern and Custom only.
    await pump(t, KitPickerSheet(team: team(), info: info, loader: fakeLoader, romPath: '/roms/pes.iso'));
    expect(find.text('Pattern'), findsOneWidget);
    expect(find.text('Model'), findsNothing);
    expect(find.text('Custom'), findsOneWidget);
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
    ButtonStyleButton link() =>
        t.widget<ButtonStyleButton>(find.ancestor(of: find.text('Download kit template'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);
    Future<void> custom() async {
      await t.tap(find.text('Custom'));
      await t.pumpAndSettle();
    }

    await pump(t, KitPickerSheet(team: tm, info: we, loader: fakeLoader, romPath: '/roms/we.bin', slot: 5, kitTemplateZip: fakeZip));
    // Your PNG and the template only show on the Custom tab.
    expect(find.text('Download kit template'), findsNothing);
    expect(find.text('Choose…'), findsNothing);
    await custom();
    expect(find.text('Download kit template'), findsOneWidget);
    expect(find.text('Choose…'), findsOneWidget);
    expect(link().onPressed, isNotNull);
    await t.tap(find.text('Download kit template'));
    await t.pumpAndSettle();
    expect(args, [('we2002', '/roms/we.bin', 5, 7)]); // the home kit's design
    expect(find.text('Kit template: Bad state: no worker'), findsOneWidget);
    expect(link().onPressed, isNotNull); // re-enabled after the job

    // The away kit is a plain default: no design goes with it.
    await t.tap(find.text('Away'));
    await t.pumpAndSettle();
    await custom(); // the tab is per side
    await t.tap(find.text('Download kit template'));
    await t.pumpAndSettle();
    expect(args.last, ('we2002', '/roms/we.bin', 5, null));

    await pump(t, KitPickerSheet(team: tm, info: we, loader: fakeLoader, slot: 5, kitTemplateZip: fakeZip));
    await custom();
    expect(link().onPressed, isNull); // no ROM
  });

  testWidgets('the game designs come one group and one page at a time', (t) async {
    const we = PatcherInfo(
      gameId: 'we2002',
      platform: 'psx',
      sport: 'soccer',
      requiresSlotMapping: true,
      providers: ['espn'],
      supportsKits: true,
      kitTemplates: true,
    );
    final designs = [for (var i = 0; i < 95; i++) KitTemplate(index: i, name: 'Team $i (red)', path: '/t/$i.png')];
    final tm = team();
    tm.extraRaw['kits'] = {
      'home': {'template': 70},
      'away': null
    };
    await pump(t, KitPickerSheet(team: tm, info: we, templates: designs, loader: fakeLoader, romPath: '/roms/we.bin', slot: 0));

    // Three groups; the sheet opens on the chosen design's group and page.
    expect(find.text('Nations (54)'), findsOneWidget);
    expect(find.text('Classics (9)'), findsOneWidget);
    expect(find.text('Master League (32)'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget); // Master League: 63..70 on page 1
    expect(find.text('Team 70'), findsOneWidget); // the bracketed note is dropped
    expect(find.text('Team 71'), findsNothing);

    await t.tap(find.byTooltip('More designs'));
    await t.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('Team 71'), findsOneWidget);
    expect(find.text('Team 70'), findsNothing);

    await t.tap(find.text('Nations (54)'));
    await t.pumpAndSettle();
    expect(find.text('1 / 7'), findsOneWidget);
    expect(find.text('Team 0'), findsOneWidget);
    expect(find.text('Team 8'), findsNothing);
    expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left)).onPressed, isNull);

    await t.tap(find.text('Team 3'));
    await t.pumpAndSettle();
    expect(tm.extraRaw['kits']['home'], {'template': 3});
  });

  // Galo's catalogue kits, as the worker resolves its default.
  const black = {'shirt': '#040404', 'secondary': '#fcfcfc', 'pattern': 'stripes', 'shorts': '#040404', 'socks': '#000000', 'sleeves': null};
  const white = {'shirt': '#fcfcfc', 'secondary': '#000000', 'pattern': 'plain', 'shorts': '#fcfcfc', 'socks': '#ffffff', 'sleeves': null};
  const we =
      PatcherInfo(gameId: 'we2002', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn'], supportsKits: true, kitTemplates: true);

  // The label of the control holding focus; null when only a scope holds it.
  String? focused() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode) return null;
    final texts = find.descendant(of: find.byElementPredicate((e) => e == node.context), matching: find.byType(Text)).evaluate();
    return texts.isEmpty ? null : (texts.first.widget as Text).data;
  }

  testWidgets('focus starts only on the picked tile, never on a design nobody chose (mouse: the outline shows)', (t) async {
    defaults = {'home': black, 'away': white};
    const designs = [KitTemplate(index: 44, name: 'Paraguay', path: '/t/44.png'), KitTemplate(index: 45, name: 'Peru', path: '/t/45.png')];
    final tm = team();
    Widget sheet() => KitPickerSheet(team: tm, info: we, templates: designs, loader: fakeLoader, romPath: '/roms/we.bin', slot: 0);

    await pump(t, sheet());
    // The default reads as Stripes: focus is there, not on Plain.
    expect(focused(), 'Stripes');
    expect(picked(t, 'Stripes'), isTrue);

    // A key press sets the traditional highlight mode (a desktop's), where
    // DpadScope draws the outline, and a mouse keeps it. On the Model tab by
    // mouse, the designs show and none takes focus.
    await t.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(find.text('Model'), kind: PointerDeviceKind.mouse);
    await t.pumpAndSettle();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    expect(find.text('Paraguay'), findsOneWidget);
    expect(focused(), isNull);
    expect(kitChoice(tm, home: true), isNull);

    // Back to Pattern, then the other side by mouse: focus follows to that
    // side's picked tile instead of staying on this side's Stripes.
    await t.tap(find.text('Pattern'), kind: PointerDeviceKind.mouse);
    await t.pumpAndSettle();
    expect(focused(), 'Stripes');
    await t.tap(find.text('Away'), kind: PointerDeviceKind.mouse);
    await t.pumpAndSettle();
    expect(focused(), 'Plain');
    expect(picked(t, 'Plain'), isTrue);

    // A side wearing a design opens with focus on that design.
    setKitChoice(tm, home: true, kit: {'template': 45});
    await pump(t, sheet());
    expect(focused(), 'Peru');
    expect(picked(t, 'Peru'), isTrue);
  });

  testWidgets('the patterns and colours wait for the default, so a pick never keeps the fallback colours', (t) async {
    defaults = {'home': black, 'away': white};
    final answer = Completer<void>();
    Future<KitPreviews> slow(Map<String, dynamic> kits,
        {bool templates = false,
        Map<String, int>? slots,
        Map<String, String>? which,
        Map<String, List<String>>? colours,
        Map<String, Map<String, Object?>>? teams,
        Map<String, dynamic>? home}) async {
      if (kits.length == 2) await answer.future; // the defaults job
      return fakeLoader(kits, templates: templates, slots: slots, which: which, colours: colours, teams: teams, home: home);
    }

    final tm = team();
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1000, 1400);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: KitPickerSheet(team: tm, info: info, loader: slow)));
    await t.pump();
    await t.tap(find.text('Hoops'));
    await t.pump();
    expect(kitChoice(tm, home: true), isNull);
    expect(picked(t, 'Plain'), isFalse); // nothing reads as the default yet
    expect(t.widget<ListTile>(find.widgetWithText(ListTile, 'Shirt')).enabled, isFalse);

    answer.complete();
    await t.pumpAndSettle();
    expect(picked(t, 'Stripes'), isTrue);
    expect(t.widget<ListTile>(find.widgetWithText(ListTile, 'Shirt')).enabled, isTrue);
    await t.tap(find.text('Hoops'));
    await t.pumpAndSettle();
    expect(kitChoice(tm, home: true), {...black, 'pattern': 'hoops'});
  });

  testWidgets('a club kit\'s own sleeve colour shows as a row that clears it', (t) async {
    // São Paulo's away kit: red and black stripes, black sleeves.
    const sp = {'shirt': '#ff0000', 'secondary': '#000000', 'pattern': 'stripes', 'shorts': '#000000', 'socks': '#000000', 'sleeves': '#000000'};
    defaults = {'home': black, 'away': sp};
    final tm = team();
    await pump(t, KitPickerSheet(team: tm, info: info, loader: fakeLoader));
    expect(find.text('Sleeves'), findsOneWidget); // the pattern tile
    expect(find.widgetWithText(ListTile, 'Sleeves'), findsNothing); // the home kit has none

    await t.tap(find.text('Away'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Sleeves'), findsOneWidget);
    expect(patternJobs().single['away_plain'], {...sp, 'pattern': 'plain'});
    await t.tap(find.byTooltip('Sleeves in the shirt colour'));
    await t.pumpAndSettle();
    expect(kitChoice(tm, home: false), {...sp, 'sleeves': null});
    expect(find.widgetWithText(ListTile, 'Sleeves'), findsNothing);
    expect(patternJobs().last['away_plain'], {...sp, 'pattern': 'plain', 'sleeves': null});
  });

  testWidgets('the default is the kit the worker resolves: a striped club kit reads as Stripes, in its colours', (t) async {
    defaults = {'home': black, 'away': white};
    final tm = team();
    Color? swatch(String label) => ((t.widget<ListTile>(find.widgetWithText(ListTile, label)).leading as Container).decoration as BoxDecoration).color;

    await pump(t, KitPickerSheet(team: tm, info: info, loader: fakeLoader));
    // One job asks both sides' default; the patterns wait for it.
    expect(requested.first.kits, {'home': null, 'away': null});
    expect(requested.first.which, {'home': 'home', 'away': 'away'});
    expect(requested.first.colours?['away'], ['#c60000', '#000000']);
    expect(picked(t, 'Stripes'), isTrue);
    expect(picked(t, 'Plain'), isFalse);
    expect(swatch('Shirt'), const Color(0xff040404));
    // Every pattern is drawn in the default's colours, each side its own.
    final grid = patternJobs().single;
    expect(grid['home_hoops'], {...black, 'pattern': 'hoops'});
    expect(grid['away_sash'], {...white, 'pattern': 'sash'});

    await t.tap(find.text('Away'));
    await t.pumpAndSettle();
    expect(picked(t, 'Plain'), isTrue);
    expect(swatch('Shirt'), const Color(0xfffcfcfc));

    // A colour change makes a spec of the default; Back to default restores
    // its colours and re-renders the patterns in them.
    await t.tap(find.text('Shorts'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(kitChoice(tm, home: false), {...white, 'shorts': '#c2185b'});
    expect(patternJobs().length, 2);
    await t.tap(find.text('Back to default'));
    await t.pumpAndSettle();
    expect(kitChoice(tm, home: false), isNull);
    expect(swatch('Shorts'), const Color(0xfffcfcfc));
    expect(patternJobs().last['away_plain'], white);
    expect(picked(t, 'Plain'), isTrue);
  });

  testWidgets('three tabs: the designs have their own, only the chosen one looks picked, and a tab is only a view', (t) async {
    const designs = [KitTemplate(index: 44, name: 'Paraguay (red stripes)', path: '/t/44.png'), KitTemplate(index: 45, name: 'Peru', path: '/t/45.png')];
    KitTab tab() => t.widget<SegmentedButton<KitTab>>(find.byType(SegmentedButton<KitTab>)).selected.single;
    final tm = team();
    Widget sheet() => KitPickerSheet(team: tm, info: we, templates: designs, loader: fakeLoader, romPath: '/roms/we.bin', slot: 0);

    await pump(t, sheet());
    // Pattern: the generated patterns and the colours; no design, no PNG.
    expect(tab(), KitTab.pattern);
    expect(find.text('Plain'), findsOneWidget);
    expect(find.text('Shirt'), findsOneWidget);
    expect(find.text('Paraguay'), findsNothing);
    expect(find.text('Choose…'), findsNothing);

    // Model, from the d-pad (up from the autofocused Plain to the tabs, right,
    // A): the designs replace them, none picked, the choice stays the default.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(tab(), KitTab.model);
    expect(find.text('Plain'), findsNothing);
    expect(find.text('Shirt'), findsNothing);
    expect(find.text('Paraguay'), findsOneWidget);
    expect(picked(t, 'Paraguay') || picked(t, 'Peru'), isFalse);
    expect(kitChoice(tm, home: true), isNull);

    // Down lands on the designs; Left to the first, Enter picks it.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(kitChoice(tm, home: true), {'template': 44});
    expect(picked(t, 'Paraguay'), isTrue);
    expect(picked(t, 'Peru'), isFalse);

    // The tab is per side: the away kit wears no design.
    await t.tap(find.text('Away'));
    await t.pumpAndSettle();
    expect(tab(), KitTab.pattern);
    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    expect(tab(), KitTab.model);

    // Another tab only shows other choices: the design is still the kit.
    await t.tap(find.text('Pattern'));
    await t.pumpAndSettle();
    expect(kitChoice(tm, home: true), {'template': 44});
    expect(picked(t, 'Plain'), isFalse);
    await t.tap(find.text('Custom'));
    await t.pumpAndSettle();
    expect(find.text('Choose…'), findsOneWidget);
    expect(find.text('Download kit template'), findsOneWidget);

    // A side wearing a design opens on Model with that design picked; one
    // wearing a PNG opens on Custom.
    setKitChoice(tm, home: true, kit: {'template': 45});
    await pump(t, sheet());
    expect(tab(), KitTab.model);
    expect(picked(t, 'Peru'), isTrue);
    expect(picked(t, 'Paraguay'), isFalse);
    setKitChoice(tm, home: true, kit: {'image': '/k/mine.png'});
    await pump(t, sheet());
    expect(tab(), KitTab.custom);
    expect(picked(t, 'Custom PNG'), isTrue);
  });

  testWidgets('the team page shows both kits side by side, and Change kits opens the picker', (t) async {
    final tm = team();
    await pump(t, editor(tm));
    final home = t.getCenter(find.text('Home kit')), away = t.getCenter(find.text('Away kit'));
    expect(home.dy, away.dy); // one row
    expect(home.dx, lessThan(away.dx));
    expect(t.getCenter(find.text('Change kits')).dx, greaterThan(away.dx));

    // D-pad: from the home kit, Right to the away kit, Right to Change kits, A.
    Focus.of(t.element(find.text('Home kit'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(KitPickerSheet), findsOneWidget);
    expect(t.widget<KitPickerSheet>(find.byType(KitPickerSheet)).initialHome, isTrue);
  });

  test('designGroups and designLabel', () {
    final two = [const KitTemplate(index: 1, name: 'A', path: ''), const KitTemplate(index: 9, name: 'B', path: '')];
    expect(designGroups('pes2013-ps2', two).map((g) => g.name), ['All']);
    expect(designGroups('we2002', two).map((g) => g.name), ['Nations']);
    expect(designGroups('we2002', const []), isEmpty);
    expect(designLabel(const KitTemplate(index: 4, name: 'Peru (white, red sash)', path: '')), 'Peru');
    expect(designLabel(const KitTemplate(index: 4, name: '', path: '')), 'Design 4');
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
