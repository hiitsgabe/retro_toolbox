import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_store.dart';

const snes = 'Super Nintendo Entertainment System';

const games = [
  LaunchboxGame(
    id: 1,
    name: 'Super Metroid',
    alternateNames: ['Metroid 3'],
    releaseDate: 19940319,
    overview: 'Samus returns.\nShe explores Zebes & fights Ridley.',
    maxPlayers: 1,
    rating: 4.5,
    ratingCount: 80,
    genres: ['Action', 'Platform'],
    developer: 'Nintendo R&D1',
    publisher: 'Nintendo',
    images: [
      LaunchboxImage(LaunchboxImageType.boxFront, 'metroid-a.jpg', 'North America'),
      LaunchboxImage(LaunchboxImageType.clearLogo, 'metroid-logo.png'),
    ],
  ),
  LaunchboxGame(id: 2, name: 'Pilotwings', cooperative: true),
];

List<String> lines(List<LaunchboxGame> games) => [for (final g in games) jsonEncode(g.toJson())];

void main() {
  late Directory tmp;
  late LaunchboxStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lb_store_');
    store = LaunchboxStore(Directory('${tmp.path}/launchbox'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('manifest', () {
    test('round trips through the file', () async {
      final m = LaunchboxManifest(etag: '"abc"', importedAt: DateTime.utc(2026, 11, 16, 12, 30), platforms: {snes, 'Sega Genesis'});
      await store.writeManifest(m);
      final back = await store.readManifest();
      expect(back, isNotNull);
      expect(back!.etag, '"abc"');
      expect(back.importedAt, DateTime.utc(2026, 11, 16, 12, 30));
      expect(back.platforms, {snes, 'Sega Genesis'});
    });

    test('toJson has the format, a UTC date and the platforms sorted', () {
      final m = LaunchboxManifest(etag: null, importedAt: DateTime.utc(2026, 1, 2, 3, 4, 5), platforms: {snes, 'Atari Lynx'});
      expect(m.toJson(), {
        'format': 1,
        'etag': null,
        'importedAt': '2026-01-02T03:04:05.000Z',
        'platforms': ['Atari Lynx', snes],
      });
    });

    test('the version is the ETag, else the import date', () {
      final at = DateTime.utc(2026, 11, 16, 12, 30);
      expect(LaunchboxManifest(etag: '"abc"', importedAt: at, platforms: const {}).version, '"abc"');
      expect(LaunchboxManifest(etag: null, importedAt: at, platforms: const {}).version, '2026-11-16T12:30:00.000Z');
    });

    test('another format or junk reads as null', () {
      expect(LaunchboxManifest.fromJson({'format': 2, 'etag': 'x', 'importedAt': '2026-01-02T03:04:05.000Z', 'platforms': []}), isNull);
      expect(LaunchboxManifest.fromJson({'format': 1, 'importedAt': 'yesterday', 'platforms': []}), isNull);
      expect(LaunchboxManifest.fromJson('manifest'), isNull);
    });

    test('a junk file reads as null', () async {
      await store.root.create(recursive: true);
      await File('${store.root.path}/manifest.json').writeAsString('{not json');
      expect(await store.readManifest(), isNull);
    });

    test('a missing file reads as null', () async {
      expect(await store.readManifest(), isNull);
    });
  });

  test('a platform written then decoded gives the same games', () async {
    await store.writePlatform(snes, games);
    expect(store.platformFile(snes).path, '${store.root.path}/super_nintendo_entertainment_system.json.gz');
    final bytes = await store.readPlatformBytes(snes);
    expect(bytes, isNotNull);
    expect(lines(LaunchboxStore.decodePlatform(bytes!)), lines(games));
  });

  test('a missing platform reads as null', () async {
    expect(await store.readPlatformBytes(snes), isNull);
  });

  test('a .tmp left by a crash does not break the next write or read', () async {
    await store.writePlatform(snes, games);
    await File('${store.platformFile(snes).path}.tmp').writeAsString('half a file');
    await File('${store.root.path}/manifest.json.tmp').writeAsString('{"form');

    // Still the last complete file before the next write.
    expect(lines(LaunchboxStore.decodePlatform((await store.readPlatformBytes(snes))!)), lines(games));

    await store.writePlatform(snes, games.take(1).toList());
    await store.writeManifest(LaunchboxManifest(etag: 'e', importedAt: DateTime.utc(2026), platforms: {snes}));
    expect(lines(LaunchboxStore.decodePlatform((await store.readPlatformBytes(snes))!)), lines(games.take(1).toList()));
    expect((await store.readManifest())!.etag, 'e');
  });

  test('a write that fails leaves the previous file whole', () async {
    await store.writePlatform(snes, games);
    final before = store.platformFile(snes).readAsBytesSync();
    // A directory where the temp file goes, so the write cannot finish.
    Directory('${store.platformFile(snes).path}.tmp').createSync();

    await expectLater(store.writePlatform(snes, games.take(1).toList()), throwsA(isA<FileSystemException>()));
    expect(store.platformFile(snes).readAsBytesSync(), before);
  });

  test('deleteAll removes the root', () async {
    await store.writePlatform(snes, games);
    await store.writeManifest(LaunchboxManifest(etag: 'e', importedAt: DateTime.utc(2026), platforms: {snes}));
    await store.deleteAll();
    expect(store.root.existsSync(), isFalse);
    // And again when there is nothing left to delete.
    await store.deleteAll();
  });
}
