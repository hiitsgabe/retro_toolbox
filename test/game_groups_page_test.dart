import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
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
  _FakeCatalog([CatalogState? state, this.owned = const {}]) : super(state ?? const CatalogState());
  final Set<String> owned;
  @override
  Future<Set<String>> ownedGameIds() async => owned;
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

  Future<void> pumpPage(WidgetTester t, Game game, {Size size = const Size(1240, 4000), CatalogState? catalog, Set<String> owned = const {}}) async {
    ran = [];
    watched = [];
    debugRunGameAction = (ref, context, game, state, action) async => ran.add((game, action));
    GameDetailsPage.debugImageBuilder =
        (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url));
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        gameStateProvider.overrideWith((ref, g) {
          watched.add(g);
          return GameState(game: g, status: GameStatus.ready, availableActions: const {GameAction.download});
        }),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        catalogProvider.overrideWith((ref) => _FakeCatalog(catalog, owned)),
      ],
      child: MaterialApp(home: GameDetailsPage(game: game)),
    ));
    await t.pump();
  }

  Finder row(String label) => find.ancestor(of: find.text(label), matching: find.byType(GameFileRow));
  Finder mainIn(String label) => find.descendant(of: row(label), matching: find.text('Main'));

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

  testWidgets('opened on an owned Europe version, Europe is the main row and USA is not', (t) async {
    final group = buildGameGroups(psxGames(['Metal Gear Solid'])).single;
    final europe = groupEntry(group, (_) => true, owned: (g) => g.title.startsWith('Metal Gear Solid (Europe) (Disc'))!;
    expect(europe.title, 'Metal Gear Solid (Europe) (Disc 1).zip');
    await pumpPage(t, europe);
    expect(mainIn('Europe · 2 discs'), findsOneWidget);
    expect(mainIn('USA · Rev 1 · 2 discs'), findsNothing);
    expect(find.text('Main'), findsOneWidget);
  });

  testWidgets('a game with one version has no Versions section', (t) async {
    final box = buildGameGroups(psxGamesStartingWith('Arc the Lad Collection - ')).single;
    final iii = box.members.singleWhere((m) => memberLabel(box, m) == 'Arc the Lad III');
    expect(iii.versions, hasLength(1));
    await pumpPage(t, groupEntry(iii, (_) => true)!);
    expect(find.text('Discs'), findsOneWidget);
    expect(find.text('Versions'), findsNothing);
    expect(find.byType(GameFileRow), findsNothing);
  });

  testWidgets('Versions comes before Extras', (t) async {
    final mgs = groupEntry(buildGameGroups(psxGames(['Metal Gear Solid'])).single, (_) => true)!;
    await pumpPage(t, mgs);
    double y(String s) => t.getTopLeft(find.text(s)).dy;
    expect(y('Versions'), lessThan(y('Extras')));
  });

  /// What the focused control belongs to: a GameFileRow's label, or
  /// "open:<member>" for a Contents Open button; null otherwise.
  String? focused() {
    String? out;
    final ctx = FocusManager.instance.primaryFocus?.context;
    ctx?.visitAncestorElements((a) {
      final w = a.widget;
      if (w is GameFileRow) {
        out = w.label;
        return false;
      }
      if (w is Row && w.children.length == 2 && w.children.first is Expanded && (w.children.first as Expanded).child is Text) {
        final label = ((w.children.first as Expanded).child as Text).data;
        out = 'open:$label';
        return false;
      }
      return true;
    });
    return out;
  }

  Future<List<String>> walk(WidgetTester t, LogicalKeyboardKey key, int steps) async {
    final seen = <String>[];
    for (var step = 0; step < steps; step++) {
      await t.sendKeyEvent(key);
      await t.pumpAndSettle();
      final f = focused();
      if (f != null && !seen.contains(f)) seen.add(f);
    }
    return seen;
  }

  // D-pad on a TV-sized screen: rows below the fold.
  for (final size in const [Size(1280, 720), Size(800, 480)]) {
    testWidgets('at $size the d-pad reaches every version and extra button in order, and Up leaves them', (t) async {
      final group = buildGameGroups(psxGames(['Metal Gear Solid'])).single;
      final mgs = groupEntry(group, (_) => true)!;
      await pumpPage(t, mgs, size: size);
      final want = [for (final v in group.versions) v.label, for (final e in group.extras) extraLabel(e)];
      final down = await walk(t, LogicalKeyboardKey.arrowDown, 120);
      expect(down, want);
      await walk(t, LogicalKeyboardKey.arrowUp, 120);
      expect(focused(), isNull);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GameFileRow>(), isNull);
    });

    testWidgets('at $size the d-pad reaches every Open button and A on the last opens that game; Back returns', (t) async {
      final group = buildGameGroups(psxGamesStartingWith('Arc the Lad Collection - ')).single;
      final box = groupEntry(group, (_) => true)!;
      await pumpPage(t, box, size: size);
      final down = await walk(t, LogicalKeyboardKey.arrowDown, 120);
      expect(down, [for (final m in group.members) 'open:${memberLabel(group, m)}']);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Contents'), findsNothing);
      expect(find.textContaining('The Making of Arc the Lad'), findsWidgets);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Contents'), findsOneWidget);
    });
  }

  testWidgets('a member page shows its own extras', (t) async {
    final box = groupEntry(buildGameGroups(psxGamesStartingWith('Arc the Lad Collection - ')).single, (_) => true)!;
    await pumpPage(t, box);
    final open = find.ancestor(of: find.text('Arc the Lad II'), matching: find.byType(Row));
    await t.tap(find.descendant(of: open.first, matching: find.text('Open')));
    await t.pumpAndSettle();
    expect(find.text('Extras'), findsOneWidget);
    expect(find.text('USA · Beta · 2001-09-11'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Contents'), findsOneWidget);
  });

  group('a box member opens on the version the list would pick', () {
    final files = [psxGame('Foo Collection - Alpha (USA)'), psxGame('Foo Collection - Alpha (Europe)'), psxGame('Foo Collection - Alpha (Japan)'), psxGame('Foo Collection - Beta (USA)')];

    Future<void> openAlpha(WidgetTester t, {CatalogState? catalog, Set<String> owned = const {}}) async {
      final box = buildGameGroups(files).single;
      expect(box.isBoxSet, isTrue);
      await pumpPage(t, groupEntry(box, (_) => true)!, catalog: catalog ?? CatalogState(games: files, filter: const CatalogFilter(regions: {})), owned: owned);
      final open = find.ancestor(of: find.text('Alpha'), matching: find.byType(Row));
      await t.tap(find.descendant(of: open.first, matching: find.text('Open')));
      await t.pumpAndSettle();
    }

    testWidgets('an owned Europe version is the main one', (t) async {
      await openAlpha(t, owned: {psxGame('Foo Collection - Alpha (Europe)').gameId});
      expect(mainIn('Europe'), findsOneWidget);
      expect(mainIn('USA'), findsNothing);
    });

    testWidgets('nothing owned: the default region order picks USA', (t) async {
      await openAlpha(t);
      expect(mainIn('USA'), findsOneWidget);
    });

    testWidgets('a Japan region filter picks the Japan version', (t) async {
      await openAlpha(t, catalog: CatalogState(games: files, filter: const CatalogFilter(regions: {'Japan'})));
      expect(mainIn('Japan'), findsOneWidget);
      expect(mainIn('USA'), findsNothing);
    });
  });
}
