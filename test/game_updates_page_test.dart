import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/game_update_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _update = GameUpdate(
  label: 'v65536',
  size: 2722082635,
  url: 'https://api.example.com/games/download/0100BA4026E94000/update',
  fileName: "Castlevania: Belmont's Curse [v65536].nsz",
);
const _game = Game(
  title: "Castlevania: Belmont's Curse.nsz",
  url: 'https://api.example.com/games/download/0100BA4026E94000/base',
  size: 560321310,
  consoleId: 'switch',
  updates: [_update],
);

void main() {
  late List<(Game, GameAction)> ran;
  late List<Game> watched;
  tearDown(() {
    debugRunGameAction = null;
    GameDetailsPage.debugImageBuilder = null;
  });

  Future<void> pumpPage(WidgetTester t, Game game) async {
    ran = [];
    watched = [];
    debugRunGameAction = (ref, context, game, state, action) async => ran.add((game, action));
    GameDetailsPage.debugImageBuilder =
        (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url));
    t.view.physicalSize = const Size(1240, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        gameStateProvider.overrideWith((ref, g) {
          watched.add(g);
          return GameState(game: g, status: GameStatus.ready, availableActions: const {GameAction.download});
        }),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
      ],
      child: MaterialApp(home: GameDetailsPage(game: game)),
    ));
    await t.pump();
  }

  testWidgets('a game with updates lists them; Download gets that update into its folder, and the page stays', (t) async {
    await pumpPage(t, _game);
    expect(find.text('Updates'), findsOneWidget);
    final row = find.ancestor(of: find.text('v65536'), matching: find.byType(GameFileRow));
    await t.tap(find.descendant(of: row, matching: find.text('Download')));
    await t.pumpAndSettle();
    final (game, action) = ran.single;
    expect(action, GameAction.download);
    expect((game.isUpdate, game.url, game.title), (true, _update.url, _update.fileName));
    expect(find.byType(GameDetailsPage), findsOneWidget);
  });

  testWidgets('a game without updates has no Updates section', (t) async {
    await pumpPage(t, _game.copyWith(updates: const []));
    expect(find.text('Updates'), findsNothing);
  });

  testWidgets('rebuilding the page watches the same update Game, so no provider entry is orphaned', (t) async {
    await pumpPage(t, _game);
    // Same game again: the page's state is kept and it rebuilds.
    await t.pumpWidget(ProviderScope(
      overrides: [
        gameStateProvider.overrideWith((ref, g) {
          watched.add(g);
          return GameState(game: g, status: GameStatus.ready, availableActions: const {GameAction.download});
        }),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
      ],
      child: MaterialApp(home: GameDetailsPage(game: _game)),
    ));
    await t.pump();
    expect(watched.where((g) => g.isUpdate), hasLength(1));
  });
}
