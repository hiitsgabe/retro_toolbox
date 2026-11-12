import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';

import 'save_sync_support.dart';

const seaOfStarsPkg = 'com.playdigious.seaofstars';

/// Passes every command to [inner] except a `test` probe of a path under
/// [dead], which gets no answer, the way a dropped Shizuku bridge fails.
class DeadProbeShell implements PrivilegedShell {
  DeadProbeShell(this.inner, this.dead);

  final PrivilegedShell inner;
  final String dead;

  @override
  Privilege get privilege => inner.privilege;

  @override
  Future<ShellResult> run(List<String> argv) async {
    if (argv.first == 'test' && p.isWithin(dead, argv.last)) return const ShellResult(ShellResult.unreachable, '', 'bridge gone');
    return inner.run(argv);
  }
}

void main() {
  late Directory tmp;
  late String hubDir;
  final stardew = bundledRecipe('stardew-valley');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('engine');
    hubDir = p.join(tmp.path, 'hub');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(TestDevice, SaveSyncEngine)> device(String id, String name, int minute, {PrivilegedShell Function(TestDevice d)? shell}) async {
    final d = TestDevice(p.join(tmp.path, id), name);
    d.makeSavesFolder();
    final hub = Hub(FolderBackend(Directory(hubDir)));
    await hub.open(deviceId: id);
    return (
      d,
      SaveSyncEngine(
        shell: shell == null ? d.shell : shell(d),
        hub: hub,
        state: SyncState(MemoryStore()),
        paths: d.paths,
        deviceId: id,
        deviceName: name,
        model: name,
        appVersion: '0.6.0',
        clock: () => DateTime.utc(2026, 11, 10, 22, minute),
      ),
    );
  }

  test('push on one device, pull on the other, edit and come back', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (odin, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');

    var s = await a.status(stardew);
    expect(s.bind, isA<Bound>());
    expect(s.units['Farm_1']!.plan, isA<PushPlan>());
    expect(await a.push(stardew), ['Farm_1: pushed']);
    expect((await a.status(stardew)).units['Farm_1']!.plan, isA<UpToDate>());

    s = await b.status(stardew);
    expect((s.units['Farm_1']!.plan as PullPlan).missingLocally, isTrue);
    expect(s.canPull, isTrue);
    expect(await b.pull(stardew), ['Farm_1: pulled']);
    expect(odin.farm('Farm_1'), contains('day 1'));
    expect((await b.status(stardew)).units['Farm_1']!.plan, isA<UpToDate>());

    odin.writeFarm('Farm_1', 'day 2');
    expect(await b.push(stardew), ['Farm_1: pushed']);
    expect((await a.status(stardew)).units['Farm_1']!.plan, isA<PullPlan>());
    await a.pull(stardew);
    expect(thor.farm('Farm_1'), contains('day 2'));
  });

  test('both edit offline: divergence, nothing overwritten', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (odin, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');
    await a.push(stardew);
    await b.pull(stardew);
    thor.writeFarm('Farm_1', 'thor day 2');
    odin.writeFarm('Farm_1', 'odin day 2');
    await a.push(stardew);
    final s = await b.status(stardew);
    expect(s.units['Farm_1']!.plan, isA<Diverged>());
    expect(await b.pull(stardew), ['Nothing to pull']);
    expect(odin.farm('Farm_1'), contains('odin day 2'));
  });

  Set<String> hubJsons() => {
        for (final f in Directory(p.join(hubDir, 'units', 'stardew-valley', 'Farm_1')).listSync().whereType<File>())
          if (f.path.endsWith('.json')) p.basename(f.path),
      };

  test('metadata that arrives late: both devices see the divergence and no farm is overwritten', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (odin, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');
    await a.push(stardew);
    await b.pull(stardew);
    final known = hubJsons();
    thor.writeFarm('Farm_1', 'thor day 2');
    expect(await a.push(stardew), ['Farm_1: pushed']);
    final late = hubJsons().difference(known).single;
    final hidden = p.join(tmp.path, late);
    File(p.join(hubDir, 'units', 'stardew-valley', 'Farm_1', late)).renameSync(hidden); // B has the zip but not the metadata yet
    odin.writeFarm('Farm_1', 'odin day 2');
    expect(await b.push(stardew), ['Farm_1: pushed']);
    File(hidden).renameSync(p.join(hubDir, 'units', 'stardew-valley', 'Farm_1', late));

    for (final e in [a, b]) {
      final s = await e.status(stardew);
      expect(s.units['Farm_1']!.plan, isA<Diverged>());
      expect((s.units['Farm_1']!.plan as Diverged).localDiffers, isFalse);
      expect(await e.pull(stardew), ['Nothing to pull']);
    }
    expect(thor.farm('Farm_1'), contains('thor day 2'));
    expect(odin.farm('Farm_1'), contains('odin day 2'));
  });

  test('a stored internal binding without root needs root, and neither pushes nor pulls', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (_, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');
    await a.push(stardew);
    await b.state.setBinding(const Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.internal, root: 'files/Saves'));
    final s = await b.status(stardew);
    expect(s.bind, isA<NeedsRoot>());
    expect(s.canPush, isFalse);
    expect(s.canPull, isFalse);
  });

  test('a running game blocks its units', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (odin, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');
    await a.push(stardew);
    odin.shell.gameRunning = true;
    final s = await b.status(stardew);
    expect(s.running, isTrue);
    expect((s.units['Farm_1']!.plan as Blocked).reason, 'Stardew Valley is running');
    expect(s.canPull, isFalse);
  });

  test('a save from a newer game is blocked before Pull is offered', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (_, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1', version: '1.7.0');
    await a.push(stardew);
    final s = await b.status(stardew);
    expect((s.units['Farm_1']!.plan as Blocked).reason, contains('1.7.0'));
    expect(s.canPull, isFalse);
  });

  test('the next status recovers a pull whose rollback failed, and says so', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (odin, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');
    await a.push(stardew);
    await b.pull(stardew);
    thor.writeFarm('Farm_1', 'day 5');
    await a.push(stardew);
    odin.shell.failReplaceFrom = odin.shell.replaces + 1; // Farm_1/Farm_1 is replaced, then every replace fails
    expect((await b.pull(stardew)).single, contains('putting the old files back failed'));
    expect(odin.farm('Farm_1'), contains('day 5'));

    odin.shell.failReplaceFrom = -1;
    final s = await b.status(stardew);
    expect(s.notes, ['Recovered an interrupted pull of Farm_1']);
    expect(odin.farm('Farm_1'), contains('day 1'));
    expect(s.units['Farm_1']!.plan, isA<PullPlan>());
    expect((await b.status(stardew)).notes, isEmpty);
  });

  test('status does not adopt a base from a half-done pull while the game runs', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (odin, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');
    await a.push(stardew);
    await b.pull(stardew);
    thor.writeFarm('Farm_1', 'day 5');
    await a.push(stardew);
    odin.shell.startGameAfterReplaces = odin.shell.replaces + 2;
    odin.shell.failReplaceFrom = odin.shell.replaces + 2; // both files replaced, the game starts, the rollback fails
    await b.pull(stardew);
    await b.status(stardew); // the game is running: no recovery, and no adopting either
    odin.shell.startGameAfterReplaces = -1;
    odin.shell.failReplaceFrom = -1;
    final s = await b.status(stardew);
    expect(odin.farm('Farm_1'), contains('day 1'));
    expect(s.units['Farm_1']!.plan, isA<PullPlan>());
  });

  test('an interrupted pull the game saved over blocks only its unit, and says where both versions are', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (odin, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');
    thor.writeFarm('Farm_2', 'two day 1');
    await a.push(stardew);
    await b.pull(stardew);
    thor.writeFarm('Farm_1', 'day 5');
    await a.push(stardew);
    odin.shell.failReplaceFrom = odin.shell.replaces + 1; // Farm_1/Farm_1 is replaced, then every replace fails
    expect((await b.pull(stardew)).single, contains('putting the old files back failed'));
    odin.shell.failReplaceFrom = -1;
    odin.writeFarm('Farm_1', 'day 9'); // the game ran and saved before the next status
    thor.writeFarm('Farm_2', 'two day 2');
    await a.push(stardew);

    final s = await b.status(stardew);
    final kept = [
      for (final e in Directory(p.join(odin.paths.saveSync, 'history', 'stardew-valley', 'Farm_1')).listSync())
        if (e.path.endsWith('-before-recover')) e.path,
    ].single;
    expect(s.error, isNull);
    expect(s.notes, ['Farm_1: an interrupted pull could not be undone because the files changed since; both versions are kept in $kept']);
    expect((s.units['Farm_1']!.plan as Blocked).reason, 'interrupted pull needs attention');
    expect(s.units['Farm_2']!.plan, isA<PullPlan>());
    expect(await b.pull(stardew), ['Farm_2: pulled']);
    expect(odin.farm('Farm_2'), contains('two day 2'));
    expect(odin.farm('Farm_1'), contains('day 9'));
  });

  test('a save folder probe that fails gives that game an error and leaves the other game alone', () async {
    final seaOfStars = bundledRecipe('sea-of-stars');
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1, shell: (d) => DeadProbeShell(d.shell, d.paths.area(Area.androidData, seaOfStarsPkg)));
    thor.shell.installed.add(seaOfStarsPkg);
    thor.writeFarm('Farm_1', 'day 1');

    final sea = await a.status(seaOfStars);
    expect(sea.error, contains('bridge gone'));
    expect((sea.bind as NeedsDiscovery).reason, 'could not look in the save folders');

    final farm = await a.status(stardew);
    expect(farm.error, isNull);
    expect(farm.bind, isA<Bound>());
    expect(farm.units['Farm_1']!.plan, isA<PushPlan>());
  });

  test('the game list keeps every game when one status throws', () async {
    final seaOfStars = bundledRecipe('sea-of-stars');
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    thor.writeFarm('Farm_1', 'day 1');

    final games = await gameStatuses(
      [(seaOfStars, 'bundled'), (stardew, 'bundled')],
      (r, source) async => r.id == seaOfStars.id ? throw GameFsError('test failed: exit -1: bridge gone') : await a.status(r, source: source),
    );
    expect([for (final g in games) g.recipe.id], ['sea-of-stars', 'stardew-valley']);
    expect(games.first.error, 'test failed: exit -1: bridge gone');
    expect(games.first.bind, isA<NeedsDiscovery>());
    expect(games.last.error, isNull);
    expect(games.last.units['Farm_1']!.plan, isA<PushPlan>());
  });

  test('push publishes the recipe; report writes the device file and README', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    thor.writeFarm('Farm_1', 'day 1');
    await a.push(stardew);
    final hub = Hub(FolderBackend(Directory(hubDir)));
    expect((await hub.recipes())['stardew-valley']!.source, 'bundled');

    await a.report([await a.status(stardew)], access: 'shizuku');
    final me = (await hub.devices()).single;
    expect(me['id'], 'thor-7f3a');
    expect((me['games'] as List).single['units'], ['Farm_1']);
    final readme = File(p.join(hubDir, 'README.txt')).readAsStringSync();
    expect(readme, contains('AYN Thor (thor-7f3a)'));
    expect(readme, contains('Stardew Valley (stardew-valley)'));
    expect(File(p.join(thor.paths.saveSync, 'log.txt')).readAsStringSync(), contains('\tpush\t'));
  });

  test('backup-only binding never pulls', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    final (_, b) = await device('odin-02c4', 'AYN Odin 2 Mini', 2);
    thor.writeFarm('Farm_1', 'day 1');
    await a.push(stardew);
    await b.state.setBinding(const Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.androidData, root: 'files/Saves', mode: 'backup'));
    final s = await b.status(stardew);
    expect(s.canPull, isFalse);
    expect((await b.pull(stardew)).single, contains('backup only'));
  });

  test('check runs through the engine', () async {
    final (thor, a) = await device('thor-7f3a', 'AYN Thor', 1);
    thor.writeFarm('Farm_1', 'day 1');
    final lines = await a.check(stardew);
    expect(lines.first.title, 'Recipe');
    expect(jsonEncode(lines.map((l) => l.title).toList()), contains('Farm_1'));
  });
}
