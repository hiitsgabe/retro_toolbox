import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/filtering_service.dart';
import 'package:retro_toolbox/widgets/header/filter_modal.dart';

Game _game(String title, {int size = 0, int? date, int? pop}) => Game(
      title: title,
      url: 'https://host.example/$title',
      size: size,
      consoleId: 'con',
      details: date == null && pop == null ? null : GameDetails(releaseDate: date, popularity: pop),
    );

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog(List<Game> games) : super(CatalogState(games: games));
  final sorts = <CatalogSort>[];

  @override
  void setSort(CatalogSort sort) => sorts.add(sort);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('DAT release dates', () {
    test('merge year, month and day per name across files', () {
      final dates = parseDatReleaseDates([
        'clrmamepro (\n\tname "Set"\n)\n\n'
            'game (\n\tname "Alpha Title (USA)"\n\treleaseyear "1999"\n\trom ( name "Alpha Title (USA).bin" crc 00000000 )\n)\n'
            'game (\n\tcomment "Beta Title (USA)"\n\treleaseyear 2001\n\treleasemonth "7"\n\treleaseday "4"\n)\n'
            'game (\n\tcomment "Gamma Title (USA)"\n\treleasemonth "11"\n)\n'
            'game (\n\tcomment "Delta Title (USA)"\n\treleaseyear "199x"\n)\n',
        'game (\r\n\tcomment "Alpha Title (USA)"\r\n\treleasemonth "07"\r\n)\r\n',
      ]);
      expect(dates, {
        'Alpha Title (USA)': 19990700,
        'Beta Title (USA)': 20010704,
      });
    });

    test('match by exact name, then normalized name, keeping dates already set', () {
      final games = matchReleaseDates([
        _game('Alpha Title (USA).bin'),
        _game('beta title - usa.zip'),
        _game('Gamma Title (USA).bin', date: 20200000),
        _game('Other Title (USA).bin'),
      ], {
        'Alpha Title (USA)': 19990700,
        'Beta Title (USA)': 20010000,
        'Gamma Title (USA)': 19800000,
      });
      expect([for (final g in games) g.details?.releaseDate], [19990700, 20010000, 20200000, null]);
    });

    test('old details JSON without the new fields still loads', () {
      final d = GameDetails.fromJson({'boxart': 'https://host.example/a.png'});
      expect((d.boxart, d.releaseDate, d.popularity), ('https://host.example/a.png', null, null));
    });
  });

  group('sort', () {
    final games = [
      _game('Delta.bin', size: 30, date: 20010000),
      _game('Alpha.bin', size: 10, pop: 5),
      _game('Echo.bin', date: 19990700, pop: 9),
      _game('Charlie.bin', size: 30, date: 20010000, pop: 5),
      _game('Bravo.bin', size: 20),
    ];
    List<String> sorted(CatalogSort sort) => [
          for (final g in FilteringService.filterAndPaginate(FilterInput(
            games: games,
            filterText: '',
            filter: CatalogFilter(regions: const {}, dumpQualities: const {}, romTypes: const {}, modifications: const {}, distributionTypes: const {}, sort: sort),
            limit: 100,
          )).games)
            g.title.split('.').first,
        ];

    test('each order puts games without the key last, ties by name', () {
      expect(sorted(CatalogSort.name), ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']);
      expect(sorted(CatalogSort.sizeDesc), ['Charlie', 'Delta', 'Bravo', 'Alpha', 'Echo']);
      expect(sorted(CatalogSort.sizeAsc), ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']);
      expect(sorted(CatalogSort.newest), ['Charlie', 'Delta', 'Echo', 'Alpha', 'Bravo']);
      expect(sorted(CatalogSort.popular), ['Echo', 'Alpha', 'Charlie', 'Bravo', 'Delta']);
    });
  });

  group('filter modal', () {
    Future<_FakeCatalog> pump(WidgetTester t, List<Game> games) async {
      final catalog = _FakeCatalog(games);
      await t.pumpWidget(ProviderScope(
        key: UniqueKey(), // a fresh scope per pump: overrides are read once
        overrides: [catalogProvider.overrideWith((_) => catalog)],
        child: const MaterialApp(home: Scaffold(body: FilterModal())),
      ));
      return catalog;
    }

    testWidgets('shows only the sort options the catalog has data for', (t) async {
      await pump(t, [_game('Alpha.bin')]);
      expect(find.text('Sort by'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      for (final label in ['Largest', 'Smallest', 'Newest', 'Most popular']) {
        expect(find.text(label), findsNothing);
      }

      await pump(t, [_game('Alpha.bin', size: 1), _game('Bravo.bin', date: 19990000)]);
      expect(find.text('Largest'), findsOneWidget);
      expect(find.text('Smallest'), findsOneWidget);
      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Most popular'), findsNothing);
    });

    testWidgets('picking an option sets the sort', (t) async {
      final catalog = await pump(t, [_game('Alpha.bin', pop: 3)]);
      await t.tap(find.text('Most popular'));
      expect(catalog.sorts, [CatalogSort.popular]);
    });
  });
}
