import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_add_app_screen.dart';
import 'package:retro_toolbox/screens/save_sync_recipe_wizard_screen.dart';
import 'package:retro_toolbox/screens/save_sync_screen.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/services/save_sync/title_catalog.dart';

import '../save_sync_support.dart';
import 'support.dart';

/// Save Sync in its states: the list of games, a game's saves, the row
/// menu, no access, a Drive hub, nothing added yet, an error, a run in
/// flight, and Add an app and Describe an app. ONLY picks shots by name.
class _Shots extends SaveSyncNotifier {
  _Shots(SaveSyncState initial) {
    state = initial;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<List<CheckLine>> check(String recipeId) async => const [];

  @override
  Future<void> push(String recipeId, {String? unit}) async {
    state = state.copyWith(messages: [unit == null ? 'all: pushed' : '$unit: pushed']);
  }

  @override
  Future<List<({String package, AppInfo info})>> launchableApps() async => [
        for (final (pkg, name) in _apps) (package: pkg, info: AppInfo(name, _icons[pkg])),
      ];

  @override
  Future<({String root, List<({String name, bool isDir})> entries})?> probeSaveFolder(String package) async => (
        root: '/storage/emulated/0/Android/data/$package/files/Saves',
        entries: const [(name: 'slot_1.sav', isDir: false), (name: 'slot_2.sav', isDir: false), (name: 'settings.ini', isDir: false), (name: 'slot_1.bak', isDir: false)],
      );
}

const _only = String.fromEnvironment('ONLY');
bool _want(String name) => _only.isEmpty || _only.split(',').contains(name);

const _apps = [
  ('com.chucklefish.stardewvalley', 'Stardew Valley'),
  ('com.playdigious.seaofstars', 'Sea of Stars'),
  ('com.TeamCherry.HollowKnight', 'Hollow Knight'),
  ('com.SpanishFreddy.Cuphead', 'Cuphead'),
  ('com.BlackSaltGames.DREDGE', 'DREDGE'),
  ('dev.eden.eden_emulator', 'Eden'),
  ('com.example.celeste', 'Celeste'),
  ('com.example.balatro', 'Balatro'),
];

/// Launcher icons as Android hands them over: a PNG per app, a colour and
/// two letters, drawn once.
final _icons = <String, Uint8List>{};
const _colors = [Color(0xFF5D8A3A), Color(0xFF2D5AA8), Color(0xFF444A52), Color(0xFFB8862E), Color(0xFF1F6F78), Color(0xFFB03A2E), Color(0xFF7A4FA0), Color(0xFF9E3D64)];

Future<void> _drawIcons(WidgetTester t) async {
  if (_icons.isNotEmpty) return;
  await loadFonts(t);
  await t.runAsync(() async {
    for (final (i, (pkg, name)) in _apps.indexed) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 96, 96), const Radius.circular(20)), Paint()..color = _colors[i % _colors.length]);
      final tp = TextPainter(
        text: TextSpan(text: name.substring(0, 2).toUpperCase(), style: const TextStyle(fontFamily: 'Roboto', fontSize: 38, fontWeight: FontWeight.w700, color: Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset((96 - tp.width) / 2, (96 - tp.height) / 2));
      final img = await rec.endRecording().toImage(96, 96);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      _icons[pkg] = png!.buffer.asUint8List();
    }
  });
}

