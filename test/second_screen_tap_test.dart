import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/widgets/dual_screen/companion_action_listener.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';
import 'package:retro_toolbox/widgets/menu_grid/cover_flow.dart';

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  final toggled = <String>[];
  @override
  Future<void> toggleFavorite(String gameId) async => toggled.add(gameId);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog([List<Game> games = const []]) : super(CatalogState(games: games));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGames extends StateNotifier<Map<String, GameState>> implements GameStateManager {
  _FakeGames([super.state = const {}]);
  @override
  bool isResolving(String gameId) => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A dual screen whose companion is open, or not, without the platform.
class _Dual extends DualScreenNotifier {
  _Dual(super.ref, bool open) : super(enabled: false) {
    state = DualScreenState(companionOpen: open);
  }
}

Game game(String title) => Game(title: title, url: 'https://x/$title.zip', size: 1, consoleId: 'snes');

final a = game('Alpha'), b = game('Bravo');

void main() {
  late List<(Game, GameAction)> ran;

  setUp(() {
    ran = [];
    debugRunGameAction = (ref, context, game, state, action) async => ran.add((game, action));
    GameDetailsPage.debugImageBuilder = (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url));
  });
  tearDown(() {
    debugRunGameAction = null;
    GameDetailsPage.debugImageBuilder = null;
  });

  Future<ProviderContainer> pump(WidgetTester t, Widget body, {required bool open, List<Game> catalog = const [], Map<String, GameState> states = const {}}) async {
    final container = ProviderContainer(overrides: [
      gameStateProvider.overrideWith((ref, g) => states[g.gameId] ?? GameState(game: g, status: GameStatus.ready, availableActions: const {GameAction.download})),
      gameStateManagerProvider.overrideWith((ref) => _FakeGames(states)),
      favoritesProvider.overrideWith((ref) => _FakeFavorites()),
      catalogProvider.overrideWith((ref) => _FakeCatalog(catalog)),
      dualScreenProvider.overrideWith((ref) => _Dual(ref, open)),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            TextButton(autofocus: true, onPressed: () {}, child: const Text('Above')),
            Expanded(child: body),
          ]),
        ),
      ),
    ));
    await t.pump();
    return container;
  }

  Widget rows() => ListView(children: [
        SizedBox(width: 800, height: 120, child: GameRow(game: a)),
        SizedBox(width: 800, height: 120, child: GameRow(game: b)),
      ]);

  /// The card of [title] draws the second-screen outline.
  bool highlighted(WidgetTester t, String title) {
    final highlight = find.ancestor(of: find.text(title), matching: find.byType(SecondScreenHighlight));
    final box = t.widget<DecoratedBox>(find.descendant(of: highlight, matching: find.byType(DecoratedBox)).first);
    return box.position == DecorationPosition.foreground && (box.decoration as BoxDecoration).border != null;
  }

  bool focusedOn(String title) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && find.descendant(of: find.byElementPredicate((e) => e == ctx), matching: find.text(title)).evaluate().isNotEmpty;
  }

  testWidgets('second screen open: a tap shows the game there and focuses its card; a tap on the shown game opens its page', (t) async {
    final c = await pump(t, rows(), open: true);
    await t.tap(find.text('Bravo'));
    await t.pumpAndSettle();
    expect(c.read(focusedGameProvider)?.gameId, b.gameId);
    expect(find.byType(GameDetailsPage), findsNothing);
    expect(focusedOn('Bravo'), isTrue);
    expect(highlighted(t, 'Bravo'), isTrue);
    expect(highlighted(t, 'Alpha'), isFalse);

    await t.tap(find.text('Bravo'));
    await t.pumpAndSettle();
    expect(find.byType(GameDetailsPage), findsOneWidget);
  });

  testWidgets('second screen closed: a tap opens the page, and no card is outlined', (t) async {
    final c = await pump(t, rows(), open: false);
    c.read(focusedGameProvider.notifier).state = a;
    await t.pump();
    expect(highlighted(t, 'Alpha'), isFalse);
    await t.tap(find.text('Bravo'));
    await t.pumpAndSettle();
    expect(find.byType(GameDetailsPage), findsOneWidget);
  });

  testWidgets('a grid card follows the same rule and outline', (t) async {
    final c = await pump(
        t,
        Row(children: [
          SizedBox(width: 150, height: 220, child: GameGridItem(game: a)),
          SizedBox(width: 150, height: 220, child: GameGridItem(game: b)),
        ]),
        open: true);
    c.read(focusedGameProvider.notifier).state = a;
    await t.pump();
    expect(highlighted(t, 'Alpha'), isTrue);
    expect(highlighted(t, 'Bravo'), isFalse);
    await t.tap(find.text('Bravo').first);
    await t.pumpAndSettle();
    expect(c.read(focusedGameProvider)?.gameId, b.gameId);
    expect(find.byType(GameDetailsPage), findsNothing);
    expect(highlighted(t, 'Bravo'), isTrue);
  });

  testWidgets('cover flow browsed by touch: the new centre replaces the shown game, only while the second screen is open', (t) async {
    for (final open in [true, false]) {
      await t.pumpWidget(const SizedBox()); // a fresh flow, back on its first card
      final c = await pump(
          t,
          CoverFlow(aspectRatio: 0.72, items: [
            for (final g in [a, b]) CoverFlowItem(face: Text(g.title), label: g.title, wrapFocus: (f) => GameCardActions(game: g, selectable: true, child: f)),
          ]),
          open: open);
      expect(c.read(focusedGameProvider), isNull, reason: 'the flow does not have focus');
      c.read(focusedGameProvider.notifier).state = a;
      await t.tap(find.text('Bravo').first); // a side card: the flow moves to it
      await t.pumpAndSettle();
      expect(c.read(focusedGameProvider)?.gameId, open ? b.gameId : a.gameId, reason: 'open: $open');
    }
  });

  group('a companion request', () {
    Future<ProviderContainer> listen(WidgetTester t, {List<Game> catalog = const [], Map<String, GameState> states = const {}}) async {
      final key = GlobalKey<NavigatorState>();
      final c = await pump(t, const SizedBox(), open: true, catalog: catalog, states: states);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: CompanionActionListener(
          navigatorContext: () => key.currentContext,
          child: MaterialApp(navigatorKey: key, home: const SizedBox()),
        ),
      ));
      return c;
    }

    void request(ProviderContainer c, int seq, Map<String, dynamic> json) => c.read(companionRequestProvider.notifier).state = CompanionRequest(seq, json);

    testWidgets('runs the action on the shown game, which keeps its discs', (t) async {
      final grouped = game('Saga (Disc 1)').copyWith(discs: [game('Saga (Disc 1)'), game('Saga (Disc 2)')]);
      final c = await listen(t, catalog: [game('Saga (Disc 1)')]);
      c.read(focusedGameProvider.notifier).state = grouped;
      request(c, 1, {'kind': 'game', 'gameId': grouped.gameId, 'action': 'download'});
      await t.pump();
      expect(ran.single.$2, GameAction.download);
      expect(ran.single.$1.discs, hasLength(2));
    });

    testWidgets("finds a task's game from another console through the task states, and toggles favourites", (t) async {
      final other = Game(title: 'Elsewhere', url: 'https://x/e.zip', size: 1, consoleId: 'psx');
      final c = await listen(t, states: {other.gameId: GameState(game: other, status: GameStatus.downloading)});
      request(c, 1, {'kind': 'game', 'gameId': other.gameId, 'action': 'pause'});
      await t.pump();
      expect(ran.single, (other, GameAction.pause));

      request(c, 2, {'kind': 'favorite', 'gameId': other.gameId});
      await t.pump();
      expect((c.read(favoritesProvider.notifier) as _FakeFavorites).toggled, [other.gameId]);
    });

    testWidgets('the same press twice runs twice; unknown games and actions run nothing', (t) async {
      final c = await listen(t, catalog: [a]);
      request(c, 1, {'kind': 'game', 'gameId': a.gameId, 'action': 'download'});
      await t.pump();
      request(c, 2, {'kind': 'game', 'gameId': a.gameId, 'action': 'download'});
      await t.pump();
      expect(ran, hasLength(2));

      request(c, 3, {'kind': 'game', 'gameId': 'snes/nobody.zip', 'action': 'download'});
      request(c, 4, {'kind': 'game', 'gameId': a.gameId, 'action': 'teleport'});
      request(c, 5, {'kind': 'chess', 'gameId': a.gameId});
      await t.pump();
      expect(ran, hasLength(2));
    });
  });
}
