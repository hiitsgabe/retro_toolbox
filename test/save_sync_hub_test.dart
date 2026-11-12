import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';

GenMeta meta(String unit, DateTime t, List<int> zip, {List<String> parents = const []}) {
  final sha = sha256.convert(zip).toString();
  return GenMeta(
    gen: makeGenId(t, 'thor-7f3a', sha),
    parents: parents,
    recipe: 'stardew-valley',
    unit: unit,
    device: 'thor-7f3a',
    deviceName: 'AYN Thor',
    createdAt: t,
    package: 'com.chucklefish.stardewvalley',
    files: const {'Farm_1/Farm_1': GenFile('ab', 2)},
    payloadSha256: sha,
  );
}

class RecordingBackend implements HubBackend {
  RecordingBackend(this.inner);

  final HubBackend inner;
  final log = <String>[];

  @override
  String get id => inner.id;

  @override
  Future<List<HubEntry>> list(String dir) => inner.list(dir);

  @override
  Future<List<int>> read(String path) => inner.read(path);

  @override
  Future<void> write(String path, List<int> bytes) {
    log.add('write $path');
    return inner.write(path, bytes);
  }

  @override
  Future<void> delete(String path) {
    log.add('delete $path');
    return inner.delete(path);
  }
}

void main() {
  late Directory tmp;
  late FolderBackend backend;
  late Hub hub;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('hubtest');
    backend = FolderBackend(Directory(p.join(tmp.path, 'hub')));
    hub = Hub(backend);
    await hub.open(deviceId: 'thor-7f3a', now: DateTime.utc(2026, 11, 10));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('open writes hub.json once and refuses a newer format', () async {
    expect(jsonDecode(utf8.decode(await backend.read('hub.json')))['format'], 1);
    await backend.write('hub.json', utf8.encode('{"format": 2}'));
    await expectLater(Hub(backend).open(deviceId: 'x-0000'), throwsA(isA<HubTooNew>()));
  });

  test('open gives the hub an instance id, so a hub recreated at the same path has another key', () async {
    expect(hub.instanceId, matches(RegExp(r'^[0-9a-f]{16}$')));
    final again = Hub(backend);
    await again.open(deviceId: 'odin-02c4');
    expect(again.key, hub.key);
    Directory(p.join(tmp.path, 'hub')).deleteSync(recursive: true);
    final recreated = Hub(backend);
    await recreated.open(deviceId: 'odin-02c4');
    expect(recreated.key, isNot(hub.key));
    expect(recreated.key, startsWith('${backend.id}#'));
  });

  test('put writes zip then metadata; gens and units read them back', () async {
    final zip = [1, 2, 3];
    final m = meta('Farm_1', DateTime.utc(2026, 11, 10, 22), zip);
    final rec = RecordingBackend(backend);
    await Hub(rec).put(m, zip);
    final base = 'units/stardew-valley/Farm_1/${m.gen}';
    expect(rec.log, ['write $base.zip', 'write $base.json']);
    expect(await hub.units('stardew-valley'), ['Farm_1']);
    final gens = await Hub(backend).gens('stardew-valley', 'Farm_1');
    expect(gens.single.gen, m.gen);
    expect(await hub.payload(gens.single), zip);
  });

  test('payload with a wrong hash is PayloadCorrupt', () async {
    final m = meta('Farm_1', DateTime.utc(2026, 11, 10, 22), [1, 2, 3]);
    await hub.put(m, [9, 9, 9]);
    await expectLater(hub.payload(m), throwsA(isA<PayloadCorrupt>()));
  });

  test('foreign, misnamed and unparseable files are ignored', () async {
    final m = meta('Farm_1', DateTime.utc(2026, 11, 10, 22), [1]);
    await hub.put(m, [1]);
    final dir = 'units/stardew-valley/Farm_1';
    await backend.write('$dir/notes.txt', utf8.encode('hi'));
    await backend.write('$dir/${m.gen}.sync-conflict-20261110-1.json', utf8.encode('{}'));
    await backend.write('$dir/20261110T230000Z-odin-02c4-00000000.json', utf8.encode('not json'));
    await backend.write('$dir/20261110T230001Z-odin-02c4-11111111.json', utf8.encode(jsonEncode({...m.toJson(), 'gen': 'something-else'})));
    expect((await hub.gens('stardew-valley', 'Farm_1')).map((x) => x.gen), [m.gen]);
  });

  test('prune deletes old gens metadata first, keeps heads, and clears orphan zips older than a day', () async {
    var parent = <String>[];
    final all = <GenMeta>[];
    for (var i = 0; i < 4; i++) {
      final zip = [i];
      final m = meta('Farm_1', DateTime.utc(2026, 11, 10, 10 + i), zip, parents: parent);
      await hub.put(m, zip);
      all.add(m);
      parent = [m.gen];
    }
    final dir = 'units/stardew-valley/Farm_1';
    await backend.write('$dir/20261101T000000Z-odin-02c4-deadbeef.zip', [0]);
    await backend.write('$dir/20261110T235900Z-odin-02c4-cafebabe.zip', [0]);
    final removed = await hub.prune('stardew-valley', 'Farm_1', deviceId: 'odin-02c4', keep: 2, now: DateTime.utc(2026, 11, 11));
    expect(removed, 3);
    final names = (await backend.list(dir)).map((e) => e.name).toList();
    expect(names.where((n) => n.endsWith('.json')).length, 2);
    expect(names, isNot(contains('20261101T000000Z-odin-02c4-deadbeef.zip')));
    expect(names, contains('20261110T235900Z-odin-02c4-cafebabe.zip'));
    expect(names, isNot(contains('${all.first.gen}.zip')));
  });

  test('prune leaves an orphan zip another device wrote: its metadata may not have arrived yet', () async {
    final dir = 'units/stardew-valley/Farm_1';
    final m = meta('Farm_1', DateTime.utc(2026, 11, 10, 10), [1]);
    await hub.put(m, [1]);
    await backend.write('$dir/20261101T000000Z-odin-02c4-deadbeef.zip', [0]);
    await backend.write('$dir/20261101T000000Z-thor-7f3a-cafebabe.zip', [0]);
    expect(await hub.prune('stardew-valley', 'Farm_1', deviceId: 'thor-7f3a', now: DateTime.utc(2026, 11, 12)), 1);
    final names = (await backend.list(dir)).map((e) => e.name).toList();
    expect(names, contains('20261101T000000Z-odin-02c4-deadbeef.zip'));
    expect(names, isNot(contains('20261101T000000Z-thor-7f3a-cafebabe.zip')));
    expect(names, contains('${m.gen}.zip'));
  });

  test('recipes: publish once per content, newest copy per id', () async {
    final recipe = {'schema': 1, 'id': 'stardew-valley', 'name': 'Stardew Valley'};
    expect(await hub.publishRecipe(recipe, source: 'bundled', deviceId: 'thor-7f3a', now: DateTime.utc(2026, 11, 10, 1)), isTrue);
    expect(await hub.publishRecipe(recipe, source: 'bundled', deviceId: 'odin-02c4', now: DateTime.utc(2026, 11, 10, 2)), isFalse);
    final changed = {...recipe, 'name': 'Stardew'};
    expect(await hub.publishRecipe(changed, source: 'user', deviceId: 'odin-02c4', now: DateTime.utc(2026, 11, 10, 3)), isTrue);
    final recipes = await hub.recipes();
    expect(recipes.keys, ['stardew-valley']);
    expect(recipes['stardew-valley']!.recipe['name'], 'Stardew');
    expect(recipes['stardew-valley']!.source, 'user');
    expect(recipes['stardew-valley']!.device, 'odin-02c4');
  });

  test('device files and README', () async {
    await hub.writeDevice('thor-7f3a', {'id': 'thor-7f3a', 'name': 'AYN Thor'});
    await hub.writeDevice('odin-02c4', {'id': 'odin-02c4', 'name': 'AYN Odin 2 Mini'});
    await backend.write('devices/broken.json', utf8.encode('{'));
    expect((await hub.devices()).map((d) => d['id']), ['odin-02c4', 'thor-7f3a']);
    await hub.writeReadme('hello');
    expect(utf8.decode(await backend.read('README.txt')), 'hello');
  });
}
