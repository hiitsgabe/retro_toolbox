import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/filtering_service.dart';

import 'game_groups_support.dart';

const _open = CatalogFilter(regions: {}, dumpQualities: {}, romTypes: {}, modifications: {}, distributionTypes: {});

FilterResult _run(List<Game> games, {CatalogFilter filter = _open, String text = '', bool group = true, int skip = 0, int limit = 1000}) =>
    FilteringService.filterAndPaginate(FilterInput(games: games, filterText: text, filter: filter, skip: skip, limit: limit, groupVersions: group));

Game _entry(FilterResult r, String groupTitle) => r.games.singleWhere((g) => g.group!.title == groupTitle);

void main() {
  test('one entry per game: the main version, its discs and its group', () {
    final r = _run(psxGames(['Metal Gear Solid', 'Spyro the Dragon', 'Tekken 3', 'Ancient Roman Extra']));
    expect(r.totalCount, 4);
    final mgs = _entry(r, 'Metal Gear Solid');
    expect(mgs.title, 'Metal Gear Solid (USA) (Disc 1) (Rev 1).zip');
    expect(mgs.discs, hasLength(2));
    expect(mgs.group!.versions, hasLength(10));
  });

  test('with the default filter, the games that have a plain USA version', () {
    final r = _run(psxAll(), filter: const CatalogFilter());
    expect({for (final g in r.games) g.group!.title}, {
      'Arc the Lad Collection',
      'Crash Bandicoot - Warped',
      'Final Fantasy VII',
      'Gran Turismo 2',
      'Metal Gear Solid',
      'Rival Schools - United by Fate',
      'Spyro the Dragon',
      'Syphon Filter 2',
      'Tekken 3',
    });
  });

  test('a region filter picks the main version in that region', () {
    final r = _run(psxGames(['Metal Gear Solid', 'Spyro the Dragon', 'Tekken 3']), filter: _open.copyWith(regions: {'Europe'}));
    expect(_entry(r, 'Tekken 3').title, 'Tekken 3 (Europe, Australia).zip');
    expect(_entry(r, 'Spyro the Dragon').title, 'Spyro the Dragon (Europe, Australia) (En,Fr,De,Es,It).zip');
    expect(_entry(r, 'Metal Gear Solid').title, 'Metal Gear Solid (Europe) (Disc 1).zip');
  });

  test('a region filter hides the games with no version in it, and the first chosen region wins', () {
    final games = [psxGame('Only Japan (Japan)'), psxGame('Both (USA)'), psxGame('Both (Japan)')];
    final jp = _run(games, filter: _open.copyWith(regions: {'Japan'}));
    expect([for (final g in jp.games) g.title], ['Both (Japan).zip', 'Only Japan (Japan).zip']);
    final both = _run(games, filter: _open.copyWith(regions: {'Japan', 'USA'}));
    expect(_entry(both, 'Both').title, 'Both (Japan).zip');
    expect(both.totalCount, 2);
  });

  test('another filter passes a group when any of its versions passes', () {
    final games = [psxGame('Game (USA) (Beta)'), psxGame('Game (Japan)')];
    final r = _run(games, filter: _open.copyWith(romTypes: {'normal'}));
    expect(r.games.single.title, 'Game (Japan).zip');
  });

  test('the search finds a game by any of its titles', () {
    final r = _run(psxGames(['Metal Gear Solid', 'Spyro the Dragon']), text: 'Premium Package');
    expect([for (final g in r.games) g.group!.title], ['Metal Gear Solid']);
  });

  test('sorting, the count and the pages are of entries, not files', () {
    final games = psxGames(['Metal Gear Solid', 'Spyro the Dragon', 'Tekken 3']);
    final all = _run(games);
    expect(all.totalCount, 3);
    expect([for (final g in all.games) g.group!.title], ['Metal Gear Solid', 'Spyro the Dragon', 'Tekken 3']);
    final page = _run(games, skip: 1, limit: 1);
    expect([for (final g in page.games) g.group!.title], ['Spyro the Dragon']);
    expect((page.totalCount, page.hasMore), (3, true));
    final last = _run(games, skip: 2, limit: 1);
    expect((last.games.length, last.hasMore), (1, false));
  });

  test('grouping off: every file is an entry, every revision included', () {
    final games = psxAll();
    final r = _run(games, group: false);
    expect(r.totalCount, games.length);
    final titles = {for (final g in r.games) g.title};
    expect(titles, containsAll(['Final Fantasy VII (Spain) (Disc 1).zip', 'Final Fantasy VII (Spain) (Disc 1) (Rev 1).zip']));
  });

  test('a box set is one entry named after the box, with no disc set of its own', () {
    final r = _run(psxGamesStartingWith('Arc the Lad Collection - '));
    final box = r.games.single;
    expect(box.displayTitle, 'Arc the Lad Collection');
    expect(box.discs, isEmpty);
    expect(box.group!.isBoxSet, isTrue);
  });
}
