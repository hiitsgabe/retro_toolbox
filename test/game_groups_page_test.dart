import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/services/game_groups.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';

import 'game_groups_support.dart';

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
    t.view.physicalSize = const Size(1240, 4000);
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

  Finder row(String label) => find.ancestor(of: find.text(label), matching: find.byType(GameFileRow));

  testWidgets('a game lists its versions with the main one marked; a version downloads with its discs', (t) async {
    final mgs = groupEntry(buildGameGroups(psxGames(['Metal Gear Solid'])).single, (_) => true)!;
    await pumpPage(t, mgs);
    expect(find.text('Versions'), findsOneWidget);
    expect(find.descendant(of: row('USA · Rev 1 · 2 discs'), matching: find.text('Main')), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    await t.tap(find.descendant(of: row('Europe · 2 discs'), matching: find.text('Download')));
    await t.pumpAndSettle();
    final (game, action) = ran.single;
    expect((game.title, game.discs.length, action), ('Metal Gear Solid (Europe) (Disc 1).zip', 2, GameAction.download));
    expect(find.byType(GameDetailsPage), findsOneWidget);
  });

  testWidgets('demos are Extras, each downloadable on its own', (t) async {
    final mgs = groupEntry(buildGameGroups(psxGames(['Metal Gear Solid'])).single, (_) => true)!;
    await pumpPage(t, mgs);
    expect(find.text('Extras'), findsOneWidget);
    await t.tap(find.descendant(of: row('USA · Demo'), matching: find.text('Download')));
    await t.pumpAndSettle();
    expect(ran.single.$1.title, 'Metal Gear Solid (USA) (Demo).zip');
  });

  testWidgets('a box set lists its games; Open shows that game with its own discs', (t) async {
    final box = groupEntry(buildGameGroups(psxGamesStartingWith('Arc the Lad Collection - ')).single, (_) => true)!;
    await pumpPage(t, box);
    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Arc the Lad III'), findsOneWidget);
    final open = find.ancestor(of: find.text('Arc the Lad III'), matching: find.byType(Row));
    await t.tap(find.descendant(of: open.first, matching: find.text('Open')));
    await t.pumpAndSettle();
    expect(find.text('Disc 2'), findsOneWidget);
    expect(find.text('Contents'), findsNothing);
  });

  testWidgets('rebuilding the page watches the same Game for every version and extra row, so no provider entry is orphaned', (t) async {
    final mgs = groupEntry(buildGameGroups(psxGames(['Metal Gear Solid'])).single, (_) => true)!;
    await pumpPage(t, mgs);
    expect(watched.where((g) => g.discs.length >= 2), isNotEmpty);
    // The same page again: its state is kept and it rebuilds.
    await pumpPage(t, mgs);
    // Every row's Game is already a provider key: a new Game per build would
    // create one more entry each time, and watched would not be empty.
    expect(watched, isEmpty);
  });

  /// Whether primary focus sits inside [finder]'s element.
  bool focusIn(Element e) {
    var inside = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((a) {
      if (a == e) inside = true;
      return !inside;
    });
    return inside;
  }

  testWidgets('the d-pad reaches every version and extra button, and Up leaves them', (t) async {
    final mgs = groupEntry(buildGameGroups(psxGames(['Metal Gear Solid'])).single, (_) => true)!;
    await pumpPage(t, mgs);
    final rows = find.byType(GameFileRow).evaluate().toList();
    expect(rows.length, greaterThan(3));
    final reached = <int>{};
    for (var step = 0; step < 80 && reached.length < rows.length; step++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      for (final (i, r) in rows.indexed) {
        if (focusIn(r)) reached.add(i);
      }
    }
    expect(reached, {for (var i = 0; i < rows.length; i++) i});
    for (var step = 0; step < 80; step++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
    }
    expect(rows.any(focusIn), isFalse, reason: 'Up goes back to the page buttons');
  });

  testWidgets('the d-pad reaches a box set Open button and A opens that game', (t) async {
    final box = groupEntry(buildGameGroups(psxGamesStartingWith('Arc the Lad Collection - ')).single, (_) => true)!;
    await pumpPage(t, box);
    final opens = find.widgetWithText(FilledButton, 'Open').evaluate().toList();
    expect(opens, isNotEmpty);
    for (var step = 0; step < 80 && !focusIn(opens.first); step++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
    }
    expect(focusIn(opens.first), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Contents'), findsNothing);
  });
}
