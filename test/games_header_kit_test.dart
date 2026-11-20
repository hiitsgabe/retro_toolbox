import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/widgets/header/console_dropdown.dart';
import 'package:retro_toolbox/widgets/header/search_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kit/kit_support.dart';
import 'screenshots/fakes.dart';

/// Records what the empty state's buttons ask of the catalog.
class _Catalog extends FakeCatalog {
  _Catalog(super.state);

  final calls = <String>[];

  @override
  void defaultFilters() {
    calls.add('reset');
    state = state.copyWith(filter: const CatalogFilter());
  }

  @override
  void updateFilterText(String filter) {
    calls.add('search "$filter"');
    state = state.copyWith(filterText: filter);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final games = snesGames();

  Future<_Catalog> pumpGames(WidgetTester t, {(Size, double) device = odin2, CatalogState? state}) async {
    final catalog = _Catalog(state ?? CatalogState(games: games, cachedFilteredGames: games, cachedTotalCount: games.length));
    await pumpKit(t, const HomeScreen(), device: device, overrides: gamesOverrides(games, catalog: catalog));
    await t.pump(const Duration(milliseconds: 100));
    return catalog;
  }

  group('header', () {
    for (final (name, device) in [('odin2', odin2), ('phone', phone), ('linux640', linux640)]) {
      testWidgets('one row on $name: the console, the filters and the menu share a line', (t) async {
        await pumpGames(t, device: device);
        final console = t.getRect(find.byType(ConsoleDropdown));
        final filters = t.getRect(find.byTooltip('Filters'));
        final more = t.getRect(find.byTooltip('More options'));
        expect((console.center.dy - filters.center.dy).abs(), lessThan(4));
        expect((more.center.dy - filters.center.dy).abs(), lessThan(4));
      });
    }

    testWidgets('on a phone search is an icon that opens the field in the console\'s place', (t) async {
      await pumpGames(t, device: phone);
      expect(find.byType(SearchField), findsNothing);
      await t.tap(find.byTooltip('Search'));
      await t.pump();
      expect(find.byType(SearchField), findsOneWidget);
      expect(find.byType(ConsoleDropdown), findsNothing);
    });

    testWidgets('a search under way keeps the field open on a phone', (t) async {
      await pumpGames(t, device: phone, state: CatalogState(games: games, cachedFilteredGames: games, cachedTotalCount: 3, filterText: 'mario'));
      expect(find.byType(SearchField), findsOneWidget);
    });

    testWidgets('no badge on the default filter', (t) async {
      await pumpGames(t);
      expect(find.byKey(const ValueKey('filter-badge')), findsNothing);
    });

    testWidgets('the badge counts the filters off their default', (t) async {
      await pumpGames(
        t,
        state: CatalogState(
          games: games,
          cachedFilteredGames: games,
          cachedTotalCount: games.length,
          filter: const CatalogFilter().copyWith(regions: {'Japan'}, showFavoritesOnly: true),
        ),
      );
      expect(find.descendant(of: find.byKey(const ValueKey('filter-badge')), matching: find.text('2')), findsOneWidget);
    });
  });

  group('no matches', () {
    CatalogState none({CatalogFilter filter = const CatalogFilter(), String query = ''}) =>
        CatalogState(games: games, cachedFilteredGames: const [], cachedTotalCount: 0, filter: filter, filterText: query);
    const narrowed = CatalogFilter(regions: {'Japan'});

    testWidgets('a search and a filter that match nothing: the line, Reset filters and Clear search', (t) async {
      final catalog = await pumpGames(t, state: none(filter: narrowed, query: 'zelda'));
      expect(find.text('No games match'), findsOneWidget);
      await t.tap(find.text('Clear search'));
      await t.pump();
      await t.tap(find.text('Reset filters'));
      await t.pump();
      expect(catalog.calls, ['search ""', 'reset']);
    });

    testWidgets('no search: only Reset filters', (t) async {
      await pumpGames(t, state: none(filter: narrowed));
      expect(find.text('Reset filters'), findsOneWidget);
      expect(find.text('Clear search'), findsNothing);
    });

    testWidgets('the default filter: only Clear search', (t) async {
      await pumpGames(t, state: none(query: 'zelda'));
      expect(find.text('Reset filters'), findsNothing);
      expect(find.text('Clear search'), findsOneWidget);
    });

    testWidgets('a list with games shows them, not the empty state', (t) async {
      await pumpGames(t);
      expect(find.text('No games match'), findsNothing);
    });
  });
}
