import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:retro_toolbox/providers/launchbox_provider.dart';

class FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  FakeApp(super.state);
  @override
  void selectConsole(Console console) => state = state.copyWith(selectedConsole: console);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  FakeCatalog([super.state = const CatalogState()]);
  @override
  bool get groupsVersions => false;
  @override
  Future<void> loadMoreItems() async {}
  @override
  Future<void> loadCatalog(Console console) async {}
  @override
  void toggleGameSelection(String gameId) {
    final sel = {...state.selectedGames};
    if (!sel.remove(gameId)) sel.add(gameId);
    state = state.copyWith(selectedGames: sel);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeDownloads extends StateNotifier<DownloadState> implements DownloadNotifier {
  FakeDownloads() : super(const DownloadState());
  @override
  bool hasDownloadableSelectedGames() => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeGames extends StateNotifier<Map<String, GameState>> implements GameStateManager {
  /// [running]: the task states the footer and the task manager show.
  FakeGames([super.running = const {}]);
  @override
  bool isResolving(String gameId) => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeFavorites extends StateNotifier<Favorites> implements FavoritesNotifier {
  FakeFavorites() : super(Favorites(lastUpdated: DateTime(2020)));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const consoles = <Console>[
  Console(id: 'snes', name: 'Super Nintendo', urls: [], platform: 'snes'),
  Console(id: 'nes', name: 'NES', urls: [], platform: 'nes'),
  Console(id: 'n64', name: 'Nintendo 64', urls: [], platform: 'n64'),
  Console(id: 'gba', name: 'Game Boy Advance', urls: [], platform: 'gba'),
  Console(id: 'genesis', name: 'Mega Drive', urls: [], platform: 'megadrive'),
  Console(id: 'psx', name: 'PlayStation', urls: [], platform: 'psx'),
  Console(id: 'ps2', name: 'PlayStation 2', urls: [], platform: 'ps2'),
  Console(id: 'psp', name: 'PSP', urls: [], platform: 'psp'),
  Console(id: 'dreamcast', name: 'Dreamcast', urls: [], platform: 'dreamcast'),
  Console(id: 'gamecube', name: 'GameCube', urls: [], platform: 'gamecube'),
  Console(id: 'switch', name: 'Switch', urls: [], platform: 'switch'),
  Console(id: '3ds', name: 'Nintendo 3DS', urls: [], platform: '3ds'),
];

const snesTitles = [
  'Chrono Trigger (USA)',
  'Donkey Kong Country (USA)',
  'EarthBound (USA)',
  'F-Zero (USA)',
  'Final Fantasy III (USA)',
  'Kirby Super Star (USA)',
  'Mega Man X (USA)',
  'Secret of Mana (USA)',
  'Star Fox (USA)',
  'Super Mario Kart (USA)',
  'Super Mario World (USA)',
  'Super Metroid (Japan, USA)',
  'The Legend of Zelda - A Link to the Past (USA)',
  'Yoshi\'s Island (USA)',
];

List<Game> snesGames() => [
      for (final (i, title) in snesTitles.indexed)
        Game(title: title, url: 'https://example.invalid/snes/$i.zip', size: (2 + i) * 512 * 1024, consoleId: 'snes'),
    ];

/// Overrides for a games screen on SNES with [games], [selected] ids;
/// [catalog] in place of the one they make.
List<Override> gamesOverrides(List<Game> games,
        {Set<String> selected = const {}, Map<int, GameStatus> statuses = const {}, FakeCatalog? catalog, Map<String, GameState> running = const {}}) =>
    [
      appStateProvider.overrideWith((ref) => FakeApp(AppState(consoles: {for (final c in consoles) c.id: c}, selectedConsole: consoles.first))),
      catalogProvider.overrideWith((ref) =>
          catalog ??
          FakeCatalog(CatalogState(
            games: games,
            cachedFilteredGames: games,
            cachedTotalCount: games.length,
            selectedGames: selected,
          ))),
      gameStateProvider.overrideWith((ref, g) {
        final i = games.indexWhere((x) => x.gameId == g.gameId);
        final status = statuses[i] ?? GameStatus.ready;
        return GameState(
          game: g,
          status: status,
          currentProgress: 0.42,
          downloadProgress: 0.42,
          showProgressBar: status == GameStatus.downloading,
          isInteractable: status == GameStatus.ready,
          availableActions: switch (status) {
            GameStatus.ready => {GameAction.download},
            GameStatus.downloading => {GameAction.pause, GameAction.cancel},
            _ => {GameAction.none},
          },
        );
      }),
      gameStateManagerProvider.overrideWith((ref) => FakeGames(running)),
      downloadProvider.overrideWith((ref) => FakeDownloads()),
      favoritesProvider.overrideWith((ref) => FakeFavorites()),
    ];

List<Override> consolesOverrides() => [
      appStateProvider.overrideWith((ref) => FakeApp(AppState(consoles: {for (final c in consoles) c.id: c}, selectedConsole: consoles.first))),
    ];

/// The LaunchBox card waits on a store read that never finishes under
/// flutter test (sqflite): show it as loaded and off.
void launchboxLoaded(ProviderContainer c) {
  // ignore: invalid_use_of_protected_member
  c.read(launchboxProvider.notifier).state = const LaunchboxState(loading: false, wanted: {'Super Nintendo Entertainment System', 'Sony Playstation'});
}
