import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';
import 'package:retro_toolbox/widgets/header/header.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kit/kit_support.dart';
import 'screenshots/fakes.dart';

/// Records the owned view's toggles.
class _Catalog extends FakeCatalog {
  _Catalog(super.state);

  int toggles = 0;

  @override
  void toggleOwnedOnly() {
    toggles++;
    state = state.copyWith(filter: state.filter.copyWith(ownedOnly: !state.filter.ownedOnly));
  }
}

/// The SNES library dir is /roms/snes.
class _DirSettings extends SettingsNotifier {
  @override
  String getDownloadDir(String? consoleId) => consoleId == 'snes' ? '/roms/snes' : '';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final games = snesGames();

  Future<_Catalog> pumpGames(WidgetTester t, {required bool launcher, CatalogState? state, Map<int, GameStatus> statuses = const {}}) async {
    final catalog = _Catalog(state ?? CatalogState(games: games, cachedFilteredGames: games, cachedTotalCount: games.length));
    await pumpKit(t, const HomeScreen(), overrides: [
      ...gamesOverrides(games, catalog: catalog, statuses: statuses),
      launcherModeProvider.overrideWithValue(launcher),
      settingsProvider.overrideWith((ref) => _DirSettings()),
    ]);
    await t.pump(const Duration(milliseconds: 100));
    return catalog;
  }

  Color? fill(WidgetTester t) =>
      (t.widget<Container>(find.ancestor(of: find.byTooltip(ownedViewLabel), matching: find.byType(Container)).first).decoration as BoxDecoration).color;

  group('the header', () {
    testWidgets('has no Owned button with launcher mode off', (t) async {
      await pumpGames(t, launcher: false);
      expect(find.byTooltip(ownedViewLabel), findsNothing);
    });

    testWidgets('in launcher mode has the Owned button next to Filters, lit while the owned view is on; a tap toggles it', (t) async {
      final catalog = await pumpGames(t, launcher: true, state: CatalogState(games: games, cachedFilteredGames: games, cachedTotalCount: games.length, filter: const CatalogFilter(ownedOnly: true)));
      final owned = t.getRect(find.byTooltip(ownedViewLabel)), filters = t.getRect(find.byTooltip('Filters'));
      expect((owned.center.dy - filters.center.dy).abs(), lessThan(4));
      expect((owned.right - filters.left).abs(), lessThan(8));
      expect(fill(t), isNot(Colors.transparent));
      await t.tap(find.byTooltip(ownedViewLabel));
      await t.pump();
      expect(catalog.toggles, 1);
      expect(fill(t), Colors.transparent);
    });
  });

  group('an owned view with no match', () {
    CatalogState none({CatalogFilter filter = const CatalogFilter(ownedOnly: true), String query = ''}) =>
        CatalogState(games: games, cachedFilteredGames: const [], cachedTotalCount: 0, filter: filter, filterText: query);

    testWidgets('with nothing else narrowing it: the folder holds no game, and Show all', (t) async {
      final catalog = await pumpGames(t, launcher: true, state: none());
      expect(find.text('No games in /roms/snes'), findsOneWidget);
      expect(find.text('No games match'), findsNothing);
      await t.tap(find.text('Show all'));
      await t.pump();
      expect(catalog.toggles, 1);
    });

    testWidgets('with a search or a filter it keeps: no games match, as before', (t) async {
      await pumpGames(t, launcher: true, state: none(query: 'zelda'));
      expect(find.text('No games match'), findsOneWidget);
      expect(find.textContaining('No games in'), findsNothing);
    });

    testWidgets('narrowed by favourites: no games match', (t) async {
      await pumpGames(t, launcher: true, state: none(filter: const CatalogFilter(ownedOnly: true, showFavoritesOnly: true)));
      expect(find.text('No games match'), findsOneWidget);
    });
  });

  group('play badges', () {
    testWidgets('in launcher mode a game on disk wears the play badge, others none', (t) async {
      await pumpGames(t, launcher: true, statuses: {0: GameStatus.downloaded, 1: GameStatus.extracted});
      expect(find.byKey(const ValueKey('badge-play')), findsNWidgets(2));
      expect(find.byKey(const ValueKey('badge-done')), findsNothing);
    });

    testWidgets('with launcher mode off it wears the check, as before', (t) async {
      await pumpGames(t, launcher: false, statuses: {0: GameStatus.downloaded});
      expect(find.byKey(const ValueKey('badge-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-play')), findsNothing);
    });

    testWidgets('a row on disk wears it beside its checkbox, in launcher mode only', (t) async {
      final g = games.first;
      Widget row(bool on, GameStatus status) => MaterialApp(
            home: Scaffold(
              body: PlayBadges(on: on, child: GameRowBody(game: g, gameState: GameState(game: g, status: status), actions: const SizedBox())),
            ),
          );
      await t.pumpWidget(row(true, GameStatus.downloaded));
      expect(find.byKey(const ValueKey('row-play')), findsOneWidget);
      await t.pumpWidget(row(true, GameStatus.ready));
      expect(find.byKey(const ValueKey('row-play')), findsNothing);
      await t.pumpWidget(row(false, GameStatus.downloaded));
      expect(find.byKey(const ValueKey('row-play')), findsNothing);
    });
  });
}
