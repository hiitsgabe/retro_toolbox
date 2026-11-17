import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
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

class _FakeLaunchbox extends LaunchboxService {
  final asked = <(String, int)>[];
  final record = Completer<LaunchboxGame?>();

  @override
  Future<LaunchboxGame?> lookup(String platform, int id) {
    asked.add((platform, id));
    return record.future;
  }
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
    GameDetailsPage.debugImageBuilder = (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url));
  });
  tearDown(() {
    debugRunGameAction = null;
    GameDetailsPage.debugImageBuilder = null;
  });

  Future<void> pump(WidgetTester t, Widget card, {GameState? state, List<Override> overrides = const []}) async {
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
        ...overrides,
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

  Finder inPage(Finder f) => find.descendant(of: find.byType(GameDetailsPage), matching: f);

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

    expect(inPage(find.text(_game.title)), findsOneWidget);
    expect(inPage(find.text('Ready')), findsOneWidget);
    expect(inPage(find.text('Download')), findsOneWidget);
    expect(inPage(find.text('Add to favourites')), findsOneWidget);
    expect(inPage(find.text('Select')), findsOneWidget);

    // First action button is focused.
    expect(Focus.of(t.element(inPage(find.text('Download')))).hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();

    expect(find.byType(GameDetailsPage), findsNothing);
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

    await t.tap(inPage(find.text('Download')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(ran, [(_game, GameAction.download)]);
    expect(read, hasLength(1));
    expect(find.byType(GameDetailsPage), findsNothing);
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
    expect(t.getTopLeft(inPage(find.text('Cancel'))).dx, lessThan(t.getTopLeft(inPage(find.text('Pause'))).dx));
  });

  testWidgets('favourite and select buttons use the providers', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.tap(inPage(find.text('Add to favourites')));
    await t.pumpAndSettle();
    expect(favorites.toggled, [_game.gameId]);
    await t.tap(inPage(find.text('Select')));
    await t.pumpAndSettle();
    expect(catalog.toggled, [_game.gameId]);
  });

  testWidgets('selectable: false has no Select button', (t) async {
    await pump(t, const GameRow(game: _game, selectable: false));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(inPage(find.text('Download')), findsOneWidget);
    expect(inPage(find.text('Select')), findsNothing);
  });

  testWidgets('escape closes the menu and focus returns to the card', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(GameDetailsPage), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(GameDetailsPage), findsNothing);
    expect(onCard(t, GameRow), isTrue);
  });

  testWidgets('tapping the card body opens the menu (touch)', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.tap(find.text('Ready').first, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byType(GameDetailsPage), findsOneWidget);
  });

  testWidgets('tapping the cover opens the page, not the box art viewer', (t) async {
    const withArt = Game(
      title: 'Art',
      url: 'https://example.com/files/art.zip',
      size: 1,
      consoleId: 'con',
      details: GameDetails(boxart: 'https://example.com/art.png'),
    );
    final shown = <Game>[];
    debugShowBoxart = (_, g) => shown.add(g);
    addTearDown(() => debugShowBoxart = null);
    await pump(t, const GameRow(game: withArt), state: const GameState(game: withArt, status: GameStatus.ready));
    await t.tap(find.byKey(const ValueKey('boxart_con/art.zip')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.byType(GameDetailsPage), findsOneWidget);
    expect(find.byType(PhotoView), findsNothing);
    expect(shown, isEmpty);
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
    expect(find.byType(GameDetailsPage), findsOneWidget);
    expect(ran, isEmpty);
  });

  testWidgets('focus stays on the page when the focused Select button disappears', (t) async {
    catalog.state = CatalogState(selectedGames: {_game.gameId});
    await pump(t, const GameRow(game: _game),
        state: const GameState(game: _game, status: GameStatus.ready, isInteractable: false, availableActions: {GameAction.download}));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // favourites
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight); // Unselect
    await t.pump();
    expect(Focus.of(t.element(inPage(find.text('Unselect')))).hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(inPage(find.text('Unselect')), findsNothing);
    expect(inPage(find.text('Select')), findsNothing);
    final node = FocusManager.instance.primaryFocus;
    expect(node, isNot(isA<FocusScopeNode>()));
    expect(node?.context?.findAncestorWidgetOfExactType<GameDetailsPage>(), isNotNull);
    expect(Focus.of(t.element(inPage(find.text('Add to favourites')))).hasFocus, isTrue); // the button before it
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
    await t.tap(inPage(find.text('Download')));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(GameDetailsPage), findsOneWidget);
    gate.complete();
    await t.pumpAndSettle();
    expect(ran, [(_game, GameAction.download)]);
    expect(find.byType(GameDetailsPage), findsNothing);
  });

  testWidgets('a game without LaunchBox data shows its title and looks nothing up', (t) async {
    final lb = _FakeLaunchbox();
    await pump(t, const GameRow(game: _game), overrides: [launchboxServiceProvider.overrideWithValue(lb)]);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(inPage(find.text(_game.title)), findsOneWidget);
    expect(lb.asked, isEmpty);
  });

  testWidgets('a matched game keeps the logo place empty until its record arrives, then the title and overview', (t) async {
    const matched = Game(
      title: 'Sonic The Hedgehog',
      url: 'https://example.com/files/sonic.zip',
      size: 1024,
      consoleId: 'md',
      details: GameDetails(launchboxId: 7, launchboxPlatform: 'Sega Genesis'),
    );
    const overview = 'Sonic races through Green Hill Zone.';
    final lb = _FakeLaunchbox();
    await pump(t, const GameRow(game: matched),
        state: const GameState(game: matched, status: GameStatus.ready, availableActions: {GameAction.download}),
        overrides: [launchboxServiceProvider.overrideWithValue(lb)]);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(lb.asked, [('Sega Genesis', 7)]);
    // No title now to swap for the logo a moment later; the buttons are there.
    expect(inPage(find.text(matched.title)), findsNothing);
    expect(inPage(find.text('Download')), findsOneWidget);
    expect(find.text('About'), findsNothing);
    final buttonsAt = t.getTopLeft(inPage(find.text('Download')));

    // No clear logo in the record: the title takes the logo's place, nothing moves.
    lb.record.complete(const LaunchboxGame(id: 7, name: 'Sonic the Hedgehog', overview: overview, developer: 'Sonic Team'));
    await t.pumpAndSettle();
    expect(inPage(find.text(matched.title)), findsOneWidget);
    expect(t.getTopLeft(inPage(find.text('Download'))), buttonsAt);
    await t.drag(inPage(find.byType(CustomScrollView)), const Offset(0, -2000));
    await t.pumpAndSettle();
    expect(inPage(find.text(overview)), findsOneWidget);
    expect(inPage(find.text('Sonic Team')), findsOneWidget);
  });

  testWidgets('with no game actions the favourite button takes focus', (t) async {
    await pump(t, const GameRow(game: _game), state: const GameState(game: _game, status: GameStatus.extracted));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(Focus.of(t.element(inPage(find.text('Add to favourites')))).hasPrimaryFocus, isTrue);
  });

  testWidgets('the d-pad walks a long overview down to the back cover, never via the back button', (t) async {
    const matched = Game(
      title: 'Sonic The Hedgehog',
      url: 'https://example.com/files/sonic.zip',
      size: 1024,
      consoleId: 'md',
      details: GameDetails(launchboxId: 7, launchboxPlatform: 'Sega Genesis'),
    );
    const back = LaunchboxImage(LaunchboxImageType.boxBack, 'back.png');
    final lb = _FakeLaunchbox()
      ..record.complete(LaunchboxGame(
        id: 7,
        name: 'Sonic the Hedgehog',
        overview: List.filled(800, 'lorem').join(' '),
        images: [
          for (var i = 0; i < 10; i++) LaunchboxImage(LaunchboxImageType.screenshot, 'shot$i.png'),
          back,
        ],
      ));
    // Sized like real art: an empty box is no place for focus to land.
    GameDetailsPage.debugImageBuilder = (context, url, {fit = BoxFit.cover, alignment = Alignment.center, placeholder, fallback}) => SizedBox(key: ValueKey(url), width: 180, height: 240);
    await pump(t, const GameRow(game: matched),
        state: const GameState(game: matched, status: GameStatus.ready, availableActions: {GameAction.download}),
        overrides: [launchboxServiceProvider.overrideWithValue(lb)]);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();

    bool focusIn(Finder f) => f.evaluate().isNotEmpty && Focus.of(t.element(f)).hasPrimaryFocus;
    var onBackButton = false;
    for (var i = 0; i < 60 && !focusIn(find.byKey(ValueKey(back.url))); i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      onBackButton |= FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<BackButton>() != null;
    }
    expect(onBackButton, isFalse);
    expect(focusIn(find.byKey(ValueKey(back.url))), isTrue);
    expect(find.byType(GameDetailsPage), findsOneWidget);
  });

  testWidgets('the back button is not a d-pad stop: A there would close the page', (t) async {
    await pump(t, const GameRow(game: _game));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<BackButton>(), isNull);
    }
    expect(inPage(find.byType(BackButton)), findsOneWidget);
  });
}
