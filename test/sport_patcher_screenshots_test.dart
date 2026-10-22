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
              teamRaw: {'id': i + 1, 'name': n},
              // Negative ids: no ESPN headshot lookups (network, sqflite) in the editor shot.
              players: [for (var k = 0; k < 23; k++) RosterPlayer(raw: {'id': -(k + 1), 'name': 'Player $k'})],
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

  /// Every kit thumbnail shows `kit.png` from the previews folder, if any.
  Future<KitPreviews> kitPreviews(Map<String, dynamic> kits,
      {bool templates = false, Map<String, int>? slots, Map<String, String>? which, Map<String, List<String>>? colours}) async {
    final f = File('$previews/kit.png');
    return (kits: {if (f.existsSync()) for (final k in kits.keys) k: f.path}, templates: <KitTemplate>[]);
  }

  Future<void> shoot(WidgetTester t, String name, Widget Function(Map<String, String> images) page) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('shots');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    await t.runAsync(loadFonts);
    t.view.devicePixelRatio = 1;
    // Tall enough for the whole Look step without scrolling.
    t.view.physicalSize = const Size(1000, 1180);
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

  // Steps: 0 ROM, 1 Rosters, 2 Teams, 3 Look, 4 Patch.
  testWidgets('teams step', (t) => shoot(t, 'wizard_teams', (i) => wizard(2, i)), skip: !enabled);
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
}
