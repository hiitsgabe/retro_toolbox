import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

PackGame _pg(String id, String title) => PackGame(id: id, title: title, dumps: const []);

MatchedSource _src(String filename, {MatchConfidence confidence = MatchConfidence.likely}) =>
    MatchedSource(filename: filename, sourceId: 'listing', confidence: confidence, size: 1024);

void main() {
  test('an entry with no source is unavailable', () {
    final entry = PackGridEntry(game: _pg('snes/crystal-vanguard', 'Crystal Vanguard'), sources: const []);

    expect(entry.hasSource, isFalse);
    expect(entry.sourceCount, 0);
  });

  test('an entry with at least one source is available', () {
    final entry = PackGridEntry(
      game: _pg('snes/crystal-vanguard', 'Crystal Vanguard'),
      sources: [_src('Crystal Vanguard (USA).zip')],
    );

    expect(entry.hasSource, isTrue);
    expect(entry.sourceCount, 1);
  });

  test('the selection key is pack-prefixed so it cannot collide with gameId', () {
    // `Game.gameId` and `PackGame.id` both start with a letter and hold a
    // slash; the prefix is what separates them.
    final entry = PackGridEntry(game: _pg('snes/crystal-vanguard', 'Crystal Vanguard'), sources: const []);

    expect(entry.selectionKey, 'pack:snes/crystal-vanguard');
  });

  test('an entry does not synthesize its own confidence from its sources', () {
    final entry = PackGridEntry(
      game: _pg('snes/crystal-vanguard', 'Crystal Vanguard'),
      sources: [
        _src('a.zip', confidence: MatchConfidence.confirmed),
        _src('b.zip', confidence: MatchConfidence.guess),
      ],
    );

    expect(entry.hasSource, isTrue);
    expect(entry.sourceCount, 2);
  });
}
