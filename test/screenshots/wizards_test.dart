import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_setup_screen.dart';
import 'package:retro_toolbox/screens/setup_wizard_screen.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';

import '../save_sync_support.dart';
import 'fake_picker.dart';
import 'fakes.dart';
import 'support.dart';

/// Every step of the three wizards on WizardShell (Games Library setup, Save
/// Sync setup, the Sports patcher), their error states, and a pad variant
/// of each. ONLY picks shots by name.
class _SaveSync extends SaveSyncNotifier {
  _SaveSync(SaveSyncState initial) {
    state = initial;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<List<CheckLine>> check(String recipeId) async => const [];
}

const _only = String.fromEnvironment('ONLY');
bool _want(String name) => _only.isEmpty || _only.split(',').contains(name);

const _patcher = PatcherInfo(
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

const _leagues = [League(id: 1, name: 'Brasileirao Serie A', country: 'Brazil'), League(id: 2, name: 'Premier League', country: 'England')];
const _rom = '/storage/emulated/0/ROMs/psx/Winning Eleven 2002 (Japan).bin';

RosterDoc _doc() => RosterDoc(
      leagueRaw: {'name': 'Brasileirao Serie A', 'season': 2026},
      teams: [
        for (final (i, n) in ['Flamengo', 'Palmeiras', 'Gremio', 'Corinthians', 'Sao Paulo', 'Santos', 'Fluminense', 'Botafogo'].indexed)
          RosterTeam(
            teamRaw: {'id': i + 1, 'name': n, 'color': 'C3161C', 'alternate_color': '000000'},
            // Negative ids: no headshot lookups (network, sqflite).
            players: [
              for (var k = 0; k < 23; k++) RosterPlayer(raw: {'id': -(k + 1), 'name': 'Player $k'})
            ],
            statsRaw: {},
            extraRaw: {},
          ),
      ],
    );

/// The shipped consoles plus two that need a login: one on the Internet
/// Archive, one with its own sign-in form.
final _withLogins = [
  ...consoles,
  const Console(id: 'ps3', name: 'PlayStation 3', urls: ['https://archive.org/download/ps3-games']),
  const Console(id: 'vita', name: 'PS Vita', urls: ['https://example.invalid/vita'], auth: {
    'signin': {
      'params': ['username', 'password'],
    },
  }),
];

void main() {
  screenshotSetUp();
  late FakePicker picker;
  setUp(() => FilePicker.platform = picker = FakePicker());

  // Android's key map: the Linux one has no game buttons.
  Future<void> press(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k, platform: 'android');
    await frames(t, 4);
  }

  Future<void> setup(WidgetTester t, String name, {int step = 0, List<Console>? catalog, Future<void> Function(WidgetTester t)? act}) async {
    final list = catalog ?? consoles;
    final c = await launch(t, SetupWizardScreen(initialStep: step), overrides: [
      appStateProvider.overrideWith((ref) => FakeApp(AppState(consoles: {for (final c in list) c.id: c}, selectedConsole: list.firstOrNull))),
    ]);
    await realWait(t, 300);
    launchboxLoaded(c);
    await frames(t, 2);
    if (act != null) await act(t);
    await snap(t, name);
  }

  Future<void> saveSync(WidgetTester t, String name, SaveSyncState s, {Future<void> Function(WidgetTester t)? act}) async {
    await launch(t, SaveSyncSetupScreen(pickFolder: (_, __) async => null), overrides: [saveSyncProvider.overrideWith((ref) => _SaveSync(s))]);
    await realWait(t, 300);
    if (act != null) await act(t);
    await snap(t, name);
  }

  Future<void> patcher(WidgetTester t, String name, Widget screen, {Future<void> Function(WidgetTester t)? act, int wait = 600}) async {
    await launch(t, screen, overrides: consolesOverrides());
    await realWait(t, wait);
    if (act != null) await act(t);
    await snap(t, name);
  }

  final stardew = bundledRecipe('stardew-valley');
  const binding = Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.androidData, root: 'files/Saves');
  final hub = SaveSyncState(
    access: SyncAccess.shizuku,
    hubKind: HubKind.folder,
    hubFolder: '/storage/emulated/0/Retro Toolbox Saves',
    games: [
      GameStatus(stardew, 'bundled', const Bound(binding)),
      GameStatus(bundledRecipe('hollow-knight'), 'bundled', const Bound(Binding(recipe: 'hollow-knight', package: 'com.TeamCherry.HollowKnight', area: Area.androidData, root: 'files'))),
      GameStatus(bundledRecipe('sea-of-stars'), 'bundled', const NotInstalled()),
      GameStatus(bundledRecipe('cuphead'), 'bundled', const NotInstalled()),
    ],
    appInfo: const {stardewPkg: AppInfo('Stardew Valley', null), 'com.TeamCherry.HollowKnight': AppInfo('Hollow Knight', null)},
    recipeProblems: const {'balatro.json': 'unknown key "uinit" (did you mean "unit"?)'},
  );

