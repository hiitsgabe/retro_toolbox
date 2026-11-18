import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/filtering_service.dart';
import 'package:retro_toolbox/services/game_groups.dart';

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

  // The usual main version (USA) fails the filter; the group still shows, by
  // the version that passes.
  test('a group shows by any version that passes, even when the usual main one does not', () {
    final r = _run([psxGame('Game (USA) (Debug)'), psxGame('Game (Japan)')], filter: _open.copyWith(modifications: {'none'}));
    expect([for (final g in r.games) g.title], ['Game (Japan).zip']);
  });

  test('the search finds a game by any of its titles', () {
    final r = _run(psxGames(['Metal Gear Solid', 'Spyro the Dragon']), text: 'Premium Package');
    expect([for (final g in r.games) g.group!.title], ['Metal Gear Solid']);
  });

  // The search finds the group, it does not choose the version.
  test('a search by another version or an extra still shows the main version', () {
    final mgs = _run(psxGames(['Metal Gear Solid', 'Spyro the Dragon']), text: 'Premium Package');
    expect(_entry(mgs, 'Metal Gear Solid').title, 'Metal Gear Solid (USA) (Disc 1) (Rev 1).zip');
    final crash = _run(psxGames(['Crash Bandicoot - Warped', 'Metal Gear Solid', 'Tekken 3']), text: '(France) (Demo)');
    expect([for (final g in crash.games) g.title], ['Tekken 3 (USA).zip']);
  });

  test('entries are sorted by name, not by catalog order', () {
    final r = _run(psxGames(['Metal Gear Solid', 'Spyro the Dragon', 'Tekken 3']).reversed.toList());
    expect([for (final g in r.games) g.group!.title], ['Metal Gear Solid', 'Spyro the Dragon', 'Tekken 3']);
  });

  // Europe before Japan and World before Japan, whatever the names' lengths say.
  test('without a region filter, the default region order picks the main version', () {
    final r = _run([psxGame('Euro (Japan)'), psxGame('Euro (Europe)'), psxGame('Wide (Japan)'), psxGame('Wide (World)')]);
    expect([for (final g in r.games) g.title], ['Euro (Europe).zip', 'Wide (World).zip']);
  });

  test('a version the user has is the main version, before the region order', () {
    final games = [psxGame('Game (USA)'), psxGame('Game (Europe)')];
    String title({Set<String>? owned, CatalogFilter filter = _open}) => FilteringService.filterAndPaginate(FilterInput(
            games: games, filterText: '', filter: filter, limit: 10, groupVersions: true, ownedGameIds: owned))
        .games
        .single
        .title;
    final europe = games[1].gameId;
    expect(title(), 'Game (USA).zip');
    expect(title(owned: {europe}), 'Game (Europe).zip');
    expect(title(owned: {games[0].gameId, europe}), 'Game (USA).zip', reason: 'both owned: the region order breaks the tie');
    expect(title(owned: {europe}, filter: _open.copyWith(regions: {'USA'})), 'Game (USA).zip', reason: 'the region filter still decides what shows');
  });

  test('a version is owned when any of its discs is', () {
    final games = psxGames(['Metal Gear Solid']);
    final eu = games.firstWhere((g) => g.title == 'Metal Gear Solid (Europe) (Disc 2).zip');
    final r = FilteringService.filterAndPaginate(
        FilterInput(games: games, filterText: '', filter: _open, limit: 10, groupVersions: true, ownedGameIds: {eu.gameId}));
    expect(r.games.single.title, startsWith('Metal Gear Solid (Europe) (Disc 1)'));
  });

  test('groups built beforehand give the same entries as groups built in the run', () {
    final games = psxAll();
    final built = _run(games, filter: const CatalogFilter());
    final given = FilteringService.filterAndPaginate(FilterInput(
        games: games, filterText: '', filter: const CatalogFilter(), limit: 1000, groupVersions: true, groups: buildGameGroups(games)));
    expect([for (final g in given.games) g.title], [for (final g in built.games) g.title]);
    expect(given.totalCount, built.totalCount);
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