void main() {
  screenshotSetUp();

  final now = DateTime.now().toUtc();
  GenMeta gen(String recipe, String unit, String name, Duration ago) => GenMeta(
        gen: '${utcStamp(now.subtract(ago))}-${name.toLowerCase().replaceAll(' ', '-')}-9f2c01e1',
        parents: const [],
        recipe: recipe,
        unit: unit,
        device: name.toLowerCase().replaceAll(' ', '-'),
        deviceName: name,
        createdAt: now.subtract(ago),
        package: stardewPkg,
        files: const {'a': GenFile('b', 1)},
        payloadSha256: 'f' * 64,
      );
  Binding bind(String recipe, String pkg, String root) => Binding(recipe: recipe, package: pkg, area: Area.androidData, root: root);

  final thor = gen('stardew-valley', 'Pelican_418220311', 'AYN Thor', const Duration(hours: 2));
  final odin = gen('stardew-valley', 'Willow_902113', 'AYN Odin 2 Mini', const Duration(days: 1, hours: 3));
  final hk = gen('hollow-knight', 'all', 'AYN Thor', const Duration(hours: 5));
  final cup = gen('cuphead', 'all', 'Pixel 8', const Duration(minutes: 40));
  final edenA = gen('eden', '0100F2C0115B6000', 'AYN Thor', const Duration(hours: 1));

  List<GameStatus> mixed() => [
        GameStatus(bundledRecipe('stardew-valley'), 'bundled', Bound(bind('stardew-valley', stardewPkg, 'files/Saves')), installedVersion: '1.6.15.2', units: {
          'Pelican_418220311': UnitStatus(PullPlan('Pelican_418220311', thor, missingLocally: false), newest: thor),
          'Willow_902113': UnitStatus(const PushPlan('Willow_902113', []), newest: odin),
          'Cindersap_77031': UnitStatus(const UpToDate('Cindersap_77031'), newest: odin),
        }),
        GameStatus(
          bundledRecipe('sea-of-stars'),
          'bundled',
          NeedsConfirm(bind('sea-of-stars', 'com.playdigious.seaofstars', 'files'), const ['SOS_SaveSlot0.sos', 'SOS_SaveSlot1.sos']),
        ),
        GameStatus(bundledRecipe('hollow-knight'), 'bundled', Bound(bind('hollow-knight', 'com.TeamCherry.HollowKnight', 'files')), units: {
          'all': UnitStatus(const PushPlan('all', []), newest: hk),
        }),
        GameStatus(bundledRecipe('cuphead'), 'repo', Bound(bind('cuphead', 'com.SpanishFreddy.Cuphead', 'files/Cuphead')), units: {
          'all': UnitStatus(const UpToDate('all'), newest: cup),
        }),
        GameStatus(bundledRecipe('dredge'), 'bundled', Bound(bind('dredge', 'com.BlackSaltGames.DREDGE', 'files')), running: true, units: {
          'all': const UnitStatus(Blocked('all', 'DREDGE is running')),
        }),
        GameStatus(bundledRecipe('eden'), 'bundled', Bound(bind('eden', 'dev.eden.eden_emulator', 'files/nand/user/save/0000000000000000/ABC')), units: {
          '0100F2C0115B6000': UnitStatus(PullPlan('0100F2C0115B6000', edenA, missingLocally: false), newest: edenA),
          '01007EF00011E000': const UnitStatus(UpToDate('01007EF00011E000')),
        }),
        GameStatus(bundledRecipe('yuzu'), 'bundled', const NotInstalled()),
      ];

  SaveSyncState folder({List<GameStatus>? games, SyncAccess access = SyncAccess.shizuku, String? busy, String? error}) => SaveSyncState(
        access: access,
        hubKind: HubKind.folder,
        hubFolder: '/storage/emulated/0/Retro Toolbox Saves',
        games: games ?? mixed(),
        appInfo: {for (final (pkg, name) in _apps) pkg: AppInfo(name, _icons[pkg])},
        titles: const {
          '0100F2C0115B6000': TitleInfo('The Legend of Zelda: Tears of the Kingdom', null),
          '01007EF00011E000': TitleInfo('The Legend of Zelda: Breath of the Wild', null),
        },
        busyRecipe: busy,
        error: error,
      );

  Future<void> shot(WidgetTester t, String name, SaveSyncState Function() s, {Future<void> Function(WidgetTester t)? act, Widget? screen}) async {
    await _drawIcons(t);
    await launch(t, screen ?? const SaveSyncScreen(), overrides: [saveSyncProvider.overrideWith((ref) => _Shots(s()))]);
    await realWait(t, 300);
    if (act != null) await act(t);
    await snap(t, name);
  }

  // Android's key map: the Linux one has no game buttons.
  Future<void> press(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k, platform: 'android');
    await frames(t, 4);
  }

  Future<void> pad(WidgetTester t) => press(t, LogicalKeyboardKey.arrowDown);

  final shots = <String, Future<void> Function(WidgetTester)>{
    'savesync_folder': (t) => shot(t, 'savesync_folder', folder),
    'savesync_saves': (t) => shot(t, 'savesync_saves', folder, act: (t) async {
          await t.tap(find.text('Stardew Valley').first);
          await frames(t, 6);
        }),
    'savesync_menu': (t) => shot(t, 'savesync_menu', folder, act: (t) async {
          await t.longPress(find.text('Hollow Knight').first);
          await frames(t, 6);
        }),
    'savesync_noaccess': (t) => shot(t, 'savesync_noaccess', () => folder(access: SyncAccess.none)),
    'savesync_drive': (t) => shot(t, 'savesync_drive', () {
          final f = folder();
          return SaveSyncState(
            access: f.access,
            hubKind: HubKind.drive,
            googleEmail: 'player.one@gmail.com',
            googleAvailable: true,
            games: f.games,
            appInfo: f.appInfo,
            titles: f.titles,
          );
        }),
    'savesync_empty': (t) => shot(t, 'savesync_empty', () => folder(games: const [])),
    'savesync_error': (t) => shot(t, 'savesync_error', () {
          final games = mixed();
          games[2] = GameStatus(games[2].recipe, 'bundled', games[2].bind, error: 'The save folder changed while it was read; try again');
          return folder(games: games, error: 'Could not read the hub: the folder is not there any more');
        }),
    'savesync_working': (t) => shot(t, 'savesync_working', () => folder(busy: 'hollow-knight')),
    'savesync_result': (t) => shot(t, 'savesync_result', folder, act: (t) async {
          await t.tap(find.byTooltip('Upload').evaluate().isEmpty ? find.text('Upload').first : find.byTooltip('Upload').first);
          await frames(t, 4);
        }),
    'savesync_info': (t) => shot(t, 'savesync_info', folder, act: (t) async {
          await t.tap(find.byTooltip('About this screen'));
          await frames(t, 6);
        }),
    'savesync_pad': (t) => shot(t, 'savesync_pad', folder, act: pad),
    'savesync_pad_saves': (t) => shot(t, 'savesync_pad_saves', folder, act: (t) async {
          await press(t, LogicalKeyboardKey.arrowDown);
          await press(t, LogicalKeyboardKey.arrowUp);
          await press(t, LogicalKeyboardKey.gameButtonA);
          await frames(t, 6);
        }),
    'savesync_add_app': (t) => shot(
          t,
          'savesync_add_app',
          folder,
          screen: SaveSyncAddAppScreen(
            already: const {'com.chucklefish.stardewvalley', 'com.TeamCherry.HollowKnight'},
            known: const {'com.playdigious.seaofstars': 'sea-of-stars'},
            catalog: RecipeCatalog(const [
              IndexEntry(id: 'cuphead', packages: ['com.SpanishFreddy.Cuphead'], status: 'verified'),
              IndexEntry(id: 'dredge', packages: ['com.BlackSaltGames.DREDGE'], status: 'draft'),
            ], fetchedAt: DateTime.now().subtract(const Duration(hours: 3))),
          ),
          act: (t) async {
            await realWait(t, 300);
            await t.tap(find.text('Cuphead').first);
            await frames(t, 2);
          },
        ),
    'savesync_add_app_pad': (t) => shot(
          t,
          'savesync_add_app_pad',
          folder,
          screen: const SaveSyncAddAppScreen(already: {'com.chucklefish.stardewvalley'}),
          act: (t) async {
            await realWait(t, 300);
            await press(t, LogicalKeyboardKey.arrowDown);
            await press(t, LogicalKeyboardKey.arrowDown);
          },
        ),
    'savesync_describe_folder': (t) => shot(t, 'savesync_describe_folder', folder, screen: const SaveSyncRecipeWizardScreen(package: 'com.example.celeste', label: 'Celeste')),
    'savesync_describe_shape': (t) => shot(
          t,
          'savesync_describe_shape',
          folder,
          screen: const SaveSyncRecipeWizardScreen(package: 'com.example.celeste', label: 'Celeste'),
          act: (t) async {
            await press(t, LogicalKeyboardKey.gameButtonStart);
            await frames(t, 4);
          },
        ),
    'savesync_describe_travels': (t) => shot(
          t,
          'savesync_describe_travels',
          folder,
          screen: const SaveSyncRecipeWizardScreen(package: 'com.example.celeste', label: 'Celeste'),
          act: (t) async {
            await press(t, LogicalKeyboardKey.gameButtonStart);
            await press(t, LogicalKeyboardKey.gameButtonStart);
            await frames(t, 4);
          },
        ),
  };

  for (final MapEntry(key: name, value: run) in shots.entries) {
    testWidgets(name, run, skip: !screenshotsEnabled || !_want(name));
  }
}
