import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

const _game = PackGame(
  id: 'snes/crystal-vanguard',
  title: 'Crystal Vanguard',
  dumps: [PackDump(name: 'Crystal Vanguard (USA)', crc: '2D206BF7')],
);

void main() {
  test('checksum is the only confirmed confidence', () {
    expect(MatchTier.checksum.confidence, MatchConfidence.confirmed);
  });

  test('both reliable name tiers are likely, not confirmed', () {
    expect(MatchTier.exactName.confidence, MatchConfidence.likely);
    expect(MatchTier.canonicalName.confidence, MatchConfidence.likely);
  });

  test('fuzzy is a guess', () {
    expect(MatchTier.fuzzyName.confidence, MatchConfidence.guess);
  });

  test('match exposes the confidence of its own tier', () {
    const match = GameMatch(
      game: _game,
      tier: MatchTier.fuzzyName,
      sourceName: 'Crystal Vanguar (USA).zip',
      score: 93.5,
    );
    expect(match.confidence, MatchConfidence.guess);
    expect(match.score, 93.5);
    expect(match.dump, isNull);
  });
}
