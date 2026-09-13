import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

import 'support/pack_fixture.dart';

void main() {
  late Directory tmp;
  late PackMatcher matcher;
  late List<String> reads;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_identity_test');
    matcher = PackMatcher(buildPack());
    reads = [];
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File write(String name) =>
      File('${tmp.path}/$name')..writeAsStringSync('content');

  /// Service with a fake CRC, so the test controls what the disk "has" and
  /// counts how many times a file was read.
  LocalIdentityService serviceReturning(String crc) => LocalIdentityService(
        matcher: matcher,
        crcOfFile: (file) async {
          reads.add(file.path);
          return crc;
        },
      );

  test('accepts the exact name without touching the file', () async {
    final service = serviceReturning('B19ED489');
    final m = await service.identify(write('Crystal Vanguard (USA).sfc'));
    expect(m!.tier, MatchTier.exactName);
    expect(m.game.id, 'snes/crystal-vanguard');
    expect(reads, isEmpty);
  });

  test('accepts the canonical name without touching the file', () async {
    final service = serviceReturning('B19ED489');
    final m = await service.identify(write('The Zxia Gztqfevzem.sfc'));
    expect(m!.tier, MatchTier.canonicalName);
    expect(m.game.id, 'snes/the-zxia-gztqfevzem');
    expect(reads, isEmpty);
  });

  test('a fuzzy guess computes the CRC and corrects the game', () async {
    // The name looks like CopperBolt Grappling, but the bytes are Duo Vector
    // Recoil MK3; the CRC wins.
    final service = serviceReturning('11112222');
    final file = write('Copper Bolt Grappling (USA).sfc');
    expect(matcher.match('Copper Bolt Grappling (USA).sfc')!.tier,
        MatchTier.fuzzyName);
    final m = await service.identify(file);
    expect(m!.tier, MatchTier.checksum);
    expect(m.game.id, 'snes/duo-vector-recoil-mk3');
    expect(reads, [file.path]);
  });

  test('with no name guess at all, the CRC resolves on its own', () async {
    final service = serviceReturning('A31BEAD4');
    final file = write('unknown rom 0042.sfc');
    expect(matcher.match('unknown rom 0042.sfc'), isNull);
    final m = await service.identify(file);
    expect(m!.tier, MatchTier.checksum);
    expect(m.game.id, 'snes/super-pixel-world');
  });

  test('a CRC not in the pack leaves the name guess untouched',
      () async {
    final service = serviceReturning('DEADBEEF');
    final m = await service.identify(write('Copper Bolt Grappling (USA).sfc'));
    expect(m!.tier, MatchTier.fuzzyName);
    expect(m.game.id, 'snes/copperbolt-grappling');
  });

  test('does not compute the CRC of a container, since it would not be comparable', () async {
    final service = serviceReturning('11112222');
    final m = await service.identify(write('Copper Bolt Grappling (USA).zip'));
    expect(m!.tier, MatchTier.fuzzyName);
    expect(m.game.id, 'snes/copperbolt-grappling');
    expect(reads, isEmpty);
  });

  test('the cache avoids a second read of the same file', () async {
    final service = serviceReturning('11112222');
    final file = write('Copper Bolt Grappling (USA).sfc');
    await service.identify(file);
    await service.identify(file);
    expect(reads, hasLength(1));
    expect(service.cache.values, ['11112222']);
  });
}
