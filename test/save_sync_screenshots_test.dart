import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_screen.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';

import 'save_sync_support.dart';

/// Renders the Save Sync screen in its main states to PNGs under
/// `build/screenshots`, with the app's theme and fonts, at a handheld's
/// landscape size. Skipped unless `SCREENSHOTS=1`; the images are for
/// looking at the UI, not golden comparisons.
class _Shots extends SaveSyncNotifier {
  _Shots(SaveSyncState initial, this.lines) {
    state = initial;
  }

  final List<CheckLine> lines;

  @override
  Future<void> refresh() async {}

  @override
  Future<List<CheckLine>> check(String recipeId) async => lines;
}

void main() {
  final enabled = Platform.environment['SCREENSHOTS'] == '1';
  final stardew = bundledRecipe('stardew-valley');
  final seaOfStars = bundledRecipe('sea-of-stars');
  const binding = Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.androidData, root: 'files/Saves');
  const hubFolder = '/storage/emulated/0/Retro Toolbox Saves';

  GenMeta gen(String unit, String device, String name, DateTime at) => GenMeta(
        gen: '${utcStamp(at)}-$device-9f2c01e1',
        parents: const [],
        recipe: 'stardew-valley',
        unit: unit,
        device: device,
        deviceName: name,
        createdAt: at,
        package: stardewPkg,
        files: const {},
        payloadSha256: 'f' * 64,
      );

  final thorGen = gen('Pelican_418220311', 'ayn-thor-7f3a', 'AYN Thor', DateTime.utc(2026, 11, 11, 1, 41));
  final odinGen = gen('Willow_902113', 'ayn-odin-2-mini-02c4', 'AYN Odin 2 Mini', DateTime.utc(2026, 11, 10, 22, 5));

  const checkLines = [
    CheckLine(CheckLevel.ok, 'Recipe', 'Stardew Valley: verified recipe from bundled'),
    CheckLine(CheckLevel.ok, 'App', 'com.chucklefish.stardewvalley 1.6.15.2'),
    CheckLine(CheckLevel.ok, 'Access', 'Shizuku (shell)'),
    CheckLine(CheckLevel.ok, 'Save folder', '/storage/emulated/0/Android/data/com.chucklefish.stardewvalley/files/Saves'),
    CheckLine(CheckLevel.ok, 'Pelican_418220311', '2 file(s), checks pass'),
    CheckLine(CheckLevel.ok, 'Stays on this device', 'Pelican_418220311/Pelican_418220311_old, Pelican_418220311/SaveGameInfo_old, EMERGENCY_SAVE'),
    CheckLine(CheckLevel.ok, 'Hub Pelican_418220311', 'Newest 20261111T014100Z-ayn-thor-7f3a-9f2c01e1 by AYN Thor, intact'),
    CheckLine(CheckLevel.warn, 'Hub Willow_902113', 'Newest (20261110T220500Z-ayn-odin-2-mini-02c4-9f2c01e1): This save needs Stardew Valley 1.6.16 or newer; the installed one is 1.6.15.2'),
  ];

  Future<void> shoot(WidgetTester t, String name, SaveSyncState state, {Future<void> Function(WidgetTester t)? act}) async {
    await t.runAsync(() async {
      final chakra = FontLoader('ChakraPetch');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        chakra.addFont(File('assets/fonts/ChakraPetch-$w.ttf').readAsBytes().then((b) => b.buffer.asByteData()));
      }
      await chakra.load();
      final root = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter';
      final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (icons.existsSync()) await (FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then((b) => b.buffer.asByteData()))).load();
    });
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 720);
    addTearDown(t.view.reset);
    final boundary = GlobalKey();
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => _Shots(state, checkLines))],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: boundary, child: child!),
        home: const SaveSyncScreen(),
      ),
    ));
    await t.pumpAndSettle();
    if (act != null) {
      await act(t);
      await t.pumpAndSettle();
    }
    final render = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await t.runAsync(() => render.toImage(pixelRatio: 1.5));
    final bytes = await t.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('build/screenshots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  final ready = SaveSyncState(
    access: SyncAccess.shizuku,
    hubFolder: hubFolder,
    games: [
      GameStatus(stardew, 'bundled', const Bound(binding), installedVersion: '1.6.15.2', units: {
        'Pelican_418220311': UnitStatus(PullPlan('Pelican_418220311', thorGen, missingLocally: false), newest: thorGen),
        'Willow_902113': UnitStatus(const PushPlan('Willow_902113', []), newest: odinGen),
        'Cindersap_77031': const UnitStatus(UpToDate('Cindersap_77031')),
      }),
      GameStatus(
        seaOfStars,
        'bundled',
        const NeedsConfirm(
          Binding(recipe: 'sea-of-stars', package: 'com.playdigious.seaofstars', area: Area.androidData, root: 'files', mode: 'backup'),
          ['SOS_SaveSlot0.sos', 'SOS_SaveSlot1.sos'],
        ),
      ),
    ],
    messages: const ['Willow_902113: pushed'],
  );

  testWidgets('main list', (t) => shoot(t, 'save_sync_main', ready), skip: !enabled);

  testWidgets('check dialog', (t) => shoot(t, 'save_sync_check', ready, act: (t) => t.tap(find.widgetWithText(TextButton, 'Check').first)), skip: !enabled);

  testWidgets('confirm a draft location', (t) => shoot(t, 'save_sync_confirm', ready, act: (t) => t.tap(find.text('Confirm save location'))), skip: !enabled);

  testWidgets(
    'needs attention',
    (t) => shoot(
      t,
      'save_sync_attention',
      SaveSyncState(
        access: SyncAccess.shizuku,
        hubFolder: hubFolder,
        games: [
          GameStatus(
            stardew,
            'bundled',
            const Bound(binding),
            installedVersion: '1.6.15.2',
            running: true,
            notes: const ['Recovered an interrupted pull of Cindersap_77031'],
            units: {
              'Pelican_418220311': UnitStatus(Diverged('Pelican_418220311', [thorGen, odinGen], localDiffers: true), newest: thorGen),
              'Willow_902113': UnitStatus(const Blocked('Willow_902113', 'Stardew Valley is running'), newest: odinGen),
            },
          ),
        ],
      ),
    ),
    skip: !enabled,
  );

  testWidgets(
    'no access yet',
    (t) => shoot(t, 'save_sync_no_access', const SaveSyncState(shizukuRunning: true, hubFolder: hubFolder)),
    skip: !enabled,
  );
}
