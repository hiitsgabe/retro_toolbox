import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_group_model.dart';
import 'package:retro_toolbox/services/game_groups.dart';

import 'game_groups_support.dart';

List<String> _labels(GameGroup g) => [for (final v in g.versions) v.label];
List<String> _titles(Iterable<GameGroup> gs) => [for (final g in gs) g.title];

void main() {
  test('Metal Gear Solid: ten versions of two discs each, six demos as extras', () {
    final g = buildGameGroups(psxGames(['Metal Gear Solid'])).single;
    expect(g.title, 'Metal Gear Solid');
    expect(g.versions, hasLength(10));
    expect(g.versions.every((v) => v.discs.length == 2), isTrue);
    expect(_labels(g), containsAll(['USA · 2 discs', 'USA · Rev 1 · 2 discs', 'Japan · 2 discs', 'Japan, Asia · Premium Package · 2 discs']));
    expect(g.extras, hasLength(6));
    expect([for (final e in g.extras) extraLabel(e)], contains('USA · Demo'));
  });

  test('Spyro the Dragon: four versions, two betas and three demos as extras', () {
    final g = buildGameGroups(psxGames(['Spyro the Dragon'])).single;
    expect(_labels(g), unorderedEquals(['Europe, Australia · En,Fr,De,Es,It', 'Japan', 'Japan, Asia · Shokai Genteiban', 'USA']));
    expect(g.extras, hasLength(5));
  });

  test('Gran Turismo 2: a bonus CD and beta discs are extras', () {
    final g = buildGameGroups(psxGames(['Gran Turismo 2'])).single;
    expect(g.versions, hasLength(8));
    expect(g.extras, hasLength(5));
    expect([for (final e in g.extras) e.title], contains('Gran Turismo 2 (France) (Un CD Bonus).zip'));
  });

  test('Final Fantasy VII and Final Fantasy VII International are two games; the Perfect Guide is disc 4', () {
    final groups = buildGameGroups(psxGames(['Final Fantasy VII', 'Final Fantasy VII International']));
    expect(_titles(groups), ['Final Fantasy VII', 'Final Fantasy VII International']);
    expect(groups.first.versions, hasLength(7));
    expect(groups.first.extras, hasLength(2));
    expect(_labels(groups.last), ['Japan · 4 discs']);
  });

  test('Arc the Lad Collection: one box with its five games, each with its own discs and betas', () {
    final box = buildGameGroups(psxGamesStartingWith('Arc the Lad Collection - ')).single;
    expect(box.title, 'Arc the Lad Collection');
    expect(box.isBoxSet, isTrue);
    expect([for (final m in box.members) memberLabel(box, m)],
        ['Arc Arena - Monster Tournament', 'Arc the Lad', 'Arc the Lad II', 'Arc the Lad III', 'The Making of Arc the Lad']);
    expect(_labels(box.members[3]), ['USA · 2 discs']);
    expect([for (final m in box.members) m.extras.length], [1, 1, 1, 0, 1]);
  });

  test('SuperLite 1500 Series is a label, not a box: its games stay apart', () {
    final groups = buildGameGroups(psxGamesStartingWith('SuperLite 1500 Series - '));
    expect(groups, hasLength(2));
    expect(groups.any((g) => g.isBoxSet), isFalse);
  });

  test('discs named apart from their edition stay one version (Chou Kousoku Gran Doll)', () {
    final g = buildGameGroups(psxGames(['Chou Kousoku Gran Doll'])).single;
    expect(_labels(g), unorderedEquals(['Japan · Premium Edition · 2 discs', 'Japan']));
  });

  test('a game known only from a demo is a group with no version', () {
    final g = buildGameGroups(psxGames(['Ancient Roman Extra'])).single;
    expect(g.versions, isEmpty);
    expect(g.extras, hasLength(1));
    expect(g.title, 'Ancient Roman Extra');
  });

  test('LaunchBox joins the titles of one game across regions; without it they stay apart', () {
    final bases = ['Crash Bandicoot - Warped', 'Crash Bandicoot 3 - Warped'];
    final joined = buildGameGroups(psxGames(bases, launchboxId: 7));
    expect(joined, hasLength(1));
    expect(joined.single.title, 'Crash Bandicoot - Warped');
    expect(joined.single.versions, hasLength(2));
    expect(joined.single.extras, hasLength(5));
    expect(buildGameGroups(psxGames(bases)), hasLength(2));
  });

  test('a box keeps its games even when LaunchBox matches one to another title', () {
    final games = [
      ...psxGamesStartingWith('Arc the Lad Collection - ', launchboxId: 9),
      psxGame('Arc the Lad II (Japan)', launchboxId: 9),
    ];
    final groups = buildGameGroups(games);
    expect(_titles(groups), ['Arc the Lad Collection', 'Arc the Lad II']);
    expect(groups.first.members, hasLength(5));
  });

  test('revisions compare as numbers and letters, none first', () {
    expect(compareRevisions('', '1'), lessThan(0));
    expect(compareRevisions('2', '10'), lessThan(0));
    expect(compareRevisions('10', '2'), greaterThan(0));
    expect(compareRevisions('A', 'B'), lessThan(0));
    expect(compareRevisions('1.1', '1.10'), lessThan(0));
    expect(compareRevisions('1', '1'), 0);
  });

  test('the main version: the region order, then the newest revision, then the plain one over an Alt', () {
    final tekken = buildGameGroups(psxGames(['Tekken 3'])).single;
    expect(pickMainVersion(tekken.versions, defaultRegionOrder)!.first.title, 'Tekken 3 (USA).zip');
    expect(pickMainVersion(tekken.versions, ['Europe'])!.first.title, 'Tekken 3 (Europe, Australia).zip');
    expect(pickMainVersion(tekken.versions, ['Japan'])!.first.title, 'Tekken 3 (Japan) (Rev 1).zip');
    final mgs = buildGameGroups(psxGames(['Metal Gear Solid'])).single;
    expect(pickMainVersion(mgs.versions, defaultRegionOrder)!.first.title, 'Metal Gear Solid (USA) (Disc 1) (Rev 1).zip');
    expect(pickMainVersion(const [], defaultRegionOrder), isNull);
  });
}
