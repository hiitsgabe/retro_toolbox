import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';

/// What Hub needs from every [HubBackend]. [make] gives a new, empty hub for each test.
void backendContract(Future<HubBackend> Function() make) {
  late HubBackend hub;
  setUp(() async => hub = await make());

  test('write creates parents, read returns the bytes, list shows files and folders', () async {
    await hub.write('units/stardew-valley/Farm_1/a.json', utf8.encode('{}'));
    await hub.write('hub.json', utf8.encode('{"format":1}'));
    expect(utf8.decode(await hub.read('hub.json')), '{"format":1}');
    expect((await hub.list('')).map((e) => '${e.name}:${e.isDir}'), ['hub.json:false', 'units:true']);
    expect((await hub.list('units/stardew-valley/Farm_1')).map((e) => '${e.name}:${e.size}'), ['a.json:2']);
  });

  test('list is sorted by name', () async {
    for (final name in ['b.json', 'c/x.json', 'a.json']) {
      await hub.write('devices/$name', [1]);
    }
    expect((await hub.list('devices')).map((e) => e.name), ['a.json', 'b.json', 'c']);
  });

  test('a missing folder lists as empty; deleting a missing file is fine', () async {
    expect(await hub.list('units/nothing'), isEmpty);
    expect(await hub.list(''), isEmpty);
    await hub.delete('units/nothing/x.json');
  });

  test('write replaces a file whole', () async {
    await hub.write('devices/thor.json', utf8.encode('a longer first version'));
    await hub.write('devices/thor.json', utf8.encode('2'));
    expect(utf8.decode(await hub.read('devices/thor.json')), '2');
    expect((await hub.list('devices')).map((e) => e.name), ['thor.json']);
  });

  test('delete removes the file and leaves the others', () async {
    await hub.write('units/r/u/a.zip', [1]);
    await hub.write('units/r/u/a.json', [2]);
    await hub.delete('units/r/u/a.json');
    expect((await hub.list('units/r/u')).map((e) => e.name), ['a.zip']);
  });

  test('names starting with a dot are hidden', () async {
    await hub.write('devices/.partial', [1]);
    await hub.write('devices/thor.json', [1]);
    expect((await hub.list('devices')).map((e) => e.name), ['thor.json']);
  });

  test('reading a file that is not there throws', () async {
    await expectLater(() => hub.read('units/r/u/nothing.json'), throwsA(isA<Exception>()));
  });

  test('unsafe paths are refused', () async {
    // A closure, since a backend may throw before it returns a Future.
    await expectLater(() => hub.write('../escape.json', [1]), throwsArgumentError);
    await expectLater(() => hub.read('/etc/passwd'), throwsArgumentError);
    await expectLater(() => hub.list('units/../..'), throwsArgumentError);
    await expectLater(() => hub.delete('units//x.json'), throwsArgumentError);
  });
}
