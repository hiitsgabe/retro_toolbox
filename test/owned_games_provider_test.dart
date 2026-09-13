import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/owned_games_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

const _target = PackTarget('snes', 'Super Nintendo');

final _pack = MetadataPack(
  pack: 'snes',
  system: 'Super Nintendo',
  built: '2026-01-01',
  games: [
    PackGame(
      id: 'snes/crystal-vanguard',
      title: 'Crystal Vanguard',
      dumps: [PackDump(name: 'Crystal Vanguard (USA)', crc: 'AABBCCDD')],
    ),
    PackGame(
      id: 'snes/super-vectron',
      title: 'Super Vectron',
      dumps: [PackDump(name: 'Super Vectron (Japan, USA)')],
    ),
  ],
);

/// Fixed CRC on purpose: `FFFFFFFF` is not in the pack, so the CRC axis never
/// matches and each test measures exactly the name axis it claims to.
LocalIdentityService _service() => LocalIdentityService(
      matcher: PackMatcher(_pack),
      crcOfFile: (_) async => 'FFFFFFFF',
    );

Future<Directory> _dir() async {
  final dir = await Directory.systemTemp.createTemp('owned_games_test');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

Future<File> _file(Directory dir, String name) async {
  final file = File(p.join(dir.path, name));
  await file.parent.create(recursive: true);
  await file.writeAsString('rom');
  return file;
}

ProviderContainer _container({
  required String? libraryDir,
  PackTarget? target = _target,
  LocalIdentityService? service,
  bool withService = true,
}) {
  final container = ProviderContainer(
    overrides: [
      packTargetProvider.overrideWithValue(target),
      libraryDirProvider.overrideWithValue(libraryDir),
      if (target != null)
        localIdentityServiceProvider(target).overrideWith(
          (ref) => withService ? (service ?? _service()) : null,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('no selected console yields an empty set', () async {
    final container = _container(libraryDir: null, target: null);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('no pack means no identity, and the set is empty', () async {
    final dir = await _dir();
    await _file(dir, 'Crystal Vanguard (USA).sfc');
    final container = _container(libraryDir: dir.path, withService: false);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a missing directory does not crash the scan', () async {
    final container = _container(libraryDir: p.join(Directory.systemTemp.path, 'does_not_exist_at_all'));

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a ROM matched by name enters the set', () async {
    final dir = await _dir();
    await _file(dir, 'Crystal Vanguard (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), {'snes/crystal-vanguard'});
  });

  test('non-ROM files are ignored', () async {
    final dir = await _dir();
    await _file(dir, 'Crystal Vanguard (USA).txt');
    await _file(dir, 'Super Vectron (Japan, USA).nfo');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a ROM that matches nothing stays out', () async {
    final dir = await _dir();
    await _file(dir, 'A Game That Does Not Exist (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a ROM extracted into a subfolder counts too', () async {
    final dir = await _dir();
    await _file(dir, p.join('Super Vectron (Japan, USA)', 'Super Vectron (Japan, USA).sfc'));
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), {'snes/super-vectron'});
  });

  test('a similarity-only match does not count as downloaded', () async {
    final dir = await _dir();
    // Tier 3: ratio passes 90 so the matcher returns a fuzzyName, good enough
    // to suggest but not to mark as owned.
    await _file(dir, 'Crystal Vanguar (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });
}
