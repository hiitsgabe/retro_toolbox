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

  // Known limitation: the USA Arcade Mode and Simulation Mode files carry no
  // disc number in their names, so they stay separate versions.
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

  test('a game whose name holds tags mid-title keeps them in its title (Euro Demo, Slotter Mania 6)', () {
    final euro = buildGameGroups([for (final g in psxGamesStartingWith('Euro Demo (')) g]);
    expect(euro, hasLength(15));
    expect(euro.every((g) => g.versions.length == 1 && g.versions.single.discs.length == 1), isTrue);
    expect(_titles(euro), contains('Euro Demo (Future) 94'));
    final slotter = buildGameGroups(psxGamesStartingWith('Slotter Mania 6')).single;
    expect(slotter.title, 'Slotter Mania 6 - Bakuretsu Sairai! Wadatsumi (2 Types) & Blue Lagoon');
    expect(_labels(slotter), ['Japan']);
  });

  test('an unnumbered file next to numbered ones is a version of its own (Dungeon Creator)', () {
    final g = buildGameGroups(psxGamesStartingWith('Dungeon Creator (')).single;
    expect(_labels(g), unorderedEquals(['Japan', 'Japan · 2 discs']));
  });

  test('an edition tag on a disc 4 does not split the set (SD Gundam - GGeneration-F)', () {
    final g = buildGameGroups(psxGamesStartingWith('SD Gundam - GGeneration-F (')).single;
    expect(_labels(g), contains('Japan · 4 discs'));
    expect(_labels(g), contains('Japan · Tokubetsu-ban · 4 discs'));
    final plain = g.versions.firstWhere((v) => v.label == 'Japan · 4 discs');
    expect(plain.discs.last.title, 'SD Gundam - GGeneration-F (Japan) (Disc 4) (Premium Disc).zip');
  });

  test('disc names that follow two different disc numbers are editions only per version (Rival Schools)', () {
    final g = buildGameGroups(psxGamesStartingWith('Rival Schools - United by Fate')).single;
    expect(_labels(g), unorderedEquals(['Europe · 2 discs', 'USA · 2 discs']));
  });

  test('a version whose discs are not 1 to n says which (lone Disc 2)', () {
    final g = buildGameGroups(psxGamesStartingWith('Syphon Filter 2 (')).single;
    expect(_labels(g), contains('Europe · Disc 2'));
    expect(_labels(g), contains('Europe · Rev 1 · 2 discs'));
    final gt = buildGameGroups(psxGames(['Gran Turismo 2'])).single;
    expect(_labels(gt), contains('Japan · Gran Turismo · Rev 1 · Disc 2'));
  });

  test('a missing part counts as zero', () {
    expect(compareRevisions('1', '1.1'), lessThan(0));
  });


  test('in one region with no revision or Alt, the shortest name', () {
    final spyro = buildGameGroups(psxGames(['Spyro the Dragon'])).single;
    expect(pickMainVersion(spyro.versions, ['Japan'])!.first.title, 'Spyro the Dragon (Japan).zip');
  });


  test('a version entry carries its disc set, a single disc carries none', () {
    final mgs = buildGameGroups(psxGames(['Metal Gear Solid'])).single;
    expect([for (final d in pickMainVersion(mgs.versions, defaultRegionOrder)!.entry.discs) d.title],
        ['Metal Gear Solid (USA) (Disc 1) (Rev 1).zip', 'Metal Gear Solid (USA) (Disc 2) (Rev 1).zip']);
    final tekken = buildGameGroups(psxGames(['Tekken 3'])).single;
    expect(pickMainVersion(tekken.versions, defaultRegionOrder)!.entry.discs, isEmpty);
  });


  test('a box set lists its members files', () {
    final box = buildGameGroups(psxGamesStartingWith('Arc the Lad Collection - ')).single;
    expect(box.files, hasLength(10));
  });


  test('a box word on one base title is not a box', () {
    final g = buildGameGroups([psxGame('Die Hard Trilogy 2 - Viva Las Vegas (USA)')]).single;
    expect(g.isBoxSet, isFalse);
    expect(g.title, 'Die Hard Trilogy 2 - Viva Las Vegas');
  });


  test('an undated Beta is an extra', () {
    expect(isExtra(psxGame('Spyro the Dragon (USA) (Beta)')), isTrue);
  });


  test('a dated file with no Beta tag is an extra', () {
    expect(isExtra(psxGame('Pocket PowerStation PlayStation Cheats CD (UK) (Unl) (2001-02-19)')), isTrue);
  });


  test('a numbered Special Disc stays in its set', () {
    final g = buildGameGroups([
      psxGame('Neorude (Japan) (Disc 1) (Game Disc)'),
      psxGame('Neorude (Japan) (Disc 2) (Special Disc)'),
    ]).single;
    expect(_labels(g), ['Japan · 2 discs']);
    expect(g.extras, isEmpty);
  });


  test('discs are ordered by number whatever the input order', () {
    final mgs = buildGameGroups(psxGames(['Metal Gear Solid']).reversed.toList()).single;
    expect([for (final d in pickMainVersion(mgs.versions, defaultRegionOrder)!.discs) d.title],
        ['Metal Gear Solid (USA) (Disc 1) (Rev 1).zip', 'Metal Gear Solid (USA) (Disc 2) (Rev 1).zip']);
  });


  test('a joined group is named after its main version', () {
    final bases = ['Crash Bandicoot - Warped', 'Crash Bandicoot 3 - Warped'];
    final g = buildGameGroups(psxGames(bases, launchboxId: 7).reversed.toList()).single;
    expect(g.title, 'Crash Bandicoot - Warped');
  });


  test('M groupEntry: text, filter, box discs, and a filtered-out group never falls back to an extra', () {
    final mgs = buildGameGroups(psxGames(['Metal Gear Solid'])).single;
    expect(groupEntry(mgs, (_) => true, text: 'spyro'), isNull);
    expect(groupEntry(mgs, (_) => true, text: 'premium package'), isNotNull);
    final tekken = buildGameGroups(psxGames(['Tekken 3'])).single;
    expect(groupEntry(tekken, (g) => !g.title.contains('(USA)'))!.title, 'Tekken 3 (Europe, Australia).zip');
    final box = buildGameGroups(psxGamesStartingWith('Arc the Lad Collection - ')).single;
    final entry = groupEntry(box, (g) => g.title.contains('Arc the Lad III'))!;
    expect(entry.title, 'Arc the Lad Collection - Arc the Lad III (USA) (Disc 1).zip');
    expect(entry.discs, isEmpty);
    expect(entry.group, same(box));
    final spyro = buildGameGroups(psxGames(['Spyro the Dragon'])).single;
    expect(groupEntry(spyro, (g) => g.title.contains('(Demo')), isNull);
    final ancient = buildGameGroups(psxGames(['Ancient Roman Extra'])).single;
    expect(groupEntry(ancient, (_) => true)!.group, same(ancient));
  });
}
