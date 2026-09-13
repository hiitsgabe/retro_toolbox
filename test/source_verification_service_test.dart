import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_verification_service.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

/// Test pack CRCs, in the numeric form the central directory stores.
const crystalUsa = 0x2D206BF7;
const crystalJapan = 0xABCD1234;
const pixelEurope = 0xA31BEAD4;
const outsider = 0xDEADBEEF;

const crystalVanguard = 'snes/crystal-vanguard';

void main() {
  late PackMatcher matcher;
  final uri = Uri.parse('https://example/file.zip');

  setUp(() => matcher = PackMatcher(buildPack()));

  test('does not hit the network when the file is not a zip', () async {
    var calls = 0;
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: (u, r) async {
        calls++;
        throw StateError('should not have hit the network');
      },
    );

    final out = await service.verify(uri, 'Crystal Vanguard (USA).7z', crystalVanguard);

    expect(out, SourceVerification.impossible);
    expect(calls, 0);
  });

  test('an inner CRC that is a dump of this game', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)])).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.crcOk,
    );
  });

  test('any dump of the game matches, not only the named one', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', crystalJapan)])).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.crcOk,
    );
  });

  test('an inner CRC that belongs to another game is discarded', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', pixelEurope)])).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.crcDiscarded,
    );
  });

  test('an inner CRC that belongs to no game in the pack is discarded', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', outsider)])).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.crcDiscarded,
    );
  });

  test('a zip with no ROM inside disproves nothing', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([
        cdEntry('readme.txt', outsider),
        cdEntry('bonus.zip', outsider),
      ])).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.impossible,
    );
  });

  test('a server without Range support leaves verification impossible', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(
        buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]),
        status: 200,
      ).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.impossible,
    );
  });

  test('two short requests, not the whole file', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final service = SourceVerificationService(matcher: matcher, fetch: server.fetch);

    await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard);

    expect(server.asked.length, 2);
    expect(server.asked.first, 'bytes=-256');
  });
}
