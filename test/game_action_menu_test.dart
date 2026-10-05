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
  void toggleGameSelection(String gameId) => toggled.add(gameId);

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
}
