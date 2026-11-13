import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/drive_api.dart';
import 'package:retro_toolbox/services/save_sync/drive_backend.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';

import 'save_sync_backend_contract.dart';
import 'save_sync_fake_drive.dart';
import 'save_sync_support.dart';

void main() {
  const account = '1234567890';
  late FakeDrive drive;

  setUp(() => drive = FakeDrive(pageSize: 2));

  /// A new backend, the way each refresh in the app makes one.
  DriveBackend backend() => DriveBackend(account, DriveApi(drive, FakeTokens(['token-1']), sleep: (_) async {}));

  group('contract', () => backendContract(() async => backend()));

  test('id is drive plus the account id, with no # or | (bases are keyed on it)', () {
    expect(backend().id, 'drive:1234567890');
  });

  test('the hub is a Retro Toolbox Saves folder in My Drive', () async {
    await backend().write('hub.json', utf8.encode('{"format":1}'));
    expect(drive.at('Retro Toolbox Saves')!.isFolder, isTrue);
    expect(utf8.decode(drive.at('Retro Toolbox Saves/hub.json')!.bytes), '{"format":1}');
  });

  test('two same-name folders: list and read take the union, writes go to the oldest', () async {
    final hub = drive.add('Retro Toolbox Saves');
    final older = drive.add('devices', parent: hub.id, created: DateTime.utc(2026, 11, 1));
    final newer = drive.add('devices', parent: hub.id, created: DateTime.utc(2026, 11, 2));
    drive.add('thor.json', parent: older.id, bytes: utf8.encode('thor'));
    drive.add('odin.json', parent: newer.id, bytes: utf8.encode('odin'));
    final b = backend();

    expect((await b.list('')).map((e) => e.name), ['devices']);
    expect((await b.list('devices')).map((e) => e.name), ['odin.json', 'thor.json']);
    expect(utf8.decode(await b.read('devices/odin.json')), 'odin');
    await b.write('devices/rg.json', utf8.encode('rg'));
    expect(drive.named(older.id, 'rg.json'), hasLength(1));
    expect(drive.named(newer.id, 'rg.json'), isEmpty);
  });

  test('a folder that exists only in the newer copy is written there, not made again', () async {
    final hub = drive.add('Retro Toolbox Saves');
    drive.add('units', parent: hub.id, created: DateTime.utc(2026, 11, 1));
    final newer = drive.add('units', parent: hub.id, created: DateTime.utc(2026, 11, 2));
    final stardew = drive.add('stardew-valley', parent: newer.id);
    await backend().write('units/stardew-valley/Farm_1/g.json', [1]);
    expect(drive.files.values.where((f) => f.name == 'stardew-valley'), hasLength(1));
    expect(drive.named(stardew.id, 'Farm_1'), hasLength(1));
  });

  test('a folder another device made after this one looked is found, not made again', () async {
    final thor = backend();
    final odin = backend();
    await thor.write('hub.json', [1]);
    expect(await thor.list('units'), isEmpty);
    await odin.write('units/stardew-valley/Farm_1/a.json', [1]);
    await thor.write('units/stardew-valley/Farm_2/b.json', [2]);
    expect(drive.files.values.where((f) => f.name == 'units'), hasLength(1));
    expect(drive.files.values.where((f) => f.name == 'stardew-valley'), hasLength(1));
  });

  test('a name stored twice always reads as the oldest copy, and delete trashes both', () async {
    final hub = drive.add('Retro Toolbox Saves');
    drive.add('hub.json', parent: hub.id, bytes: utf8.encode('{"id":"newer"}'), created: DateTime.utc(2026, 11, 2));
    drive.add('hub.json', parent: hub.id, bytes: utf8.encode('{"id":"older"}'), created: DateTime.utc(2026, 11, 1));
    expect((await backend().list('')).map((e) => e.name), ['hub.json']);
    for (var i = 0; i < 3; i++) {
      expect(utf8.decode(await backend().read('hub.json')), '{"id":"older"}');
    }
    final b = backend();
    await b.delete('hub.json');
    expect(drive.named(hub.id, 'hub.json'), isEmpty);
    expect(await b.list(''), isEmpty);
  });

  test('two devices that open an empty Drive at the same moment end up on one hub', () async {
    // Each made its own hub folder and hub.json before seeing the other's.
    final a = drive.add('Retro Toolbox Saves', created: DateTime.utc(2026, 11, 1, 9));
    final b = drive.add('Retro Toolbox Saves', created: DateTime.utc(2026, 11, 1, 9, 0, 1));
    drive.add('hub.json', parent: a.id, bytes: utf8.encode('{"format":1,"id":"aaaaaaaaaaaaaaaa"}'), created: DateTime.utc(2026, 11, 1, 9));
    drive.add('hub.json', parent: b.id, bytes: utf8.encode('{"format":1,"id":"bbbbbbbbbbbbbbbb"}'), created: DateTime.utc(2026, 11, 1, 9, 0, 1));
    final thor = Hub(backend());
    final odin = Hub(backend());
    await thor.open(deviceId: 'thor-7f3a', create: true);
    await odin.open(deviceId: 'odin-02c4', create: true);
    expect(thor.key, 'drive:1234567890#aaaaaaaaaaaaaaaa');
    expect(odin.key, thor.key);
  });

  test('a rewrite updates the same Drive file instead of adding a copy', () async {
    final b = backend();
    await b.write('README.txt', utf8.encode('one'));
    final id = drive.at('Retro Toolbox Saves/README.txt')!.id;
    await backend().write('README.txt', utf8.encode('two'));
    expect(drive.files.values.where((f) => f.name == 'README.txt'), hasLength(1));
    expect(utf8.decode(drive.files[id]!.bytes), 'two');
  });

  test('a full Drive fails the write with "Drive is full"', () async {
    final b = backend();
    await b.write('hub.json', [1]);
    drive.fail(403, reason: 'storageQuotaExceeded');
    await expectLater(b.write('units/r/u/g.zip', [1, 2]), throwsA(isA<DriveFull>()));
  });

  group('the engine over Drive', () {
    late Directory tmp;
    final stardew = bundledRecipe('stardew-valley');

    setUp(() => tmp = Directory.systemTemp.createTempSync('drive-engine'));
    tearDown(() => tmp.deleteSync(recursive: true));

    /// One handheld signed in to the same account; [state] outlives the engine like the app's preferences.
    Future<SaveSyncEngine> engine(TestDevice d, SyncState state, String id, int minute) async {
      final hub = Hub(backend());
      await hub.open(deviceId: id, create: true);
      return SaveSyncEngine(
        shell: d.shell,
        hub: hub,
        state: state,
        paths: d.paths,
        deviceId: id,
        deviceName: d.name,
        model: d.name,
        appVersion: '0.6.0',
        clock: () => DateTime.utc(2026, 11, 12, 22, minute),
      );
    }

    test('two handhelds carry a farm through one Google account', () async {
      final thor = TestDevice(p.join(tmp.path, 'thor'), 'AYN Thor')..makeSavesFolder();
      final odin = TestDevice(p.join(tmp.path, 'odin'), 'AYN Odin 2 Mini')..makeSavesFolder();
      final thorState = SyncState(MemoryStore());
      final odinState = SyncState(MemoryStore());
      thor.writeFarm('Farm_1', 'day 1');

      expect(await (await engine(thor, thorState, 'thor-7f3a', 1)).push(stardew), ['Farm_1: pushed']);
      final b = await engine(odin, odinState, 'odin-02c4', 2);
      expect((await b.status(stardew)).units['Farm_1']!.plan, isA<PullPlan>());
      expect(await b.pull(stardew), ['Farm_1: pulled']);
      expect(odin.farm('Farm_1'), contains('day 1'));

      odin.writeFarm('Farm_1', 'day 2');
      expect(await (await engine(odin, odinState, 'odin-02c4', 3)).push(stardew), ['Farm_1: pushed']);
      final a = await engine(thor, thorState, 'thor-7f3a', 4);
      expect(await a.pull(stardew), ['Farm_1: pulled']);
      expect(thor.farm('Farm_1'), contains('day 2'));
      expect(drive.files.values.where((f) => f.name.endsWith('.zip') && !f.trashed), hasLength(2));
    });

    test('a push into a full Drive fails with "Drive is full" and leaves the save to push later', () async {
      final thor = TestDevice(p.join(tmp.path, 'thor'), 'AYN Thor')..makeSavesFolder();
      final state = SyncState(MemoryStore());
      thor.writeFarm('Farm_1', 'day 1');
      final a = await engine(thor, state, 'thor-7f3a', 1);
      drive.fail(403, reason: 'storageQuotaExceeded', match: (r) => r.url.path.startsWith('/upload/'));
      final out = await a.push(stardew);
      expect(out.single, startsWith('Farm_1: Drive is full'));
      expect(thor.farm('Farm_1'), contains('day 1'));
      expect((await a.status(stardew)).units['Farm_1']!.plan, isA<PushPlan>());
    });
  });
}