  final shots = <String, Future<void> Function(WidgetTester)>{
    // Games Library setup.
    'wizard_setup_catalog': (t) => setup(t, 'wizard_setup_catalog'),
    'wizard_setup_link': (t) => setup(t, 'wizard_setup_link', act: (t) async {
          await t.tap(find.text('From a link'));
          await frames(t, 2);
          await t.enterText(find.byType(TextField), 'https://example.com/consoles.json');
          await frames(t, 2);
        }),
    // The test binding answers every request with 400: a real failed load.
    'wizard_setup_link_error': (t) => setup(t, 'wizard_setup_link_error', act: (t) async {
          await t.tap(find.text('From a link'));
          await frames(t, 2);
          await t.enterText(find.byType(TextField), 'https://example.com/consoles.json');
          await frames(t, 2);
          await t.tap(find.byKey(const ValueKey('kit-primary')));
          await realWait(t, 1500);
        }),
    'wizard_setup_empty': (t) => setup(t, 'wizard_setup_empty', catalog: const []),
    'wizard_setup_downloads': (t) => setup(t, 'wizard_setup_downloads', step: 1),
    'wizard_setup_connections': (t) => setup(t, 'wizard_setup_connections', step: 2, catalog: _withLogins),
    'wizard_setup_connections_none': (t) => setup(t, 'wizard_setup_connections_none', step: 2),
    'wizard_setup_pad': (t) => setup(t, 'wizard_setup_pad', act: (t) async {
          await press(t, LogicalKeyboardKey.arrowDown);
        }),
    'wizard_setup_pad_connections': (t) => setup(t, 'wizard_setup_pad_connections', step: 1, catalog: _withLogins, act: (t) async {
          await press(t, LogicalKeyboardKey.gameButtonStart);
          await frames(t, 4);
        }),

    // Save Sync setup.
    'wizard_savesync_where': (t) => saveSync(t, 'wizard_savesync_where', const SaveSyncState(hubKind: HubKind.none, googleAvailable: true)),
    'wizard_savesync_where_folder': (t) => saveSync(t, 'wizard_savesync_where_folder', const SaveSyncState(hubKind: HubKind.none)),
    'wizard_savesync_signing': (t) => saveSync(t, 'wizard_savesync_signing', const SaveSyncState(hubKind: HubKind.none, googleAvailable: true, signingIn: true)),
    'wizard_savesync_signin_error': (t) => saveSync(
        t, 'wizard_savesync_signin_error', const SaveSyncState(hubKind: HubKind.none, googleAvailable: true, signInError: 'Google sign-in failed: the network is unreachable.')),
    'wizard_savesync_apps': (t) => saveSync(t, 'wizard_savesync_apps', hub),
    'wizard_savesync_apps_loading': (t) => saveSync(t, 'wizard_savesync_apps_loading', const SaveSyncState(hubKind: HubKind.folder, loading: true)),
    'wizard_savesync_apps_error': (t) => saveSync(
        t, 'wizard_savesync_apps_error', const SaveSyncState(hubKind: HubKind.folder, hubFolder: '/storage/emulated/0/Old Saves', error: 'No hub here: the folder has no devices.json')),
    'wizard_savesync_apps_empty': (t) => saveSync(t, 'wizard_savesync_apps_empty', const SaveSyncState(hubKind: HubKind.folder)),
    'wizard_savesync_pad': (t) => saveSync(t, 'wizard_savesync_pad', const SaveSyncState(hubKind: HubKind.none, googleAvailable: true), act: (t) async {
          await press(t, LogicalKeyboardKey.arrowDown);
        }),

    // Sports patcher.
    'wizard_patcher_rom': (t) => patcher(t, 'wizard_patcher_rom', const SportPatcherWizardScreen(info: _patcher, initialLeagues: _leagues)),
    'wizard_patcher_rom_chosen': (t) => patcher(t, 'wizard_patcher_rom_chosen', const SportPatcherWizardScreen(info: _patcher, initialLeagues: _leagues, initialRomPath: _rom)),
    'wizard_patcher_rosters': (t) => patcher(t, 'wizard_patcher_rosters', const SportPatcherWizardScreen(info: _patcher, initialLeagues: _leagues, initialRomPath: _rom, initialStep: 1)),
    'wizard_patcher_teams': (t) => patcher(t, 'wizard_patcher_teams', SportPatcherWizardScreen(info: _patcher, initialLeagues: _leagues, initialDoc: _doc(), initialRomPath: _rom, initialStep: 2)),
    'wizard_patcher_look': (t) =>
        patcher(t, 'wizard_patcher_look', SportPatcherWizardScreen(info: _patcher, initialLeagues: _leagues, initialDoc: _doc(), initialRomPath: _rom, initialStep: 3, initialImages: const {})),
    // A file of the wrong kind: the step says why and keeps the slot empty.
    'wizard_patcher_rom_error': (t) => patcher(t, 'wizard_patcher_rom_error', const SportPatcherWizardScreen(info: _patcher, initialLeagues: _leagues), act: (t) async {
          picker.file = '/storage/emulated/0/ROMs/nes/Contra (USA).nes';
          final choose = find.text('Choose the game file');
          await t.ensureVisible(choose);
          await frames(t, 2);
          await withNativePicker(() async {
            await t.tap(choose);
            await realWait(t, 600);
          });
        }),
    'wizard_patcher_patch': (t) => patcher(t, 'wizard_patcher_patch', SportPatcherWizardScreen(info: _patcher, initialLeagues: _leagues, initialDoc: _doc(), initialRomPath: _rom, initialStep: 4)),
    'wizard_patcher_done': (t) => patcher(
          t,
          'wizard_patcher_done',
          SportPatcherWizardScreen(
            info: _patcher,
            initialLeagues: _leagues,
            initialDoc: _doc(),
            initialRomPath: _rom,
            initialStep: 4,
            initialResult: const PatchResult(
              outputPath: '/storage/emulated/0/ROMs/psx/Brasileirao Serie A 2026 - Winning Eleven 2002 (Japan).bin',
              teamsPatched: 20,
              playersPatched: 460,
              notes: ['Santos skipped: 17 players in the list, the game needs 18; the slot keeps the original team'],
            ),
          )),
    'wizard_patcher_pad': (t) => patcher(t, 'wizard_patcher_pad', SportPatcherWizardScreen(info: _patcher, initialLeagues: _leagues, initialDoc: _doc(), initialRomPath: _rom, initialStep: 2),
            act: (t) async {
          await press(t, LogicalKeyboardKey.gameButtonStart);
          await frames(t, 4);
        }),
  };

  for (final MapEntry(key: name, value: run) in shots.entries) {
    testWidgets(name, run, skip: !screenshotsEnabled || !_want(name));
  }
}
