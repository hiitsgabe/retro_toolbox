import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:retro_toolbox/companion/companion_tasks_view.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart' as gs;
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/providers/update_provider.dart';
import 'package:retro_toolbox/services/update_service.dart';
import 'package:retro_toolbox/screens/about_screen.dart';
import 'package:retro_toolbox/screens/save_sync_screen.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/screens/setup_wizard_screen.dart';
import 'package:retro_toolbox/screens/sport_games_grid_screen.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';

import '../save_sync_support.dart';
import 'support.dart';
import 'fakes.dart';

class _Shots extends SaveSyncNotifier {
  _Shots(SaveSyncState initial) {
    state = initial;
  }
  @override
  Future<void> refresh() async {}
  @override
  Future<List<CheckLine>> check(String recipeId) async => const [];
}

/// No network: the check answers "up to date" instead of failing with HTTP 400.
class _UpToDate extends UpdateNotifier {
  _UpToDate() : super(UpdateService());
  @override
  Future<void> checkOnOpen(String currentVersion) async => state = const UpdateState(UpdatePhase.upToDate);
}

void main() {
  screenshotSetUp();
  setUp(() => PackageInfo.setMockInitialValues(appName: 'Retro Toolbox', packageName: 'name.rafaismy.retrotoolbox', version: '0.7.7', buildNumber: '77', buildSignature: ''));

  testWidgets('save sync main', (t) async {
    final stardew = bundledRecipe('stardew-valley');
    final seaOfStars = bundledRecipe('sea-of-stars');
    const binding = Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.androidData, root: 'files/Saves');
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
    final ready = SaveSyncState(
      access: SyncAccess.shizuku,
      hubKind: HubKind.folder,
      hubFolder: '/storage/emulated/0/Retro Toolbox Saves',
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
    await launch(t, const SaveSyncScreen(), overrides: [saveSyncProvider.overrideWith((ref) => _Shots(ready))]);
    await snap(t, 'other_save_sync_main');
  }, skip: !screenshotsEnabled);

  testWidgets('game details', (t) async {
    final game = Game(
      title: 'Chrono Trigger (USA)',
      url: 'https://example.invalid/snes/chrono.zip',
      size: 4 << 20,
      consoleId: 'snes',
      details: const GameDetails(boxart: 'https://example.invalid/boxart/chrono.png', rating: 4.6, ratingCount: 812, genres: ['Role-Playing'], maxPlayers: 1),
    );
    await launch(t, GameDetailsPage(game: game), overrides: gamesOverrides([game, ...snesGames()]));
    await realWait(t, 600);
    await snap(t, 'other_game_details');
  }, skip: !screenshotsEnabled);

  testWidgets('about', (t) async {
    await launch(t, const AboutScreen(), overrides: [...consolesOverrides(), updateProvider.overrideWith((ref) => _UpToDate())]);
    await realWait(t, 600);
    await snap(t, 'other_about');
  }, skip: !screenshotsEnabled);

  testWidgets('setup wizard first step', (t) async {
    await launch(t, const SetupWizardScreen(), overrides: consolesOverrides());
    await realWait(t, 600);
    await snap(t, 'other_setup_wizard_step1');
  }, skip: !screenshotsEnabled);

  for (final s in [SettingsSection.library, SettingsSection.downloads, SettingsSection.network]) {
    testWidgets('settings ${s.name}', (t) async {
      final c = await launch(t, SettingsScreen(section: s), overrides: consolesOverrides());
      await realWait(t, 600);
      launchboxLoaded(c);
      await snap(t, 'other_settings_${s.name}');
    }, skip: !screenshotsEnabled);
  }

  testWidgets('task manager', (t) async {
    gs.GameState task(String title, gs.GameStatus status, {double? progress, bool done = false}) => gs.GameState(
          game: Game(title: '$title.zip', url: 'https://example.com/$title.zip', size: 24 << 20, consoleId: 'md', metadata: GameMetadata(displayTitle: title)),
          status: status,
          showProgressBar: progress != null,
          currentProgress: progress ?? 0,
          hasJustCompleted: done,
        );
    final tabs = classifyTasks([
      task('Sonic The Hedgehog', gs.GameStatus.downloading, progress: 0.4),
      task('Streets of Rage 2', gs.GameStatus.downloadQueued),
      task('Golden Axe', gs.GameStatus.downloadFailed),
    ]);
    CompanionTask row(gs.GameState s) => (state: s, favorite: false);
    await launch(
      t,
      Scaffold(
        body: CompanionTasksView(
          tabs: [for (final l in [tabs.downloading, tabs.extracting, tabs.queued, tabs.completed, tabs.failed]) l.map(row).toList()],
          onRequest: (_) {},
        ),
      ),
    );
    await realWait(t, 400);
    await snap(t, 'other_task_manager');
  }, skip: !screenshotsEnabled);

  testWidgets('team editor', (t) async {
    final team = RosterTeam(
      teamRaw: {'id': 1, 'name': 'Chicago Bulls', 'code': 'CHI', 'color': 'C2185B'},
      players: [
        for (final (i, n) in ['Michael Jordan', 'Scottie Pippen', 'Horace Grant', 'B.J. Armstrong', 'Bill Cartwright', 'John Paxson', 'Stacey King'].indexed)
          RosterPlayer(raw: {'id': i + 1, 'name': n, 'position': i.isEven ? 'G' : 'F'}),
      ],
      statsRaw: {},
      extraRaw: {},
    );
    await launch(t, TeamEditorScreen(team: team, gameId: 'nbalive95-genesis', sport: 'basketball'));
    await realWait(t, 400);
    await snap(t, 'other_team_editor');
  }, skip: !screenshotsEnabled);

  testWidgets('sport games', (t) async {
    const we = PatcherInfo(gameId: 'we2002-psx', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn']);
    await launch(t, const SportGamesGridScreen(sport: 'soccer'), overrides: [patchersProvider.overrideWith((ref) async => [we])]);
    await realWait(t, 400);
    await snap(t, 'other_sport_games');
  }, skip: !screenshotsEnabled);
}
