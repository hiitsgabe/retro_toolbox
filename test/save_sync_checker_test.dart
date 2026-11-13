import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/pusher.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

import 'save_sync_support.dart';

/// Path to sha256 of every file under [dir], to prove Check changed nothing.
Map<String, String> fingerprint(String dir) => {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) p.relative(f.path, from: dir): sha256.convert(f.readAsBytesSync()).toString(),
    };

void main() {
  late Directory tmp;
  late TestDevice thor;
  late Hub hub;
  final stardew = bundledRecipe('stardew-valley');
  const binding = Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.androidData, root: 'files/Saves');

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('checker');
    thor = TestDevice(p.join(tmp.path, 'thor'), 'AYN Thor');
    hub = Hub(FolderBackend(Directory(p.join(tmp.path, 'hub'))));
    await hub.open(deviceId: 'thor-7f3a', create: true);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  GameChecker checker() => GameChecker(fs: thor.fsFor(stardew), hub: hub, paths: thor.paths, privilege: thor.shell.privilege, stagingRoot: p.join(thor.paths.saveSync, '.staging'));

  Future<void> pushFarm() async {
    final unit = (await UnitScanner(thor.fsFor(stardew)).scan(stardew, thor.saves))['Farm_1']!;
    await Pusher(fs: thor.fsFor(stardew), hub: hub, stagingRoot: p.join(thor.paths.saveSync, '.staging'), deviceId: 'thor-7f3a', deviceName: 'AYN Thor')
        .push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: unit, parents: const []);
  }

  String levels(List<CheckLine> lines) => lines.map((l) => '${l.level.name} ${l.title}').join('\n');

  test('a healthy game: every line ok, and nothing changes on disk', () async {
    thor.writeFarm('Farm_1', 'day 1');
    File(p.join(thor.saves, 'Farm_1', 'Farm_1_old')).writeAsStringSync('yesterday');
    await pushFarm();
    final before = fingerprint(tmp.path);
    final lines = await checker().check(stardew, source: 'bundled', binding: binding);
    expect(lines.where((l) => l.level != CheckLevel.ok), isEmpty, reason: levels(lines));
    expect(lines.map((l) => l.title), containsAll(['Recipe', 'App', 'Access', 'Save folder', 'Farm_1', 'Stays on this device', 'Hub Farm_1']));
    expect(lines.firstWhere((l) => l.title == 'Stays on this device').detail, contains('Farm_1/Farm_1_old'));
    final after = fingerprint(tmp.path)..removeWhere((k, _) => k.contains('.staging'));
    expect(after, before);
  });

  test('not installed stops after the app line', () async {
    thor.shell.installed = {};
    final lines = await checker().check(stardew, source: 'bundled');
    expect(lines.last.level, CheckLevel.fail);
    expect(lines.last.title, 'App');
  });

  test('a cut-off local save fails its line; a running game warns', () async {
    thor.writeFarm('Farm_1', 'day 1');
    File(p.join(thor.saves, 'Farm_1', 'Farm_1')).writeAsStringSync('<SaveGame>cut');
    thor.shell.gameRunning = true;
    final lines = await checker().check(stardew, source: 'bundled', binding: binding);
    expect(lines.firstWhere((l) => l.title == 'Farm_1').level, CheckLevel.fail);
    expect(lines.firstWhere((l) => l.title == 'Game').level, CheckLevel.warn);
  });

  test('a damaged hub copy fails; a save from a newer game warns', () async {
    thor.writeFarm('Farm_1', 'day 1', version: '1.7.0');
    await pushFarm();
    var lines = await checker().check(stardew, source: 'bundled', binding: binding);
    expect(lines.firstWhere((l) => l.title == 'Hub Farm_1').level, CheckLevel.warn);

    final zip = Directory(p.join(tmp.path, 'hub', 'units', 'stardew-valley', 'Farm_1')).listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.zip'));
    zip.writeAsBytesSync([1, 2, 3]);
    final freshHub = Hub(FolderBackend(Directory(p.join(tmp.path, 'hub'))));
    lines = await GameChecker(
      fs: thor.fsFor(stardew),
      hub: freshHub,
      paths: thor.paths,
      privilege: thor.shell.privilege,
      stagingRoot: p.join(thor.paths.saveSync, '.staging'),
    ).check(stardew, source: 'bundled', binding: binding);
    expect(lines.firstWhere((l) => l.title == 'Hub Farm_1').level, CheckLevel.fail);
  });
}
