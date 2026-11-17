import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/services/disc_sets.dart';
import 'package:retro_toolbox/services/filtering_service.dart';

Game _g(String title, {String console = 'psx', int size = 1}) =>
    Game(title: title, url: 'https://example.com/files/${Uri.encodeComponent(title)}.chd', size: size, consoleId: console);

List<String> _titles(Iterable<Game> games) => [for (final g in games) g.title];

void main() {
  final ff1 = _g('Final Fantasy VII (USA) (Disc 1)');
  final ff2 = _g('Final Fantasy VII (USA) (Disc 2)');
  final ff3 = _g('Final Fantasy VII (USA) (Disc 3)');
  final ffEu1 = _g('Final Fantasy VII (Europe) (Disc 1)');
  final ffEu2 = _g('Final Fantasy VII (Europe) (Disc 2)');
  final crash = _g('Crash Bandicoot (USA)');

  group('disc keys', () {
    test('discs of one game share a key; a game without a disc token has none', () {
      expect(discGroupKey(ff1), discGroupKey(ff3));
      expect(discGroupKey(ff1), 'psx|Final Fantasy VII (USA)');
      expect(discGroupKey(crash), isNull);
      expect(discNumber(ff2), 2);
      expect(discNumber(crash), 0);
    });

    test('Disk, CD and "of N" spellings count, in any case', () {
      expect(discNumber(_g('Riven (USA) (disk 4)')), 4);
      expect(discNumber(_g('Myst (USA) (CD 2)')), 2);
      expect(discNumber(_g('Lunar (USA) (Disc 3 of 4)')), 3);
      expect(discGroupKey(_g('Lunar (USA) (Disc 3 of 4)')), discGroupKey(_g('Lunar (USA) (Disc 1 of 4)')));
    });

    test('another region, revision or console is another set', () {
      expect(discGroupKey(ffEu1), isNot(discGroupKey(ff1)));
      expect(discGroupKey(_g('Final Fantasy VII (USA) (Rev 1) (Disc 1)')), isNot(discGroupKey(ff1)));
      expect(discGroupKey(_g('Final Fantasy VII (USA) (Disc 1)', console: 'ps2')), isNot(discGroupKey(ff1)));
    });
  });

  group('discSetOf', () {
    test('finds the whole set, by disc number, Disc 10 after Disc 2', () {
      final ten = _g('Game (USA) (Disc 10)');
      final two = _g('Game (USA) (Disc 2)');
      final one = _g('Game (USA) (Disc 1)');
      expect(_titles(discSetOf(two, [ten, crash, two, one])), ['Game (USA) (Disc 1)', 'Game (USA) (Disc 2)', 'Game (USA) (Disc 10)']);
    });

    test('a game without a disc token is its own set', () {
      expect(discSetOf(crash, [crash, ff1, ff2]), [crash]);
    });
  });

  group('groupDiscSets', () {
    test('one entry per set of two or more, the first disc carrying the set, in place', () {
      final out = groupDiscSets([crash, ff2, ff1, ff3, ffEu1, ffEu2, _g('Zed (USA) (Disc 1)')]);
      expect(_titles(out), [
        'Crash Bandicoot (USA)',
        'Final Fantasy VII (USA) (Disc 1)',
        'Final Fantasy VII (Europe) (Disc 1)',
        'Zed (USA) (Disc 1)', // a single disc is not a set
      ]);
      expect(_titles(out[1].discs), _titles([ff1, ff2, ff3]));
      expect(_titles(out[2].discs), _titles([ffEu1, ffEu2]));
      expect(out[0].discs, isEmpty);
      expect(out[3].discs, isEmpty);
    });

    test('the grouped entry is still disc 1: same id, so selection and state carry over', () {
      final out = groupDiscSets([ff1, ff2]);
      expect(out.single.gameId, ff1.gameId);
    });

    test('discs are not saved with the game', () {
      final grouped = groupDiscSets([ff1, ff2]).single;
      expect(grouped.toJson().containsKey('discs'), isFalse);
      expect(Game.fromJson(grouped.toJson()).discs, isEmpty);
    });
  });

  group('discsToDownload', () {
    final grouped = groupDiscSets([ff1, ff2, ff3]).single;

    test('all: every disc; not all: only the one asked for', () {
      expect(_titles(discsToDownload(grouped, all: true)), _titles([ff1, ff2, ff3]));
      expect(_titles(discsToDownload(grouped, all: false)), [ff1.title]);
    });

    test('a disc without its set finds it in the catalog', () {
      expect(_titles(discsToDownload(ff1, all: true, catalog: [crash, ff3, ff1, ff2])), _titles([ff1, ff2, ff3]));
      expect(_titles(discsToDownload(ff1, all: true)), [ff1.title]);
      expect(_titles(discsToDownload(crash, all: true, catalog: [crash, ff1, ff2])), [crash.title]);
    });

    test('other discs already queued, running or done stay as they are; the one asked for always goes', () {
      final status = {
        ff1.gameId: GameStatus.extracted,
        ff2.gameId: GameStatus.downloading,
        ff3.gameId: GameStatus.downloadFailed,
      };
      expect(_titles(discsToDownload(grouped, all: true, statusOf: (id) => status[id])), _titles([ff1, ff3]));
    });
  });

  group('FilteringService', () {
    final games = [crash, ff3, ff1, ff2, ffEu1, ffEu2];
    FilterResult run({required bool group, int limit = 100}) => FilteringService.filterAndPaginate(FilterInput(
          games: games,
          filterText: '',
          filter: const CatalogFilter(regions: {}, dumpQualities: {}, romTypes: {}, modifications: {}, distributionTypes: {}, showLatestRevisionOnly: false),
          limit: limit,
          groupVersions: group,
        ));

    test('off: every disc is an entry', () {
      final r = run(group: false);
      expect(r.totalCount, 6);
      expect(r.games.every((g) => g.discs.isEmpty), isTrue);
    });

    test('on: one entry per set, counted and paged as entries', () {
      final r = run(group: true);
      expect(r.totalCount, 3);
      expect(_titles(r.games), ['Crash Bandicoot (USA)', 'Final Fantasy VII (Europe) (Disc 1)', 'Final Fantasy VII (USA) (Disc 1)']);
      expect(r.games[2].discs.length, 3);
      final page = run(group: true, limit: 2);
      expect((page.games.length, page.totalCount, page.hasMore), (2, 3, true));
    });

    test('with latest revision only on (the default), the discs survive it and group', () {
      final revs = [
        _g('Game (USA) (Disc 1)'),
        _g('Game (USA) (Disc 2)'),
      ];
      final r = FilteringService.filterAndPaginate(FilterInput(
          games: revs,
          filterText: '',
          filter: const CatalogFilter(regions: {}, dumpQualities: {}, romTypes: {}, modifications: {}, distributionTypes: {}),
          limit: 100,
          groupVersions: true));
      expect(r.totalCount, 1);
      expect(r.games.single.discs.length, 2);
    });
  });

  group('settings', () {
    test('a choice saved under the old groupDiscs key is read as groupVersions', () {
      expect(BaseSettings.fromJson({'groupDiscs': false}).groupVersions, isFalse);
      expect(BaseSettings.fromJson({'groupDiscs': true, 'groupVersions': false}).groupVersions, isFalse);
    });

    test('BaseSettings round-trips groupVersions and downloadAllDiscs, unset by default', () {
      expect(const BaseSettings().getSetting<bool>(AppSettings.groupVersions), isNull);
      expect(const BaseSettings().getSetting<bool>(AppSettings.downloadAllDiscs), isNull);
      final set = const BaseSettings().setSetting(AppSettings.groupVersions, true).setSetting(AppSettings.downloadAllDiscs, false);
      final back = BaseSettings.fromJson(set.toJson());
      expect(back.getSetting<bool>(AppSettings.groupVersions), isTrue);
      expect(back.getSetting<bool>(AppSettings.downloadAllDiscs), isFalse);
    });

    test('AppSettings keeps a per-console choice through JSON', () {
      final s = AppSettings(consoleSettings: {'psx': const BaseSettings().setSetting(AppSettings.groupVersions, true)});
      expect(AppSettings.fromJson(s.toJson()).consoleSettings['psx']!.getSetting<bool>(AppSettings.groupVersions), isTrue);
    });
  });
}
