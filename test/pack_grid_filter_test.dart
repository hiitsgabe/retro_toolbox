import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';

PackGridEntry _e(String title, {bool withSource = true, String? id}) => PackGridEntry(
      game: PackGame(id: id ?? 'snes/${title.toLowerCase()}', title: title, dumps: const []),
      sources: withSource
          ? [const MatchedSource(filename: 'a.zip', sourceId: 'listing', confidence: MatchConfidence.likely, size: 1)]
          : const [],
    );

void main() {
  test('an empty query returns everything', () {
    final out = filterPackEntries([_e('Super Vectron'), _e('Crystal Vanguard')], '');

    expect(out.length, 2);
  });

  test('output is sorted by title, not by pack order', () {
    final out = filterPackEntries([_e('Super Vectron'), _e('Crystal Vanguard'), _e('Emberfall')], '');

    expect(out.map((e) => e.game.title), ['Crystal Vanguard', 'Emberfall', 'Super Vectron']);
  });

  test('the search ignores case and accents', () {
    final out = filterPackEntries([_e('Prismón Red'), _e('Super Vectron')], 'prismon');

    expect(out.single.game.title, 'Prismón Red');
  });

  test('the search matches a substring in the middle of the title', () {
    final out = filterPackEntries([_e('The Legend of Kaelis'), _e('Super Vectron')], 'kaelis');

    expect(out.single.game.title, 'The Legend of Kaelis');
  });

  test('a search with no results returns an empty list', () {
    final out = filterPackEntries([_e('Super Vectron')], 'cryptmanor');

    expect(out, isEmpty);
  });

  test('a sourceless game still shows, because the grid shows everything', () {
    final out = filterPackEntries([_e('Super Vectron', withSource: false)], '');

    expect(out.single.hasSource, isFalse);
  });

  test('equal titles sort stably, broken by id', () {
    // Every other sort test uses distinct titles, so the tie-break branch never
    // runs without this case; both call orders must yield the same output.
    final usa = _e('Fabled Frontier', id: 'snes/ff-usa');
    final eur = _e('Fabled Frontier', id: 'snes/ff-eur');

    expect(filterPackEntries([usa, eur], '').map((e) => e.game.id), ['snes/ff-eur', 'snes/ff-usa']);
    expect(filterPackEntries([eur, usa], '').map((e) => e.game.id), ['snes/ff-eur', 'snes/ff-usa']);
  });

  test('whitespace around the query does not count', () {
    final out = filterPackEntries([_e('Super Vectron')], '  vectron  ');

    expect(out.length, 1);
  });

  test('selection returns entries in list order, not in the order they were checked', () {
    final entries = [_e('Crystal Vanguard'), _e('Emberfall'), _e('Super Vectron')];

    final out = entriesForSelection(entries, {entries[2].selectionKey, entries[0].selectionKey});

    expect(out.map((e) => e.game.title), ['Crystal Vanguard', 'Super Vectron']);
  });

  test('a key no longer in the pack is ignored, without throwing', () {
    expect(entriesForSelection([_e('Crystal Vanguard')], {'pack:snes/game-that-vanished'}), isEmpty);
  });

  test('a source-mode key brings back no pack entry', () {
    expect(entriesForSelection([_e('Crystal Vanguard')], {'snes/Crystal Vanguard (USA).zip'}), isEmpty);
  });

  test('in pack mode only pack-prefixed keys count', () {
    final out = selectionKeysFor(
      {'pack:snes/crystal-vanguard', 'snes/Crystal Vanguard (USA).zip'},
      pack: true,
    );

    expect(out, {'pack:snes/crystal-vanguard'});
  });

  test('in source mode only unprefixed keys count', () {
    final out = selectionKeysFor(
      {'pack:snes/crystal-vanguard', 'snes/Crystal Vanguard (USA).zip'},
      pack: false,
    );

    expect(out, {'snes/Crystal Vanguard (USA).zip'});
  });

  test('an empty selection returns an empty set in both modes', () {
    expect(selectionKeysFor(const {}, pack: true), isEmpty);
    expect(selectionKeysFor(const {}, pack: false), isEmpty);
  });
}
