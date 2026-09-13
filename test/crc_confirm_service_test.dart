import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/crc_confirm_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

/// CRCs of the test pack, in the numeric form the central directory stores.
const crystalUsa = 0x2D206BF7;
const smwEurope = 0xA31BEAD4;

void main() {
  late PackMatcher matcher;
  final uri = Uri.parse('https://example/file.zip');

  setUp(() => matcher = PackMatcher(buildPack()));

  CrcConfirmService serving(Uint8List zip) => CrcConfirmService(
        matcher: matcher,
        fetch: FakeRangeServer(zip).fetch,
      );

  test('skips the network when the filename does not end in .zip', () async {
    var calls = 0;
    final service = CrcConfirmService(
      matcher: matcher,
      fetch: (u, r) async {
        calls++;
        throw StateError('should not have gone to the network');
      },
    );
    final byName = matcher.match('Crystal Vanguard (USA).sfc');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).sfc', byName);
    expect(calls, 0);
    expect(out, same(byName));
  });

  test('confirms the name guess when the CRC points to the same game', () async {
    final service = serving(
        buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final byName = matcher.match('Crystal Vanguard (USA).zip');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).zip', byName);
    expect(out!.game.id, 'snes/crystal-vanguard');
    expect(out.tier, MatchTier.checksum);
    expect(out.confidence, MatchConfidence.confirmed);
    expect(out.dump?.name, 'Crystal Vanguard (USA)');
  });

  test('corrects the name guess when the CRC points to a different game', () async {
    // The file is named Crystal Vanguard but contains Super Pixel World.
    // The name lies; the CRC does not.
    final service = serving(
        buildZip([cdEntry('rom.sfc', smwEurope)]));
    final byName = matcher.match('Crystal Vanguard (USA).zip');
    expect(byName!.game.id, 'snes/crystal-vanguard');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).zip', byName);
    expect(out!.game.id, 'snes/super-pixel-world');
    expect(out.tier, MatchTier.checksum);
    expect(out.dump?.name, 'Super Pixel World (Europe)');
  });

  test('keeps the name match when the server does not support Range', () async {
    final service = CrcConfirmService(
      matcher: matcher,
      fetch: FakeRangeServer(
        buildZip([cdEntry('rom.sfc', smwEurope)]),
        status: 200,
      ).fetch,
    );
    final byName = matcher.match('Crystal Vanguard (USA).zip');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).zip', byName);
    expect(out, same(byName));
  });

  test('keeps the name match when the zip contains two different games',
      () async {
    final service = serving(buildZip([
      cdEntry('Crystal Vanguard (USA).sfc', crystalUsa),
      cdEntry('Super Pixel World (Europe).sfc', smwEurope),
    ]));
    final byName = matcher.match('Crystal Vanguard (USA).zip');
    final out = await service.confirm(uri, 'Crystal Vanguard (USA).zip', byName);
    expect(out, same(byName));
  });

  test('ignores non-ROM entries and decides by the single ROM', () async {
    // Without the extension filter, bonus.zip would carry the Super Pixel World
    // CRC, produce two games, and the zip would be discarded as inconclusive.
    final service = serving(buildZip([
      cdEntry('readme.txt', 0x00000009),
      cdEntry('bonus.zip', smwEurope),
      cdEntry('Crystal Vanguard (USA).sfc', crystalUsa),
    ]));
    final byName = matcher.match('random thing.zip');
    expect(byName, isNull);
    final out = await service.confirm(uri, 'random thing.zip', byName);
    expect(out!.game.id, 'snes/crystal-vanguard');
    expect(out.tier, MatchTier.checksum);
    expect(out.sourceName, 'random thing.zip');
  });
}
