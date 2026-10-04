import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
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
          {'team': {'id': 1, 'name': 'Alpha'}, 'players': [1, 2, 3]},
          {'team': {'id': 2, 'name': 'Beta'}, 'players': []},
        ],
      });
      expect(data.leagueName, 'Test League');
      expect(data.season, 2025);
      expect(data.teams.length, 2);
      expect(data.teams.first.playerCount, 3);
    });
  });

  test('defaultSeason uses the hockey season start year and the calendar year otherwise', () {
    // Hockey seasons run October to June, named by their start year.
    expect(defaultSeason('nhl', DateTime(2026, 9, 30)), 2025);
    expect(defaultSeason('nhl', DateTime(2026, 10, 1)), 2026);
    expect(defaultSeason('espn', DateTime(2026, 3, 1)), 2026);
  });

  test('PatcherInfo carries the game languages, empty when it has none', () {
    final withLangs = PatcherInfo.fromJson({'game_id': 'g', 'languages': ['en', 'pt']});
    expect(withLangs.languages, ['en', 'pt']);
    expect(PatcherInfo.fromJson({'game_id': 'g'}).languages, isEmpty);
    expect(languageName('pt'), 'Português');
    expect(languageName('xx'), 'XX');
  });
}
