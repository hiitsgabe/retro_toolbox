import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/services/python_worker.dart';
import 'package:retro_toolbox/widgets/menu_grid/sport_slug.dart';

void main() {
  group('parseWorkerLine', () {
    test('parses progress percent to fraction', () {
      final r = parseWorkerLine('PROGRESS:42');
      expect(r.signal, WorkerSignal.progress);
      expect(r.progress, closeTo(0.42, 1e-9));
    });

    test('DONE completes at 1.0', () {
      final r = parseWorkerLine('DONE');
      expect(r.signal, WorkerSignal.done);
      expect(r.progress, 1.0);
    });

    test('ERROR carries the message', () {
      final r = parseWorkerLine('ERROR:ApiError: upstream down');
      expect(r.signal, WorkerSignal.error);
      expect(r.message, 'ApiError: upstream down');
    });

    test('unrelated stdout is ignored', () {
      expect(parseWorkerLine('some log line').signal, WorkerSignal.none);
    });

    test('malformed progress falls back to 0', () {
      expect(parseWorkerLine('PROGRESS:xx').progress, 0.0);
    });
  });

  group('PatcherInfo.fromJson', () {
    test('reads library fields and defaults the provider', () {
      final info = PatcherInfo.fromJson(const {
        'game_id': 'x',
        'platform': 'genesis',
        'sport': 'hockey',
        'requires_slot_mapping': false,
        'providers': ['espn', 'nhl'],
      });
      expect(info.sport, 'hockey');
      expect(info.requiresSlotMapping, false);
      expect(info.defaultProvider, 'espn');
    });

    test('tolerates missing keys', () {
      final info = PatcherInfo.fromJson(const {});
      expect(info.providers, isEmpty);
      expect(info.defaultProvider, '');
    });
  });

  group('LeagueData.fromJson', () {
    test('flattens teams and counts players', () {
      final data = LeagueData.fromJson(const {
        'league': {'name': 'Test League', 'season': 2025},
        'teams': [
          {
            'team': {'id': 1, 'name': 'Alpha'},
            'players': [1, 2, 3]
          },
          {
            'team': {'id': 2, 'name': 'Beta'},
            'players': []
          },
        ],
      });
      expect(data.leagueName, 'Test League');
      expect(data.season, 2025);
      expect(data.teams.length, 2);
      expect(data.teams.first.playerCount, 3);
    });
  });

  test('ISS screen slots have their own names', () {
    expect(imageSlotLabel('konami', 'iss-snes').$1, 'Konami screen');
    expect(imageSlotLabel('menu', 'iss-snes').$1, 'Menu wallpaper');
    expect(imageSlotLabel('title', 'iss-snes').$2, contains('PRESS START'));
  });

  test("NHL '94 and KGJ screen slots have their own names", () {
    expect(imageSlotLabel('boot', 'nhl94-snes').$2, contains('EA SPORTS'));
    expect(imageSlotLabel('menu', 'nhl94-snes').$1, 'Menu wallpaper');
    expect(imageSlotLabel('title', 'kgj-mlb-snes').$1, 'Stadium');
    expect(imageSlotLabel('boot', 'kgj-mlb-snes').$2, contains('licence screen'));
    expect(logosNote('nhl94-snes'), contains('center ice'));
    expect(logosNote('nhl94-snes'), contains("while the cartridge's title stays"));
    expect(logosNote('kgj-mlb-snes'), contains("Today's Game"));
    expect(logosNote('we2002'), contains('in-game flag'));
  });

  test("RomInfo pairs a team code with its slot's roster counts", () {
    final info = RomInfo.fromJson({
      'is_valid': true,
      'slots': [],
      'extra': {
        'roster_counts': [
          [2, 9, 7],
          [2, 15, 7],
        ],
      },
      'team_slots': {'BOS': 1},
    });
    expect(info.countsFor('BOS'), [2, 15, 7]);
    expect(info.countsFor('ANA'), isNull); // not asked
    expect(RomInfo.fromJson({'is_valid': true}).countsFor('BOS'), isNull);
  });

  test('PatchResult carries what mapping said, none from an older worker', () {
    final r = PatchResult.fromJson({'output_path': 'o', 'teams_patched': 27, 'players_patched': 600, 'notes': ['Edmonton skipped']});
    expect(r.notes, ['Edmonton skipped']);
    expect(PatchResult.fromJson({'output_path': 'o'}).notes, isEmpty);
  });

  test('a roster names the season the provider fetched', () {
    final doc = RosterDoc.fromJson({'league': {'name': 'Brasileirao Serie A', 'season': 2026}, 'teams': []});
    expect(doc.season, 2026);
    expect(RosterDoc.fromJson({'league': {'name': 'Custom'}, 'teams': []}).season, isNull);
  });

  test('defaultSeason uses the hockey season start year and the calendar year otherwise', () {
    // Hockey seasons run October to June, named by their start year.
    expect(defaultSeason('nhl', DateTime(2026, 9, 30)), 2025);
    expect(defaultSeason('nhl', DateTime(2026, 10, 1)), 2026);
    expect(defaultSeason('espn', DateTime(2026, 3, 1)), 2026);
  });

  test('PatcherInfo reads the visual capabilities, off when absent', () {
    final visual = PatcherInfo.fromJson({
      'game_id': 'g',
      'supports_logos': true,
      'supports_blank_unused': true,
      'image_slots': ['title', 'menu'],
    });
    expect(visual.supportsLogos, isTrue);
    expect(visual.supportsBlankUnused, isTrue);
    expect(visual.imageSlots, ['title', 'menu']);
    expect(visual.hasVisuals, isTrue);
    final plain = PatcherInfo.fromJson({'game_id': 'g'});
    expect(plain.hasVisuals, isFalse);
    expect(imageSlotLabel('title').$1, 'Title screen');
    expect(imageSlotLabel('loading').$1, 'Loading screen');
    expect(imageSlotLabel('match').$1, 'Match screen');
    expect(imageSlotLabel('other').$1, 'Other');
    expect(imageSlotLabel('some_slot').$1, 'Some slot');
    expect(imageSlotLabel('logo', 'nhl07-psp').$1, 'Game logo');
    expect(imageSlotLabel('title', 'nhl07-psp').$2, contains('PRESS START'));
    expect(imageSlotLabel('legal', 'nhl05-ps2').$1, 'Legal screen');
    expect(imageSlotLabel('title', 'we2002').$1, 'Title screen');
  });

  test('PatcherInfo reads kits, nationals and slot groups; a kit-only game has visuals', () {
    final pes = PatcherInfo.fromJson({
      'game_id': 'pes2013-ps2',
      'supports_kits': true,
      'kit_templates': false,
      'supports_nationals': true,
      'national_slot_base': 139,
      'slot_groups': [
        {'name': 'England', 'first': 0, 'count': 20},
        {'name': 'Other', 'first': 98, 'count': 41},
      ],
      'max_leagues': 5,
      'multi_league': true,
    });
    expect(pes.supportsKits, isTrue);
    expect(pes.kitTemplates, isFalse);
    expect(pes.supportsNationals, isTrue);
    expect(pes.nationalSlotBase, 139);
    expect(pes.slotGroups.map((g) => (g.name, g.first, g.count)), [('England', 0, 20), ('Other', 98, 41)]);
    expect(pes.maxLeagues, 5);
    expect(pes.leagueCap, 2); // only two groups listed here
    expect(pes.multiLeague, isTrue);
    expect(pes.hasVisuals, isFalse); // kits live in the team editor, not the Look step
    final we = PatcherInfo.fromJson({'game_id': 'we2002', 'supports_kits': true, 'kit_templates': true});
    expect(we.kitTemplates, isTrue);
    expect(we.nationalSlotBase, isNull);
    expect(we.slotGroups, isEmpty);
    expect(we.multiLeague, isFalse);
    // Groups that only describe the slots, with no max_leagues (or 1): one league.
    final grouped = PatcherInfo.fromJson({
      'game_id': 'we2002',
      'slot_groups': [
        {'name': 'Master League', 'first': 0, 'count': 32},
        {'name': 'National only', 'first': 32, 'count': 31},
      ],
    });
    expect(grouped.maxLeagues, 1);
    expect(grouped.multiLeague, isFalse);
  });

  test('PatcherInfo carries the game languages, empty when it has none', () {
    final withLangs = PatcherInfo.fromJson({
      'game_id': 'g',
      'languages': ['en', 'pt']
    });
    expect(withLangs.languages, ['en', 'pt']);
    expect(PatcherInfo.fromJson({'game_id': 'g'}).languages, isEmpty);
    expect(languageName('pt'), 'Português');
    expect(languageName('xx'), 'XX');
  });
}
