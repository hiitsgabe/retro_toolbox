import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/models/favorites_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_grid/game_cover_flow.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';
import 'package:retro_toolbox/widgets/header/filter_modal.dart';
import 'package:retro_toolbox/widgets/header/header.dart';

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState(games: [_a, _b]));
  final toggled = <String>[];

  @override
  void toggleGameSelection(String gameId) {
    toggled.add(gameId);
    final sel = {...state.selectedGames};
    if (!sel.remove(gameId)) sel.add(gameId);
    state = state.copyWith(selectedGames: sel);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDownloads extends StateNotifier<DownloadState> implements DownloadNotifier {
  _FakeDownloads(this._catalog) : super(const DownloadState());
  final _FakeCatalog _catalog;

  @override
  bool hasDownloadableSelectedGames() => _catalog.state.selectedGames.isNotEmpty;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeAppState extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeAppState() : super(const AppState(selectedConsole: Console(id: 'con', name: 'Con', urls: [])));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _a = Game(title: 'Alpha', url: 'https://example.com/files/a.zip', size: 1, consoleId: 'con');
const _b = Game(title: 'Beta', url: 'https://example.com/files/b.zip', size: 1, consoleId: 'con');

void main() {
  late _FakeCatalog catalog;
  late List<(List<Game>, String?)> started;

  setUp(() {
    catalog = _FakeCatalog();
    started = [];
    debugStartDownloads = (ref, context, games, consoleId) async => started.add((games, consoleId));
  });
  tearDown(() => debugStartDownloads = null);

  Future<void> pump(WidgetTester t, Widget card, {bool interactable = true, bool above = true}) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      overrides: [
        gameStateProvider.overrideWith((ref, game) => GameState(
              game: game,
              status: GameStatus.ready,
              isInteractable: interactable,
              availableActions: const {GameAction.download},
            )),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        catalogProvider.overrideWith((ref) => catalog),
        downloadProvider.overrideWith((ref) => _FakeDownloads(catalog)),
        appStateProvider.overrideWith((ref) => _FakeAppState()),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(
          body: GamesButtons(
            child: above
                ? Column(children: [
                    TextButton(autofocus: true, onPressed: () {}, child: const Text('Above')),
                    SizedBox(width: 800, height: 120, child: card),
                  ])
                : card,
          ),
        ),
      ),
    ));
    await t.pump();
  }

  Future<void> focusCard(WidgetTester t) async {
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
  }

  for (final (name, card) in [
    ('row', const GameRow(game: _a)),
    ('grid item', const GameGridItem(game: _a)),
  ]) {
    testWidgets('$name: X marks, Y opens the actions menu', (t) async {
      await pump(t, card);
      await focusCard(t);
      await t.sendKeyEvent(LogicalKeyboardKey.f2);
      await t.pump();
      expect(catalog.toggled, [_a.gameId]);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
      await t.pump();
      expect(catalog.toggled, [_a.gameId, _a.gameId]);

      await t.sendKeyEvent(LogicalKeyboardKey.f3);
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  }

  testWidgets('X does nothing on a card that cannot be marked', (t) async {
    await pump(t, const GameRow(game: _a), interactable: false);
    await focusCard(t);
    await t.sendKeyEvent(LogicalKeyboardKey.f2);
    await t.pump();
    expect(catalog.toggled, isEmpty);
  });

  testWidgets('task manager row (not selectable): X does nothing, Y opens the menu', (t) async {
    await pump(t, const GameRow(game: _a, selectable: false));
    await focusCard(t);
    await t.sendKeyEvent(LogicalKeyboardKey.f2);
    await t.pump();
    expect(catalog.toggled, isEmpty);
    await t.sendKeyEvent(LogicalKeyboardKey.f3);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('Start downloads the selected games once', (t) async {
    catalog.state = const CatalogState(games: [_a, _b], selectedGames: {'con/a.zip', 'con/b.zip'});
    await pump(t, const GameRow(game: _a));
    await focusCard(t);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    expect(started, hasLength(1));
    expect(started.single.$1, [_a, _b]);
    expect(started.single.$2, 'con');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('Start with nothing selected presses the focused card', (t) async {
    await pump(t, const GameRow(game: _a));
    await focusCard(t);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    expect(started, isEmpty);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('Start works from outside the list too', (t) async {
    catalog.state = const CatalogState(games: [_a, _b], selectedGames: {'con/a.zip'});
    await pump(t, const GameRow(game: _a));
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart); // focus is on "Above"
    await t.pump();
    expect(started.single.$1, [_a]);
  });

  testWidgets('Select opens the filter sheet', (t) async {
    await pump(t, const GameRow(game: _a));
    await focusCard(t);
    await t.sendKeyEvent(LogicalKeyboardKey.f4);
    await t.pumpAndSettle();
    expect(find.byType(FilterModal), findsOneWidget);
  });

  testWidgets('cover flow: Start downloads the selection, X marks and Y opens the centre game', (t) async {
    catalog.state = const CatalogState(games: [_a, _b], selectedGames: {'con/b.zip'}, cachedFilteredGames: [_a, _b]);
    await pump(t, const GameCoverFlow(), above: false);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    expect(started.single.$1, [_b]);
    expect(find.byType(BottomSheet), findsNothing);

    await t.sendKeyEvent(LogicalKeyboardKey.f2);
    await t.pump();
    expect(catalog.toggled, [_a.gameId]);
    await t.sendKeyEvent(LogicalKeyboardKey.f3);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('cover flow: Start with nothing selected opens the centre game', (t) async {
    catalog.state = const CatalogState(games: [_a, _b], cachedFilteredGames: [_a, _b]);
    await pump(t, const GameCoverFlow(), above: false);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(started, isEmpty);
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
