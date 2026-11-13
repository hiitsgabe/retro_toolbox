import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/hub_config.dart';

ConfigEntry entry(String? recipe, DateTime at, String by, {bool removed = false}) =>
    ConfigEntry(recipe: recipe, updatedAt: at, by: by, removed: removed);

void main() {
  final t0 = DateTime.utc(2026, 11, 13, 1);
  final t1 = DateTime.utc(2026, 11, 13, 2);

  group('merging what each device wrote', () {
    test('two devices changing different apps both survive', () {
      final merged = mergeConfigFiles([
        encodeConfigFile({'com.example.one': entry('one', t0, 'dev-a')}, deviceId: 'dev-a', writtenAt: t0),
        encodeConfigFile({'com.example.two': entry('two', t0, 'dev-b')}, deviceId: 'dev-b', writtenAt: t0),
      ]);
      expect(merged.packages, unorderedEquals(['com.example.one', 'com.example.two']));
    });

    test('the newer decision wins, whichever file it was read from', () {
      final merged = mergeConfigFiles([
        encodeConfigFile({'com.example.one': entry('old', t1, 'dev-b')}, deviceId: 'dev-b', writtenAt: t1),
        encodeConfigFile({'com.example.one': entry('new', t0, 'dev-a')}, deviceId: 'dev-a', writtenAt: t0),
      ]);
      expect(merged.entries['com.example.one']!.recipe, 'old', reason: 'later updatedAt wins, not later file');
    });

    test('a tie is broken the same way on every device', () {
      final files = [
        encodeConfigFile({'com.example.one': entry('from-a', t0, 'dev-a')}, deviceId: 'dev-a', writtenAt: t0),
        encodeConfigFile({'com.example.one': entry('from-b', t0, 'dev-b')}, deviceId: 'dev-b', writtenAt: t0),
      ];
      expect(mergeConfigFiles(files).entries['com.example.one']!.recipe, 'from-b');
      expect(mergeConfigFiles(files.reversed).entries['com.example.one']!.recipe, 'from-b');
    });

    // The point of a tombstone: a device that still holds the old file cannot
    // bring back an app the owner took out.
    test('a removal is not undone by a stale copy of the addition', () {
      final merged = mergeConfigFiles([
        encodeConfigFile({'com.example.one': entry('one', t0, 'dev-a')}, deviceId: 'dev-a', writtenAt: t0),
        encodeConfigFile({'com.example.one': entry(null, t1, 'dev-b', removed: true)}, deviceId: 'dev-b', writtenAt: t1),
      ]);
      expect(merged.entries['com.example.one']!.removed, isTrue);
      expect(merged.packages, isEmpty);
      expect(merged.count, 0);
    });

    test('an app wanted before any recipe exists is still an entry', () {
      final merged = mergeConfigFiles([encodeConfigFile({'com.example.one': entry(null, t0, 'dev-a')}, deviceId: 'dev-a', writtenAt: t0)]);
      expect(merged.packages, ['com.example.one']);
      expect(merged.entries['com.example.one']!.recipe, isNull);
    });

    test('junk and a key that is not a package are skipped, not fatal', () {
      final merged = mergeConfigFiles([
        [1, 2, 3],
        encodeConfigFile({'not a package': entry('x', t0, 'dev-a')}, deviceId: 'dev-a', writtenAt: t0),
        encodeConfigFile({'com.example.one': entry('one', t0, 'dev-a')}, deviceId: 'dev-a', writtenAt: t0),
      ]);
      expect(merged.packages, ['com.example.one']);
    });
  });

  group('through the hub', () {
    late Directory tmp;
    late Hub hub;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('hubconfig');
      hub = Hub(FolderBackend(Directory(p.join(tmp.path, 'hub'))));
      await hub.open(deviceId: 'dev-a', create: true, now: t0);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a hub with no config reads as empty, not as an error', () async {
      expect((await hub.config()).isEmpty, isTrue);
    });

    test('what one device writes, the next device reads', () async {
      await hub.putConfig({'com.example.one': entry('one', t0, 'dev-a')}, deviceId: 'dev-a', now: t0);
      final seen = await Hub(hub.backend).config();
      expect(seen.packages, ['com.example.one']);
    });

    test('writing the same change twice leaves one file', () async {
      final changed = {'com.example.one': entry('one', t0, 'dev-a')};
      expect(await hub.putConfig(changed, deviceId: 'dev-a', now: t0), isTrue);
      expect(await hub.putConfig(changed, deviceId: 'dev-a', now: t0), isFalse);
      expect(Directory(p.join(tmp.path, 'hub', 'config')).listSync().length, 1);
    });

    test('a later write never rewrites the earlier file', () async {
      await hub.putConfig({'com.example.one': entry('one', t0, 'dev-a')}, deviceId: 'dev-a', now: t0);
      await hub.putConfig({'com.example.two': entry('two', t1, 'dev-a')}, deviceId: 'dev-a', now: t1);
      expect(Directory(p.join(tmp.path, 'hub', 'config')).listSync().length, 2);
      expect((await hub.config()).packages, unorderedEquals(['com.example.one', 'com.example.two']));
    });
  });
}
