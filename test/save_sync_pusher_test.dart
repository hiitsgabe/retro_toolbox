import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/errors.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/pusher.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

import 'save_sync_support.dart';

void main() {
  late Directory tmp;
  late TestDevice thor;
  late Hub hub;
  final stardew = bundledRecipe('stardew-valley');
  const binding = Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.androidData, root: 'files/Saves');

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('pusher');
    thor = TestDevice(p.join(tmp.path, 'thor'), 'AYN Thor');
    hub = Hub(FolderBackend(Directory(p.join(tmp.path, 'hub'))));
    await hub.open(deviceId: 'thor-7f3a');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Pusher pusher() => Pusher(
        fs: thor.fsFor(stardew),
        hub: hub,
        stagingRoot: p.join(thor.paths.saveSync, '.staging'),
        deviceId: 'thor-7f3a',
        deviceName: 'AYN Thor',
        clock: () => DateTime.utc(2026, 11, 10, 22, 41, 7),
      );

  Future<LocalUnit> scan(String farm) async => (await UnitScanner(thor.fsFor(stardew)).scan(stardew, thor.saves))[farm]!;

  test('pushes a farm as a zip with metadata, versions and no staging left over', () async {
    thor.writeFarm('Farm_1', 'day 1');
    thor.writeFarm('Farm_1_extra', 'x');
    final unit = await scan('Farm_1');
    final gen = await pusher().push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: unit, parents: const []);
    expect(gen.gen, startsWith('20261110T224107Z-thor-7f3a-'));
    expect(gen.files.keys, ['Farm_1/Farm_1', 'Farm_1/SaveGameInfo']);
    expect(gen.gameVersion, '1.6.15');
    expect(gen.packageVersion, '1.6.15.2');
    final zip = ZipDecoder().decodeBytes(await hub.payload(gen));
    expect(utf8.decode(zip.findFile('Farm_1/Farm_1')!.content), contains('day 1'));
    expect((await hub.gens('stardew-valley', 'Farm_1')).single.gen, gen.gen);
    expect(Directory(p.join(thor.paths.saveSync, '.staging')).listSync(), isEmpty);
  });

  test('refuses while the game runs, while busy, and when a check fails', () async {
    thor.writeFarm('Farm_1', 'day 1');
    var unit = await scan('Farm_1');
    thor.shell.gameRunning = true;
    await expectLater(pusher().push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: unit, parents: const []), throwsA(isA<SyncBlocked>()));
    thor.shell.gameRunning = false;

    File(p.join(thor.saves, 'Farm_1', 'Farm_1_STARDEWVALLEYSAVETMP')).writeAsStringSync('');
    unit = await scan('Farm_1');
    await expectLater(pusher().push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: unit, parents: const []), throwsA(isA<SyncBlocked>()));
    File(p.join(thor.saves, 'Farm_1', 'Farm_1_STARDEWVALLEYSAVETMP')).deleteSync();

    File(p.join(thor.saves, 'Farm_1', 'Farm_1')).writeAsStringSync('<SaveGame>cut off');
    unit = await scan('Farm_1');
    await expectLater(pusher().push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: unit, parents: const []), throwsA(isA<SyncBlocked>()));
    expect(await hub.units('stardew-valley'), isEmpty);
  });

  test('a farm file every parent has but the unit lacks is refused', () async {
    thor.writeFarm('Farm_1', 'day 1');
    final parent = await pusher().push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: await scan('Farm_1'), parents: const []);
    File(p.join(thor.saves, 'Farm_1', 'SaveGameInfo')).deleteSync();
    final unit = await scan('Farm_1');
    await expectLater(
      pusher().push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: unit, parents: [parent]),
      throwsA(isA<SyncBlocked>().having((e) => e.reason, 'reason', contains('Farm_1/SaveGameInfo'))),
    );
    expect((await hub.gens('stardew-valley', 'Farm_1')).single.gen, parent.gen);
  });

  test('fails closed when the version a fromPackage recipe needs cannot be read', () async {
    final fromPackage = Recipe.parse({...stardew.raw, 'version': {'from': 'package', 'rule': 'sameBuild'}});
    thor.writeFarm('Farm_1', 'day 1');
    thor.shell.version = null; // dumpsys fails
    final unit = (await UnitScanner(thor.fsFor(fromPackage)).scan(fromPackage, thor.saves))['Farm_1']!;
    await expectLater(
      pusher().push(recipe: fromPackage, binding: binding, locationDir: thor.saves, unit: unit, parents: const []),
      throwsA(isA<SyncBlocked>().having((e) => e.reason, 'reason', contains('cannot read the save version'))),
    );
    expect(await hub.units('stardew-valley'), isEmpty);
  });

  test('a file that changed after scanning is refused', () async {
    thor.writeFarm('Farm_1', 'day 1');
    final unit = await scan('Farm_1');
    thor.writeFarm('Farm_1', 'day 2');
    await expectLater(pusher().push(recipe: stardew, binding: binding, locationDir: thor.saves, unit: unit, parents: const []), throwsA(isA<SyncBlocked>()));
  });
}
