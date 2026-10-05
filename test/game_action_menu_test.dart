import 'dart:async';
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
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  final toggled = <String>[];

  @override
  Future<void> toggleFavorite(String gameId) async => toggled.add(gameId);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  final toggled = <String>[];

  @override
  void toggleGameSelection(String gameId) {
    toggled.add(gameId);
    final sel = {...state.selectedGames};
    if (!sel.remove(gameId)) sel.add(gameId);
    state = CatalogState(selectedGames: sel);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _game = Game(
  title: 'A Very Long Sample Game Title That Would Be Cut Off In The List Row',
  url: 'https://example.com/files/sample.zip',
  size: 1024,
  consoleId: 'con',
);

void main() {
  late _FakeFavorites favorites;
  late _FakeCatalog catalog;
  late List<(Game, GameAction)> ran;

  setUp(() {
    favorites = _FakeFavorites();
    catalog = _FakeCatalog();
    ran = [];
    debugRunGameAction = (ref, context, game, state, action) async => ran.add((game, action));
  });
  tearDown(() => debugRunGameAction = null);

  Future<void> pump(WidgetTester t, Widget card, {GameState? state}) async {
    final nav = GlobalKey<NavigatorState>();
    final gs = state ??
        const GameState(
          game: _game,
          status: GameStatus.ready,
          availableActions: {GameAction.download},
        );
    await t.pumpWidget(ProviderScope(
      overrides: [
        gameStateProvider.overrideWith((ref, game) => gs),
        favoritesProvider.overrideWith((ref) => favorites),
        catalogProvider.overrideWith((ref) => catalog),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(
          body: Column(children: [
            TextButton(autofocus: true, onPressed: () {}, child: const Text('Above')),
            SizedBox(width: 800, height: 120, child: card),
          ]),
        ),
      ),
    ));
    await t.pump();
  }

  Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

  bool onCard(WidgetTester t, Type card) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    var inCard = false, inInner = false;
    ctx.visitAncestorElements((e) {
      if (e.widget.runtimeType == card) inCard = true;
      if (e.widget is Checkbox || e.widget is IconButton) inInner = true;
      return true;
    });
    return inCard && !inInner;
  }

  testWidgets('a row is one focus stop; inner controls never take focus', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(onCard(t, GameRow), isTrue);
    expect(FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<InkWell>(), isNotNull);
    for (final k in [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.tab]) {
      await t.sendKeyEvent(k);
      await t.pump();
      final ctx = FocusManager.instance.primaryFocus!.context!;
      expect(ctx.findAncestorWidgetOfExactType<Checkbox>(), isNull);
      expect(ctx.findAncestorWidgetOfExactType<IconButton>(), isNull);
    }
  });

  testWidgets('a grid item is one focus stop', (t) async {
    await pump(t, const GameGridItem(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(onCard(t, GameGridItem), isTrue);
  });

  testWidgets('enter opens the menu; Download runs the action and closes it; focus returns', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();

    expect(inSheet(find.text(_game.title)), findsOneWidget);
    expect(inSheet(find.text('Ready')), findsOneWidget);
    expect(inSheet(find.text('Download')), findsOneWidget);
    expect(inSheet(find.text('Add to favourites')), findsOneWidget);
    expect(inSheet(find.text('Select')), findsOneWidget);

    // First action tile is focused.
    expect(Focus.of(t.element(inSheet(find.text('Download')))).hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(ran, [(_game, GameAction.download)]);
    expect(onCard(t, GameRow), isTrue);
  });

  testWidgets('an action still runs, with a live ref, after the card unmounts', (t) async {
    final show = ValueNotifier(true);
    final read = <Object?>[];
    debugRunGameAction = (ref, context, game, state, action) async {
      read.add(ref.read(favoritesProvider)); // throws if ref is disposed
      ran.add((game, action));
    };
    await pump(
        t,
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, on, __) => on ? const GameRow(game: _game) : const SizedBox(),
        ));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    show.value = false;
    await t.pump();
    expect(find.byType(GameRow), findsNothing);

    await t.tap(inSheet(find.text('Download')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(ran, [(_game, GameAction.download)]);
    expect(read, hasLength(1));
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('actions are listed in availableActions order', (t) async {
    await pump(t, const GameRow(game: _game),
        state: const GameState(
          game: _game,
          status: GameStatus.downloading,
          availableActions: {GameAction.cancel, GameAction.pause},
        ));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(t.getTopLeft(inSheet(find.text('Cancel'))).dy, lessThan(t.getTopLeft(inSheet(find.text('Pause'))).dy));
  });

  testWidgets('favourite and select tiles use the providers', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.tap(inSheet(find.text('Add to favourites')));
    await t.pumpAndSettle();
    expect(favorites.toggled, [_game.gameId]);
    await t.tap(inSheet(find.text('Select')));
    await t.pumpAndSettle();
    expect(catalog.toggled, [_game.gameId]);
  });

  testWidgets('selectable: false has no Select tile', (t) async {
    await pump(t, const GameRow(game: _game, selectable: false));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(inSheet(find.text('Download')), findsOneWidget);
    expect(inSheet(find.text('Select')), findsNothing);
  });

  testWidgets('escape closes the menu and focus returns to the card', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(onCard(t, GameRow), isTrue);
  });

  testWidgets('tapping the card body opens the menu (touch)', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.tap(find.text('Ready').first, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('holding Enter on a card opens the menu once and runs nothing', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await t.pump();
    }
    await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(ran, isEmpty);
  });

  testWidgets('focus stays in the sheet when the focused Select tile disappears', (t) async {
    catalog.state = CatalogState(selectedGames: {_game.gameId});
    await pump(t, const GameRow(game: _game),
        state: const GameState(game: _game, status: GameStatus.ready, isInteractable: false, availableActions: {GameAction.download}));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // favourites
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // Unselect
    await t.pump();
    expect(Focus.of(t.element(inSheet(find.text('Unselect')))).hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(inSheet(find.text('Unselect')), findsNothing);
    expect(inSheet(find.text('Select')), findsNothing);
    final node = FocusManager.instance.primaryFocus;
    expect(node, isNot(isA<FocusScopeNode>()));
    expect(node?.context?.findAncestorWidgetOfExactType<BottomSheet>(), isNotNull);
    expect(Focus.of(t.element(inSheet(find.text('Filters')))).hasFocus, isTrue); // the tile that moved up
  });

  testWidgets('escape while an action runs does not drop it', (t) async {
    final gate = Completer<void>();
    debugRunGameAction = (ref, context, game, state, action) async {
      await gate.future;
      ran.add((game, action));
    };
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.tap(inSheet(find.text('Download')));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    gate.complete();
    await t.pumpAndSettle();
    expect(ran, [(_game, GameAction.download)]);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
