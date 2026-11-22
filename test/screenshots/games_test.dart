// The games side on the kit: the games list in each layout, its header with
// and without the filter badge, the no-match state, the console list and a
// game's page, in the style CARDS picks.
//
//   SCREENSHOTS=1 flutter test test/screenshots/games_test.dart --dart-define=DEVICE=odin2 --dart-define=CARDS=vita

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/companion/companion_app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/services/dual_screen/companion_payload.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/widgets/game_details/game_box_view.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_page.dart';

import 'support.dart';
import 'fakes.dart';

/// Art without the network: a coloured box per picture, a cover's shape for
/// the cover, a wide one for the rest.
Widget _art(BuildContext context, String url, {BoxFit fit = BoxFit.cover, Alignment alignment = Alignment.center, Widget? placeholder, Widget? fallback}) {
  final hue = (url.hashCode % 360).toDouble();
  final cover = url.contains('boxart');
  return SizedBox(
    width: cover ? 86 : null,
    height: cover ? 120 : null,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HSLColor.fromAHSL(1, hue, 0.55, 0.45).toColor(), HSLColor.fromAHSL(1, (hue + 50) % 360, 0.6, 0.25).toColor()],
        ),
      ),
    ),
  );
}

/// Chrono Trigger's LaunchBox record, as the page reads it.
class _Record extends LaunchboxService {
  @override
  Future<LaunchboxGame?> lookup(String platform, int id) async => const LaunchboxGame(
        id: 1,
        name: 'Chrono Trigger',
        developer: 'Square',
        publisher: 'Square',
        releaseDate: 19950811,
        maxPlayers: 1,
        cooperative: false,
        esrb: 'E - Everyone',
        overview: 'Crono and his friends travel through time to stop Lavos, a creature that will destroy the world in 1999 AD. '
            'Thirteen endings depend on when and how the party faces it.',
        images: [
          LaunchboxImage(LaunchboxImageType.screenshot, 'shot1.jpg'),
          LaunchboxImage(LaunchboxImageType.screenshot, 'shot2.jpg'),
          LaunchboxImage(LaunchboxImageType.boxFront, 'front.jpg'),
          LaunchboxImage(LaunchboxImageType.boxBack, 'back.jpg'),
        ],
      );
}

