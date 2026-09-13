import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

import 'support/pack_fixture.dart';

void main() {
  late PackMatcher matcher;

  setUp(() => matcher = PackMatcher(buildPack()));

  group('tier 1, exact name', () {
    test('matches the dump name letter for letter', () {
      final m = matcher.match('Crystal Vanguard (USA)');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.exactName);
      expect(m.game.id, 'snes/crystal-vanguard');
      expect(m.sourceName, 'Crystal Vanguard (USA)');
    });

    test('matches ignoring the file extension', () {
      expect(matcher.match('Crystal Vanguard (USA).zip')?.tier, MatchTier.exactName);
      expect(matcher.match('Crystal Vanguard (USA).sfc')?.tier, MatchTier.exactName);
    });

    test('matches ignoring case, underscore and punctuation', () {
      final m = matcher.match('crystal_vanguard_(usa).ZIP');
      expect(m?.tier, MatchTier.exactName);
      expect(m?.game.id, 'snes/crystal-vanguard');
    });

    test('the exact tier returns the concrete dump, with that region CRC', () {
      expect(matcher.match('Crystal Vanguard (USA)')?.dump?.crc, '2D206BF7');
      expect(matcher.match('Crystal Vanguard (Japan)')?.dump?.crc, 'ABCD1234');
    });

    test('returns null when nothing matches at any tier', () {
      expect(matcher.match('Something That Does Not Exist (USA).zip'), isNull);
    });
  });

  group('tier 2, canonical title', () {
    test('matches when only region and revision differ', () {
      final m = matcher.match('Crystal Vanguard (Europe) (Rev 1).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.canonicalName);
      expect(m.game.id, 'snes/crystal-vanguard');
    });

    test('matches when the article is inverted on both sides', () {
      // The dump is "Zxia Gztqfevzem, The (Japan)" and the source writes the
      // article up front; `canon` brings both to the same form.
      final m = matcher.match('The Zxia Gztqfevzem (Japan).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.canonicalName);
      expect(m.game.id, 'snes/the-zxia-gztqfevzem');
    });

    test('the canonical tier resolves the game not the version, so it carries no dump', () {
      expect(matcher.match('Crystal Vanguard (Europe) (Rev 1).zip')?.dump, isNull);
    });

    test('the exact tier beats the canonical when both would match', () {
      // "Super Pixel World (Europe)" matches exact on the second dump and would
      // match canonical on the whole game; exact must win, since only it knows
      // which region it is.
      final m = matcher.match('Super Pixel World (Europe).sfc');
      expect(m!.tier, MatchTier.exactName);
      expect(m.dump?.crc, 'A31BEAD4');
    });
  });

  group('tier 3, similarity', () {
    test('matches above the cutoff', () {
      // "Copper Bolt" against "CopperBolt", one space apart: 97.56.
      final m = matcher.match('Copper Bolt Grappling (USA).zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.fuzzyName);
      expect(m.game.id, 'snes/copperbolt-grappling');
    });

    test('does not match below the cutoff', () {
      // 47.46 against "crystal vanguard".
      expect(
        matcher.match('Crystal Vanguard 2 - Ressurection of the Ancients (USA).zip'),
        isNull,
      );
    });

    test('the score lands between the cutoff and a hundred', () {
      final m = matcher.match('Copper Bolt Grappling (USA).zip')!;
      expect(m.score, greaterThanOrEqualTo(fuzzyCutoff));
      expect(m.score, lessThan(100));
    });

    test('picks the highest-scoring candidate, not the first in the bucket', () {
      // The "reso" bucket has "reso 4 kkesv hq" (90.32) before
      // "reso 4 kkesv hq h" (96.97); the second is the right one.
      final m = matcher.match('Reso4 Kkesv HQ-H (Japan).zip');
      expect(m!.tier, MatchTier.fuzzyName);
      expect(m.game.id, 'snes/reso-4-kkesv-hq-h');
    });

    test('tier 3 errs, and the model calls it a guess', () {
      // MK2 resolves to MK3 at 95.24: the trailing digit is exactly what edit
      // distance cannot see.
      final m = matcher.match('Duo Vector Recoil MK2 (Europe) (Unl) [b].zip');
      expect(m!.game.id, 'snes/duo-vector-recoil-mk3');
      expect(m.confidence, MatchConfidence.guess);
    });

    test('scans the whole pack when the first-token bucket is missing', () {
      // "ropperbolt" falls in the "ropp" bucket, which does not exist; without
      // the fallback the 95.00 match against "copperbolt grappling" would be lost.
      final m = matcher.match('Ropperbolt Grappling.zip');
      expect(m!.game.id, 'snes/copperbolt-grappling');
      expect(m.tier, MatchTier.fuzzyName);
    });
  });

  group('checksum axis', () {
    test('matches the CRC uppercased and brings the right dump', () {
      final m = matcher.matchCrc('A31BEAD4', sourceName: 'anything.zip');
      expect(m, isNotNull);
      expect(m!.tier, MatchTier.checksum);
      expect(m.confidence, MatchConfidence.confirmed);
      expect(m.game.id, 'snes/super-pixel-world');
      expect(m.dump?.name, 'Super Pixel World (Europe)');
      expect(m.sourceName, 'anything.zip');
    });

    test('matches the CRC lowercased', () {
      expect(matcher.matchCrc('a31bead4')?.game.id, 'snes/super-pixel-world');
    });

    test('returns null for a CRC not in the pack', () {
      expect(matcher.matchCrc('DEADBEEF'), isNull);
    });
  });
}
