import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';

GenMeta meta(String unit, String device, DateTime t, List<int> zip) => GenMeta(
      gen: makeGenId(t, device, 'aaaaaaaa'),
      parents: const [],
      kind: 'backup',
      recipe: 'alpha',
      unit: unit,
      device: device,
      deviceName: device == 'odin-1' ? 'AYN Odin2 Mini' : 'Anbernic RG Rotate',
      createdAt: t,
      package: 'com.example.alpha',
      files: const {'save.dat': GenFile('abc', 3)},
      payloadSha256: 'x',
    );

List<int> zipOf(String body) {
  final a = Archive()..addFile(ArchiveFile.bytes('save.dat', utf8.encode(body)));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  late Directory tmp;
  late Hub hub;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('backup');
    hub = Hub(FolderBackend(Directory(p.join(tmp.path, 'hub'))));
    await hub.open(deviceId: 'odin-1', create: true);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a backup is not a generation, so it never becomes a head', () async {
    final t = DateTime.utc(2026, 11, 13, 3);
    await hub.putBackup(meta('all', 'odin-1', t, zipOf('older')), zipOf('older'), deviceId: 'odin-1');

    // The whole point: nothing under units/, so the planner cannot see it as
    // something this device pushed, and no other device diverges because of it.
    expect(await hub.gens('alpha', 'all'), isEmpty);
  });

  test('there is only ever one, whatever a device does', () async {
    final t = DateTime.utc(2026, 11, 13, 3);
    for (final body in ['first', 'second', 'third']) {
      await hub.putBackup(meta('all', 'odin-1', t, zipOf(body)), zipOf(body), deviceId: 'odin-1');
    }
    final dir = Directory(p.join(tmp.path, 'hub', 'backups', 'odin-1', 'alpha', 'all'));
    expect(dir.listSync().map((e) => p.basename(e.path)).toSet(), {'save.zip', 'save.json'});
    expect(utf8.decode(ZipDecoder().decodeBytes(await hub.backupPayload('odin-1', 'alpha', 'all')).first.readBytes()!), 'third');
  });

  test('two handhelds keep their own, and both can be restored from', () async {
    final t = DateTime.utc(2026, 11, 13, 3);
    await hub.putBackup(meta('all', 'odin-1', t, zipOf('from odin')), zipOf('from odin'), deviceId: 'odin-1');
    await hub.putBackup(meta('all', 'rg-2', t, zipOf('from rg')), zipOf('from rg'), deviceId: 'rg-2');

    expect(await hub.backupDevices('alpha', 'all'), unorderedEquals(['odin-1', 'rg-2']));
    expect((await hub.backup('odin-1', 'alpha', 'all'))!.deviceName, 'AYN Odin2 Mini');
    expect((await hub.backup('rg-2', 'alpha', 'all'))!.deviceName, 'Anbernic RG Rotate');
  });

  test('a device with no backup answers null rather than throwing', () async {
    expect(await hub.backup('never-seen', 'alpha', 'all'), isNull);
    expect(await hub.backupDevices('alpha', 'all'), isEmpty);
  });
}
