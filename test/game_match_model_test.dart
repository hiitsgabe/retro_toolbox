import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

const _game = PackGame(
  id: 'snes/chrono-trigger',
  title: 'Chrono Trigger',
  dumps: [PackDump(name: 'Chrono Trigger (USA)', crc: '2D206BF7')],
);

void main() {
  test('checksum é a única confiança confirmada', () {
    expect(MatchTier.checksum.confidence, MatchConfidence.confirmed);
  });

  test('os dois tiers de nome confiáveis são prováveis, não confirmados', () {
    expect(MatchTier.exactName.confidence, MatchConfidence.likely);
    expect(MatchTier.canonicalName.confidence, MatchConfidence.likely);
  });

  test('fuzzy é palpite', () {
    expect(MatchTier.fuzzyName.confidence, MatchConfidence.guess);
  });

  test('o match expõe a confiança do próprio tier', () {
    const match = GameMatch(
      game: _game,
      tier: MatchTier.fuzzyName,
      sourceName: 'Chrono Triger (USA).zip',
      score: 93.5,
    );
    expect(match.confidence, MatchConfidence.guess);
    expect(match.score, 93.5);
    expect(match.dump, isNull);
  });
}