void main() {
  screenshotSetUp();
  final style = shotStyle.cards.name;
  final games = snesGames();

  for (final layout in GameLayout.values) {
    final appStyle = AppStyle(cards: shotStyle.cards, gameLayout: layout);
    final tag = 'games_${style}_${layout.name}';

    testWidgets('$tag touch', (t) async {
      await launch(t, const HomeScreen(), style: appStyle, overrides: gamesOverrides(games));
      await snap(t, '${tag}_touch');
    }, skip: !screenshotsEnabled);

    // A pad: focus on the second game (the cover flow's ring round its centre card).
    testWidgets('$tag pad', (t) async {
      await launch(t, const HomeScreen(), style: appStyle, overrides: gamesOverrides(games, selected: {games[2].gameId}));
      await key(t, LogicalKeyboardKey.arrowRight);
      await snap(t, '${tag}_pad');
    }, skip: !screenshotsEnabled);
  }

  testWidgets('games badge', (t) async {
    final catalog = FakeCatalog(CatalogState(
      games: games,
      cachedFilteredGames: games.take(5).toList(),
      cachedTotalCount: 5,
      filter: const CatalogFilter().copyWith(regions: {'Japan', 'USA'}, showFavoritesOnly: true),
    ));
    await launch(t, const HomeScreen(), overrides: gamesOverrides(games, catalog: catalog));
    await snap(t, 'games_${style}_badge');
  }, skip: !screenshotsEnabled);

  testWidgets('games no match', (t) async {
    final catalog = FakeCatalog(CatalogState(
      games: games,
      cachedFilteredGames: const [],
      cachedTotalCount: 0,
      filterText: 'zelda',
      filter: const CatalogFilter().copyWith(regions: {'Japan'}),
    ));
    await launch(t, const HomeScreen(), overrides: gamesOverrides(games, catalog: catalog));
    await snap(t, 'games_${style}_nomatch');
  }, skip: !screenshotsEnabled);

  testWidgets('games working', (t) async {
    final running = {
      for (final i in [0, 3]) games[i].gameId: GameState(game: games[i], status: GameStatus.downloading, currentProgress: 0.42),
      games[5].gameId: GameState(game: games[5], status: GameStatus.extracting, currentProgress: 0.7),
    };
    await launch(t, const HomeScreen(), overrides: gamesOverrides(games, statuses: {0: GameStatus.downloading, 3: GameStatus.downloading}, running: running));
    await snap(t, 'games_${style}_working');
  }, skip: !screenshotsEnabled);

  for (final pad in [false, true]) {
    testWidgets('consoles ${pad ? 'pad' : 'touch'}', (t) async {
      await launch(t, const ConsoleGridScreen(), overrides: consolesOverrides());
      if (pad) await key(t, LogicalKeyboardKey.arrowRight);
      await snap(t, 'consoles_${style}_${pad ? 'pad' : 'touch'}');
    }, skip: !screenshotsEnabled);
  }

  final chrono = Game(
    title: 'Chrono Trigger (USA)',
    url: 'https://example.invalid/snes/chrono.zip',
    size: 4 << 20,
    consoleId: 'snes',
    details: const GameDetails(
      boxart: 'https://example.invalid/boxart/chrono.png',
      rating: 4.6,
      ratingCount: 812,
      genres: ['Role-Playing'],
      maxPlayers: 1,
      launchboxId: 1,
      launchboxPlatform: 'Super Nintendo Entertainment System',
    ),
  );
  for (final (name, status) in [('ready', GameStatus.ready), ('downloading', GameStatus.downloading)]) {
    for (final pad in [false, true]) {
      testWidgets('details $name ${pad ? 'pad' : 'touch'}', (t) async {
        GameDetailsPage.debugImageBuilder = _art;
        addTearDown(() => GameDetailsPage.debugImageBuilder = null);
        await launch(t, GameDetailsPage(game: chrono),
            overrides: [...gamesOverrides([chrono, ...games], statuses: {0: status}), launchboxServiceProvider.overrideWithValue(_Record())]);
        await realWait(t, 600);
        if (pad) await key(t, LogicalKeyboardKey.arrowDown);
        await snap(t, 'details_${style}_${name}_${pad ? 'pad' : 'touch'}');
      }, skip: !screenshotsEnabled);
    }
  }

  // The box at the page's end: as it opens, then turned to the back.
  testWidgets('details box', (t) async {
    GameDetailsPage.debugImageBuilder = _art;
    addTearDown(() => GameDetailsPage.debugImageBuilder = null);
    await launch(t, GameDetailsPage(game: chrono),
        overrides: [...gamesOverrides([chrono, ...games]), launchboxServiceProvider.overrideWithValue(_Record())]);
    await realWait(t, 600);
    final scroll = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    // The sheet is built lazily: its end is known only once it is near.
    for (var i = 0; i < 4; i++) {
      scroll.jumpTo(scroll.maxScrollExtent);
      await frames(t, 2);
    }
    final box = find.byType(GameBox3D);
    final turns = box.evaluate().isNotEmpty; // flat on the framebuffer handheld
    await snap(t, 'details_${style}_box', keep: turns);
    if (!turns) return;
    Focus.of(t.element(find.descendant(of: box, matching: find.byType(GestureDetector)).first)).requestFocus();
    await frames(t);
    // Half way to the back, then the back.
    await key(t, LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump(const Duration(milliseconds: 120));
    await snap(t, 'details_${style}_box_turning', keep: true);
    await frames(t, 5);
    await snap(t, 'details_${style}_box_back');
  }, skip: !screenshotsEnabled);

  // The second screen with a multi-disc game: its discs and update as rows,
  // each with its own button.
  testWidgets('companion details', (t) async {
    const channel = MethodChannel('retro_toolbox/companion');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    CompanionScreen.debugImageBuilder = _art;
    addTearDown(() => CompanionScreen.debugImageBuilder = null);
    await launch(t, CompanionScreen(channel: channel, lookup: (_, __) => _Record().lookup('', 1), invalidate: () {}));
    final payload = detailsPayload(chrono,
        state: GameState(game: chrono, status: GameStatus.ready, availableActions: const {GameAction.download}),
        files: [
          {'section': 'Discs', 'label': 'Disc 1', 'gameId': 'snes/d1', 'size': 650 << 20, 'status': 'Extracted', 'action': null},
          {'section': 'Discs', 'label': 'Disc 2', 'gameId': 'snes/d2', 'size': 640 << 20, 'status': 'Downloading', 'action': 'pause'},
          {'section': 'Discs', 'label': 'Disc 3', 'gameId': 'snes/d3', 'size': 610 << 20, 'status': 'Ready', 'action': 'download'},
          {'section': 'Updates', 'label': 'v1.1 (Translation fix)', 'gameId': 'snes/u1', 'size': 2 << 20, 'status': 'Ready', 'action': 'download'},
        ]);
    await messenger.handlePlatformMessage(channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall('update', jsonEncode(payload))), (_) {});
    await realWait(t, 600);
    await snap(t, 'companion_${style}_details', keep: true);
    final scroll = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    // Down a page: the sheet is built lazily, so Discs is found on the way.
    for (var i = 0; i < 6 && find.text('Discs').evaluate().isEmpty; i++) {
      scroll.jumpTo(math.min(scroll.maxScrollExtent, scroll.pixels + 120));
      await frames(t, 2);
    }
    final discs = t.getTopLeft(find.text('Discs')).dy;
    scroll.jumpTo(math.min(scroll.maxScrollExtent, scroll.pixels + discs - 24));
    await frames(t);
    await snap(t, 'companion_${style}_files');
  }, skip: !screenshotsEnabled);
}
