import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/hub_jksv_source.dart';
import 'package:retro_toolbox/services/jksv_folder_source.dart';
import 'package:retro_toolbox/services/jksv_meta.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';

const _id = '0100000000ABC000';

/// Counts how often the listing is read, to prove the cache holds.
class _CountingHub extends Hub {
  _CountingHub(super.backend);

  int unitsCalls = 0;

  @override
  Future<List<String>> units(String recipe) {
    unitsCalls++;
    return super.units(recipe);
  }
}

/// Entry names and bytes in archive order; zip timestamps follow the wall clock.
List<List<Object>> _entries(List<int> zip) => [
      for (final e in ZipDecoder().decodeBytes(zip))
        if (e.isFile) [e.name, List<int>.from(e.content as List<int>)]
    ];

List<int> _zip(Map<String, List<int>> files) {
  final a = Archive();
  for (final path in files.keys.toList()..sort()) {
    a.addFile(ArchiveFile.bytes(path, files[path]!));
  }
  return ZipEncoder().encodeBytes(a);
}

void main() {
  late Directory tmp;
  late _CountingHub hub;
  var now = DateTime.utc(2026, 11, 19, 12);

  /// A gen another device wrote: `<unit>/<rel>` paths, as Eden's folder recipe pushes them.
  Future<GenMeta> putGen(String unit, Map<String, List<int>> rels, DateTime at, {List<String> parents = const [], String device = 'odin-02c4'}) async {
    final files = {for (final e in rels.entries) '$unit/${e.key}': e.value};
    final zip = _zip(files);
    final sha = sha256.convert(zip).toString();
    final meta = GenMeta(
      gen: makeGenId(at, device, sha),
      parents: parents,
      recipe: 'eden',
      unit: unit,
      device: device,
      deviceName: 'Odin',
      createdAt: at,
      package: 'dev.eden.eden_emulator',
      files: {for (final e in files.entries) e.key: GenFile(sha256.convert(e.value).toString(), e.value.length)},
      payloadSha256: sha,
    );
    await hub.put(meta, zip);
    return meta;
  }

  HubJksvSource source() => HubJksvSource(hub: hub, recipe: 'eden', deviceId: 'thor-7f3a', deviceName: 'Switch (JKSV)', clock: () => now);

  setUp(() async {
    now = DateTime.utc(2026, 11, 19, 12);
    tmp = Directory.systemTemp.createTempSync('hub_jksv');
    hub = _CountingHub(FolderBackend(Directory(p.join(tmp.path, 'hub'))));
    await hub.open(deviceId: 'thor-7f3a', create: true);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('lists only units whose key is a title id, upper-cased', () async {
    await putGen(_id, {'slot': [1]}, DateTime.utc(2026, 11, 18));
    await putGen('notatitle', {'slot': [2]}, DateTime.utc(2026, 11, 18));
    await putGen('0100000000def000', {'slot': [3]}, DateTime.utc(2026, 11, 18));
    expect(await source().titleIds(), [_id, '0100000000DEF000']);
  });

  test('backup of a unit with two heads uses the newest one', () async {
    await putGen(_id, {'slot': 'old'.codeUnits}, DateTime.utc(2026, 11, 17));
    await putGen(_id, {'slot': 'new'.codeUnits}, DateTime.utc(2026, 11, 18), device: 'loki-0001');
    final zip = ZipDecoder().decodeBytes(await source().backupZip(_id));
    expect(zip.findFile('slot')!.content, 'new'.codeUnits);
    expect(zip.findFile(JksvMeta.fileName), isNotNull);
  });

  test('backup of a title with no gens throws', () async {
    await expectLater(source().backupZip(_id), throwsA(anything));
  });

  test('backup bytes equal the folder source for the same files', () async {
    final rels = {'dir/inner.bin': [0, 1, 255], 'slot00': 'savedata'.codeUnits};
    await putGen(_id, rels, DateTime.utc(2026, 11, 18));
    final folder = Directory(p.join(tmp.path, 'exports'))..createSync();
    File(p.join(folder.path, 'game.zip')).writeAsBytesSync(_zip({for (final e in rels.entries) '$_id/${e.key}': e.value}));
    final fromFolder = await FolderJksvSource(root: folder).backupZip(_id);
    final fromHub = await source().backupZip(_id);
    expect(_entries(fromHub), _entries(fromFolder));
    expect(fromHub.length, fromFolder.length);
  });

  test('applyIncoming writes one gen over the heads that the next backup serves', () async {
    final a = await putGen(_id, {'slot': 'a'.codeUnits}, DateTime.utc(2026, 11, 17));
    final b = await putGen(_id, {'slot': 'b'.codeUnits}, DateTime.utc(2026, 11, 18), device: 'loki-0001');
    final src = source();
    expect(ZipDecoder().decodeBytes(await src.backupZip(_id)).findFile('slot')!.content, 'b'.codeUnits);

    final jksv = Archive()
      ..addFile(ArchiveFile.bytes('slot', 'switch'.codeUnits))
      ..addFile(ArchiveFile.bytes('sub/extra.bin', [9, 8]))
      ..addFile(ArchiveFile.bytes(JksvMeta.fileName, JksvMeta.encode(applicationId: int.parse(_id, radix: 16))));
    now = now.add(const Duration(seconds: 5));
    await src.applyIncoming(_id, ZipEncoder().encodeBytes(jksv), timestamp: '20261119-120005');

    final gens = await Hub(hub.backend).gens('eden', _id);
    expect(gens, hasLength(3));
    final mine = gens.singleWhere((g) => g.gen != a.gen && g.gen != b.gen);
    expect(mine.parents.toSet(), {a.gen, b.gen});
    expect(mine.kind, 'save');
    expect(mine.device, 'thor-7f3a');
    expect(mine.deviceName, 'Switch (JKSV)');
    expect(mine.package, 'jksv');
    expect(mine.packageVersion, isNull);
    expect(mine.createdAt, now);
    expect(mine.gen, startsWith('20261119T120005Z-thor-7f3a-'));
    expect(mine.files.keys.toSet(), {'$_id/slot', '$_id/sub/extra.bin'});
    expect(mine.files['$_id/slot']!.size, 6);

    final payload = ZipDecoder().decodeBytes(await hub.payload(mine));
    expect([for (final e in payload) e.name], ['$_id/slot', '$_id/sub/extra.bin']);
    expect(payload.findFile('$_id/slot')!.content, 'switch'.codeUnits);
    expect(mine.files['$_id/slot']!.sha256, sha256.convert('switch'.codeUnits).toString());

    // Within the cache window, yet the title was dropped from it.
    expect(ZipDecoder().decodeBytes(await src.backupZip(_id)).findFile('slot')!.content, 'switch'.codeUnits);
  });

  test('the listing is cached for 30 s by the clock', () async {
    await putGen(_id, {'slot': [1]}, DateTime.utc(2026, 11, 18));
    final src = source();
    await src.titleIds();
    now = now.add(const Duration(seconds: 29));
    await src.titleIds();
    expect(hub.unitsCalls, 1);
    now = now.add(const Duration(seconds: 2));
    await src.titleIds();
    expect(hub.unitsCalls, 2);
  });

  test('a payload is cached for 30 s by the clock', () async {
    await putGen(_id, {'slot': 'one'.codeUnits}, DateTime.utc(2026, 11, 18));
    final src = source();
    expect(ZipDecoder().decodeBytes(await src.backupZip(_id)).findFile('slot')!.content, 'one'.codeUnits);
    await putGen(_id, {'slot': 'two'.codeUnits}, DateTime.utc(2026, 11, 19), device: 'loki-0001');
    now = now.add(const Duration(seconds: 29));
    expect(ZipDecoder().decodeBytes(await src.backupZip(_id)).findFile('slot')!.content, 'one'.codeUnits);
    now = now.add(const Duration(seconds: 2));
    expect(ZipDecoder().decodeBytes(await src.backupZip(_id)).findFile('slot')!.content, 'two'.codeUnits);
  });
}
