import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';
import 'package:retro_toolbox/services/sports_service.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders the wizard's Teams and Look steps and the team editor with its
/// Kits section to PNGs under `build/screenshots` with the app's theme and
/// fonts. Skipped unless
/// `SCREENSHOTS=1`, so the normal run does not write files; the images are for
/// eyeballing the UI without the Python worker, not golden comparisons.
/// `SCREENSHOT_IMAGES` names a folder of `<slot>.png` previews for the Look
/// step's cards and a `kit.png` for every kit thumbnail.
void main() {
  final enabled = Platform.environment['SCREENSHOTS'] == '1';
  final previews = Platform.environment['SCREENSHOT_IMAGES'] ?? '';

  const info = PatcherInfo(
    gameId: 'we2002',
    platform: 'psx',
    sport: 'soccer',
    requiresSlotMapping: true,
    providers: ['espn'],
    languages: ['en', 'es', 'fr', 'pt'],
    supportsLogos: true,
    supportsBlankUnused: true,
    imageSlots: ['title', 'menu', 'boot'],
    supportsKits: true,
    kitTemplates: true,
  );

  RosterDoc doc() => RosterDoc(
        leagueRaw: {'name': 'Brasileirão Série A', 'season': 2026},
        teams: [
          for (final (i, n) in ['Flamengo', 'Palmeiras', 'Grêmio', 'Corinthians'].indexed)
            RosterTeam(
              teamRaw: {'id': i + 1, 'name': n, 'color': 'C3161C', 'alternate_color': '000000'},
              // Negative ids: no ESPN headshot lookups (network, sqflite) in the editor shot.
              players: [
                for (var k = 0; k < 23; k++) RosterPlayer(raw: {'id': -(k + 1), 'name': 'Player $k'})
              ],
              statsRaw: {},
              extraRaw: {},
            ),
        ],
      );

  /// The app's display font and the Material icons, which the test binding
  /// otherwise replaces with the Ahem box font.
  Future<void> loadFonts() async {
    final chakra = FontLoader('ChakraPetch');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      chakra.addFont(File('assets/fonts/ChakraPetch-$w.ttf').readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await chakra.load();
    final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then((b) => b.buffer.asByteData()));
      await loader.load();
    }
  }

  /// Every kit thumbnail shows `<key>.png` from the previews folder when it
  /// is there (real renders from the worker), else `kit.png`, if any.
  Future<KitPreviews> kitPreviews(Map<String, dynamic> kits,
      {bool templates = false,
      Map<String, int>? slots,
      Map<String, String>? which,
      Map<String, List<String>>? colours,
      Map<String, Map<String, Object?>>? teams,
      Map<String, dynamic>? home}) async {
    final generic = File('$previews/kit.png');
    final out = <String, String>{};
    for (final k in kits.keys) {
      final own = File('$previews/$k.png');
      if (own.existsSync()) {
        out[k] = own.path;
      } else if (generic.existsSync()) {
        out[k] = generic.path;
      }
    }
    return (kits: out, defaults: <String, Map<String, dynamic>>{}, templates: <KitTemplate>[]);
  }

  Future<void> shoot(WidgetTester t, String name, Widget Function(Map<String, String> images) page,
      {Future<void> Function(WidgetTester t)? act, Size size = const Size(1000, 1180)}) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('shots');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    await t.runAsync(loadFonts);
    t.view.devicePixelRatio = 1;
    // Tall enough for the whole Look step without scrolling.
    t.view.physicalSize = size;
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    final images = <String, String>{};
    if (previews.isNotEmpty) {
      for (final slot in info.imageSlots) {
        final f = File('$previews/$slot.png');
        if (f.existsSync()) images[slot] = f.path;
      }
    }
    final boundaryKey = GlobalKey();
    // Pumped inside runAsync so the preview PNGs really decode (image codecs
    // need a real event loop, which the fake async zone does not give them).
    await t.runAsync(() async {
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          navigatorKey: key,
          theme: appTheme(),
          builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
          home: RepaintBoundary(key: boundaryKey, child: page(images)),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await t.pump();
      if (act != null) {
        await act(t);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await t.pump();
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await t.pump();
    });
    await t.pumpAndSettle();
    final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await t.runAsync(() => boundary.toImage(pixelRatio: 2));
    final bytes = await t.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    final out = File('build/screenshots/$name.png')..createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  Widget wizard(int step, Map<String, String> images) => SportPatcherWizardScreen(
        info: info,
        initialDoc: doc(),
        initialStep: step,
        initialImages: images.isEmpty ? null : images,
      );

  /// The game's designs for the picker shot: `template_<n>.png` files from
  /// the previews folder, named after the WE2002 jersey templates.
  List<KitTemplate> designs() {
    // All of them when the folder lists them (`templates.json`, [{index, name}]).
    final listed = File('$previews/templates.json');
    if (listed.existsSync()) {
      return [
        for (final t in (jsonDecode(listed.readAsStringSync()) as List).cast<Map<String, dynamic>>())
          if (File('$previews/template_${t['index']}.png').existsSync())
            KitTemplate(index: t['index'] as int, name: '${t['name']}', path: '$previews/template_${t['index']}.png'),
      ];
    }
    const names = {3: 'England', 22: 'Croatia', 41: 'Brazil', 42: 'Peru', 44: 'Paraguay', 46: 'Argentina', 62: 'Clas. Argentina', 82: 'Piemonte'};
    return [
      for (final e in names.entries)
        if (File('$previews/template_${e.key}.png').existsSync()) KitTemplate(index: e.key, name: e.value, path: '$previews/template_${e.key}.png'),
    ];
  }

  const pesInfo = PatcherInfo(
    gameId: 'pes2013-ps2',
    platform: 'ps2',
    sport: 'soccer',
    requiresSlotMapping: true,
    providers: ['espn'],
    supportsLogos: true,
    supportsBlankUnused: true,
    imageSlots: ['title', 'menu', 'loading', 'match'],
    supportsKits: true,
    supportsNationals: true,
    nationalSlotBase: 1000,
    slotGroups: [
      SlotGroup('England', 0, 20),
      SlotGroup('France', 20, 20),
      SlotGroup('Italy', 40, 20),
      SlotGroup('Netherlands', 60, 18),
      SlotGroup('Spain', 78, 20),
      SlotGroup('Other', 98, 41),
    ],
    maxLeagues: 5,
  );

  const leagues = [
    League(id: 2006, name: 'Brasileirão Série A', country: 'Brazil'),
    League(id: 2001, name: 'Premier League', country: 'England'),
    League(id: 2002, name: 'La Liga', country: 'Spain'),
    League(id: 2004, name: 'Serie A', country: 'Italy'),
    League(id: 2013, name: 'Eredivisie', country: 'Netherlands'),
    League(id: 2005, name: 'Ligue 1', country: 'France'),
    League(id: 2003, name: 'Bundesliga', country: 'Germany'),
  ];

  // Steps: 0 ROM, 1 Rosters, 2 Teams, 3 Look, 4 Patch.
  testWidgets('teams step', (t) => shoot(t, 'wizard_teams', (i) => wizard(2, i)), skip: !enabled);

  // Every step of both soccer games, for a tour of the wizard.
  RosterDoc league(String name, List<String> clubs, int firstId) => RosterDoc(
        leagueRaw: {'name': name, 'season': 2026},
        teams: [
          for (final (i, n) in clubs.indexed)
            RosterTeam(
              teamRaw: {'id': firstId + i, 'name': n, 'color': 'C3161C', 'alternate_color': '000000'},
              players: [
                for (var k = 0; k < 23; k++) RosterPlayer(raw: {'id': -(k + 1), 'name': 'Player $k'})
              ],
              statsRaw: {},
              extraRaw: {},
            ),
        ],
      );
  Map<String, String> pesImages() => {
        for (final slot in pesInfo.imageSlots)
          if (File('$previews/pes/$slot.png').existsSync()) slot: '$previews/pes/$slot.png',
      };
  const stepNames = ['rom', 'rosters', 'teams', 'look', 'patch'];
  for (final (n, name) in stepNames.indexed) {
    testWidgets(
      'tour: WE2002 $name',
      (t) => shoot(
        t,
        'tour_we2002_${n}_$name',
        (i) => SportPatcherWizardScreen(
          info: info,
          initialDoc: n >= 2 ? doc() : null,
          initialStep: n,
          initialRomPath: '/roms/World Soccer Winning Eleven 2002 (Japan).cue',
          initialLeagues: leagues,
          initialImages: i.isEmpty ? null : i,
        ),
      ),
      skip: !enabled,
    );
    testWidgets(
      'tour: PES 2013 $name',
      (t) => shoot(
        t,
        'tour_pes2013_${n}_$name',
        (_) => SportPatcherWizardScreen(
          info: pesInfo,
          initialDocs: n >= 2
              ? [
                  league('Brasileirão Série A', ['Flamengo', 'Palmeiras', 'Grêmio', 'Corinthians'], 1),
                  league('Premier League', ['Arsenal', 'Liverpool', 'Chelsea'], 101),
                ]
              : null,
          initialStep: n,
          initialRomPath: '/roms/PES 2013 (USA).iso',
          initialLeagues: leagues,
          initialImages: pesImages().isEmpty ? null : pesImages(),
        ),
        act: n == 1
            ? (t) async {
                for (final l in ['Brasileirão Série A', 'Premier League']) {
                  await t.tap(find.textContaining(l).first);
                  await t.pump();
                }
                await t.tap(find.textContaining('National teams').first);
                await t.pump();
              }
            : null,
      ),
      skip: !enabled,
    );
  }
  testWidgets(
    'tour: PES 2013 team editor',
    (t) => shoot(
      t,
      'tour_pes2013_5_team',
      (_) => TeamEditorScreen(
        team: league('Brasileirão Série A', ['Flamengo'], 1).teams.first,
        gameId: pesInfo.gameId,
        sport: pesInfo.sport,
        info: pesInfo,
        romPath: '/roms/PES 2013 (USA).iso',
        slot: 0,
        kitLoader: kitPreviews,
      ),
    ),
    skip: !enabled,
  );
  testWidgets('look step', (t) => shoot(t, 'wizard_look', (i) => wizard(3, i)), skip: !enabled);
  testWidgets(
    'team editor with kits',
    (t) => shoot(
      t,
      'wizard_kits',
      (_) => TeamEditorScreen(
        team: doc().teams.first,
        gameId: info.gameId,
        sport: info.sport,
        info: info,
        romPath: '/roms/we2002.bin',
        slot: 0,
        kitLoader: kitPreviews,
      ),
    ),
    skip: !enabled,
  );
  testWidgets(
    'kit picker',
    (t) => shoot(
      t,
      'kit_picker',
      (_) => KitPickerSheet(
        team: doc().teams.first,
        info: info,
        templates: designs(),
        loader: kitPreviews,
        romPath: '/roms/we2002.bin',
        slot: 0,
        initialHome: true,
      ),
    ),
    skip: !enabled,
  );
  testWidgets(
    'kit picker, every design',
    (t) => shoot(
      t,
      'kit_picker_all',
      (_) => KitPickerSheet(
        team: doc().teams.first,
        info: info,
        templates: designs(),
        loader: kitPreviews,
        romPath: '/roms/we2002.bin',
        slot: 0,
        initialHome: true,
      ),
      act: (t) => t.tap(find.text('Use a model from the game')),
      size: const Size(1000, 3000),
    ),
    skip: !enabled,
  );
  testWidgets(
    'pes rosters step with several leagues',
    (t) => shoot(
      t,
      'wizard_pes_leagues',
      (_) => SportPatcherWizardScreen(
        info: pesInfo,
        initialStep: 1,
        initialRomPath: '/roms/pes2013.iso',
        initialLeagues: leagues,
      ),
      act: (t) async {
        for (final name in ['Brasileirão Série A', 'Premier League', 'La Liga']) {
          await t.tap(find.textContaining(name).first);
          await t.pump();
        }
        await t.tap(find.textContaining('National teams').first);
        await t.pump();
      },
    ),
    skip: !enabled,
  );
}
