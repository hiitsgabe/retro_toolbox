import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_index.dart';

PackGame _pg(String id, String dumpName) => PackGame(
      id: id,
      title: dumpName,
      dumps: [PackDump(name: dumpName)],
    );

PackMatcher _matcher() => PackMatcher(MetadataPack(
      pack: 'snes',
      system: 'Super Nintendo',
      built: '2026-01-01',
      games: [
        _pg('snes/crystal-vanguard', 'Crystal Vanguard (USA)'),
        _pg('snes/super-vectron', 'Super Vectron (USA)'),
        _pg('snes/emberfall', 'Emberfall (USA)'),
      ],
    ));

SourceFile _f(String filename, {int size = 1024}) =>
    (filename: filename, sourceId: 'listing', size: size, url: null);

void main() {
  test('each matched file joins its game list', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Crystal Vanguard (USA).zip'),
      _f('Super Vectron (USA).zip'),
    ]);

    expect(index.sourcesFor('snes/crystal-vanguard').single.filename, 'Crystal Vanguard (USA).zip');
    expect(index.sourcesFor('snes/super-vectron').single.filename, 'Super Vectron (USA).zip');
    expect(index.hasSource('snes/emberfall'), isFalse);
  });

  test('two versions of one game stay together, in listing order', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Crystal Vanguard (USA).zip'),
      _f('Crystal Vanguard (Europe).zip'),
    ]);

    expect(
      index.sourcesFor('snes/crystal-vanguard').map((s) => s.filename),
      ['Crystal Vanguard (USA).zip', 'Crystal Vanguard (Europe).zip'],
    );
  });

  test('each source confidence comes from that file tier', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Crystal Vanguard (USA).zip'),   // exact name
      _f('Crystal Vanguar (USA).zip'),    // typo, falls into fuzzy
    ]);

    final sources = index.sourcesFor('snes/crystal-vanguard');
    expect(sources.map((s) => s.confidence),
        [MatchConfidence.likely, MatchConfidence.guess]);
  });

  test('size and source id survive the crossing', () {
    final index = SourceIndex.build(_matcher(), [_f('Crystal Vanguard (USA).zip', size: 4096)]);

    final source = index.sourcesFor('snes/crystal-vanguard').single;
    expect(source.size, 4096);
    expect(source.sourceId, 'listing');
  });

  test('a file that matches no game becomes unmatched', () {
    final index = SourceIndex.build(_matcher(), [_f('Unknown Game (USA).zip')]);

    expect(index.unmatched, ['Unknown Game (USA).zip']);
    expect(index.matchedGameCount, 0);
  });

  test('non-ROM files are ignored, not counted as unmatched', () {
    final index = SourceIndex.build(_matcher(), [
      _f('readme.txt'),
      _f('Crystal Vanguard (USA).zip'),
    ]);

    expect(index.unmatched, isEmpty);
    expect(index.matchedGameCount, 1);
  });

  test('a game with no source returns an empty list, never null', () {
    final index = SourceIndex.build(_matcher(), const []);

    expect(index.sourcesFor('snes/emberfall'), isEmpty);
    expect(index.sourcesFor('id/that/does/not/exist'), isEmpty);
  });
}
