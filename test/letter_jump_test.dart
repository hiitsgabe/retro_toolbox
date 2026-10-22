import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
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
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/utils/letter_jump.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/game_list/game_list.dart';
import 'package:retro_toolbox/widgets/game_list/letter_jump.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalogService extends CatalogService {
  _FakeCatalogService(this.games);
  final List<Game> games;

  @override
  Future<List<Game>> loadCatalog(String consoleId,
          {String? iaAccessKey, String? iaSecretKey, String? authToken, void Function(int done, int total)? onProgress, void Function(String status)? onStatus}) async =>
      games;
}

class _FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  _FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDownloads extends StateNotifier<DownloadState> implements DownloadNotifier {
  _FakeDownloads() : super(const DownloadState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeAppState extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeAppState() : super(const AppState(selectedConsole: _console));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _console = Console(id: 'con', name: 'Con', urls: []);

Game _game(String title) => Game(title: title, url: 'https://h/${Uri.encodeComponent(title)}.zip', size: 1, consoleId: 'con');

/// 50 games each under A, B and C, so C starts past the first 64-game page.
final _games = [
  for (final l in ['A', 'B', 'C'])
    for (var i = 0; i < 50; i++) _game('$l game ${i.toString().padLeft(2, '0')}'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('letter_jump');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );

  group('letterOf', () {
    test('files a title the way the name sort orders it', () {
      expect(letterOf('bomberman'), 'B');
      expect(letterOf('007 Racing'), '#');
      expect(letterOf('[BIOS]'), '#');
      expect(letterOf('  bomberman'), '#'); // a leading space sorts before a
      expect(letterOf(''), '#');
      expect(letterOf('Éric Cantona'), 'É');
    });
  });

  group('letterJumpTarget', () {
    const titles = ['Alpha', 'Apex', 'Bravo', '2 Fast', 'Delta', 'Beta'];

    test('R1 goes to the first title of the next letter present', () {
      expect(letterJumpTarget(titles, 'Alpha', forward: true), (letter: 'B', index: 2));
      expect(letterJumpTarget(titles, 'Bravo', forward: true), (letter: 'D', index: 4)); // no C
    });

    test('L1 goes to the first title of the previous letter', () {
      expect(letterJumpTarget(titles, 'Delta', forward: false), (letter: 'B', index: 2));
      expect(letterJumpTarget(titles, 'Apex', forward: false), (letter: '#', index: 3));
    });

    test('stops at either end', () {
      expect(letterJumpTarget(titles, 'Delta', forward: true), isNull);
      expect(letterJumpTarget(titles, '2 Fast', forward: false), isNull);
      expect(letterJumpTarget(const [], 'Alpha', forward: true), isNull);
    });

    test('with nothing focused, R1 starts at the first letter and L1 at the last', () {
      expect(letterJumpTarget(titles, null, forward: true)?.letter, '#');
      expect(letterJumpTarget(titles, null, forward: false)?.letter, 'D');
    });

    test('titles the sort puts after z come after Z, so the ends stay the ends', () {
      // Name order: lowercased, by code unit.
      const tail = ['Aero', 'Bomberman', 'Zelda', '~Tilde', 'Éric Cantona', 'Ōkami'];
      expect(letterJumpTarget(tail, 'Aero', forward: false), isNull);
      expect(letterJumpTarget(tail, 'Zelda', forward: true), (letter: '~', index: 3));
      expect(letterJumpTarget(tail, '~Tilde', forward: true), (letter: 'É', index: 4));
      expect(letterJumpTarget(tail, 'Ōkami', forward: true), isNull);
      expect(letterJumpTarget(tail, null, forward: true)?.letter, 'A');
    });
  });

  group('CatalogNotifier.letterJump', () {
    test('finds the next letter past the loaded page and loads up to it', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(overrides: [
        catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService(_games))),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(catalogProvider.notifier);
      await notifier.loadCatalog(_console);
      expect(container.read(catalogProvider).paginatedFilteredGames, hasLength(64));

      final fromB = container.read(catalogProvider).paginatedFilteredGames.firstWhere((g) => g.title.startsWith('B'));
      final jump = await notifier.letterJump(fromB, forward: true);
      expect(jump?.letter, 'C');
      final shown = container.read(catalogProvider).paginatedFilteredGames;
      final index = shown.indexWhere((g) => g.gameId == jump!.gameId);
      expect(index, greaterThanOrEqualTo(64));
      expect(shown[index].title, startsWith('C'));

      expect((await notifier.letterJump(fromB, forward: false))?.letter, 'A');
      expect(await notifier.letterJump(shown[index], forward: true), isNull);
    });

    test('a jump racing a page load shows every game once', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(overrides: [
        catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService(_games))),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(catalogProvider.notifier);
      await notifier.loadCatalog(_console);
      final fromB = container.read(catalogProvider).paginatedFilteredGames.firstWhere((g) => g.title.startsWith('B'));

      await Future.wait([notifier.letterJump(fromB, forward: true), notifier.loadMoreItems()]);
      final ids = [for (final g in container.read(catalogProvider).paginatedFilteredGames) g.gameId];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, [for (final g in _games.take(ids.length)) g.gameId]);
    });
  });

  testWidgets('R1 in the list focuses the first B game and flashes B', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1000, 700);
    addTearDown(t.view.reset);
    late CatalogNotifier catalog;
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      overrides: [
        catalogProvider.overrideWith((ref) => catalog = CatalogNotifier(ref, _FakeCatalogService(_games))),
        gameStateProvider.overrideWith((ref, game) => GameState(game: game, status: GameStatus.ready, isInteractable: true, availableActions: const {})),
        favoritesProvider.overrideWith((ref) => _FakeFavorites()),
        downloadProvider.overrideWith((ref) => _FakeDownloads()),
        appStateProvider.overrideWith((ref) => _FakeAppState()),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: const Scaffold(body: LetterJump(child: GameList())),
      ),
    ));
    await t.runAsync(() => catalog.loadCatalog(_console));
    await t.pumpAndSettle();

    String focusedTitle() =>
        FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<GameCardActions>()!.game.title;
    expect(focusedTitle(), 'A game 00');

    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
    expect(find.text('B'), findsOneWidget); // the flash
    await t.pumpAndSettle();
    expect(focusedTitle(), 'B game 00');

    await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(focusedTitle(), 'A game 00');

    // Sorted by anything but name, L1/R1 keep paging six rows.
    catalog.setSort(CatalogSort.sizeDesc);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(focusedTitle(), 'A game 06');
  });
}
