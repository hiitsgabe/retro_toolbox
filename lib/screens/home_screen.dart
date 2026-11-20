import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/header/header.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/game_list/game_list.dart';
import 'package:retro_toolbox/widgets/game_list/letter_jump.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid.dart';
import 'package:retro_toolbox/widgets/game_grid/game_cover_flow.dart';
import 'package:retro_toolbox/widgets/footer/footer.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/widgets/common/hammer_loader.dart';

/// Tells [HomeScreen] when a page covers it. Popups (sheets, dialogs, menus)
/// are not page routes and leave it up, and neither does the game details page,
/// which shows the game the second screen already shows. Its pop needs no
/// filter: it only says the list is up again, which it never stopped being.
class GamesRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != gameDetailsRouteName) super.didPush(route, previousRoute);
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static final routeObserver = GamesRouteObserver();

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with RouteAware {
  late final StateController<bool> _gamesScreen;
  late final StateController<Game?> _focusedGame;
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _gamesScreen = ref.read(gamesScreenActiveProvider.notifier);
    _focusedGame = ref.read(focusedGameProvider.notifier);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context) case final PageRoute<dynamic> route when route != _route) {
      if (_route != null) HomeScreen.routeObserver.unsubscribe(this);
      _route = route;
      HomeScreen.routeObserver.subscribe(this, route); // calls didPush
    }
  }

  // Tells the second screen whether a game list is up. Providers must not
  // change while the tree builds or unmounts, hence the microtasks.
  void _setActive(bool active) {
    final gamesScreen = _gamesScreen;
    Future.microtask(() {
      if (gamesScreen.mounted) gamesScreen.state = active;
    });
  }

  @override
  void didPush() => _setActive(true);

  @override
  void didPopNext() => _setActive(true);

  // The focused game stays, so coming back shows its details again.
  @override
  void didPushNext() => _setActive(false);

  @override
  void dispose() {
    HomeScreen.routeObserver.unsubscribe(this);
    final focusedGame = _focusedGame;
    _setActive(false);
    Future.microtask(() {
      if (focusedGame.mounted) focusedGame.state = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    // A game from the last console must not stay on the second screen.
    ref.listen(appStateProvider.select((s) => s.selectedConsole?.id), (_, __) {
      Future.microtask(() {
        if (_focusedGame.mounted) _focusedGame.state = null;
      });
    });
    final appStateNotifier = ref.read(appStateProvider.notifier);
    final loadingStatus = ref.watch(catalogProvider.select((s) => s.loadingStatus));
    final errorMessage = ref.watch(catalogProvider.select((s) => s.errorMessage));
    final cards = ref.watch(styleProvider.select((s) => s.cards));
    final view = ref.watch(styleProvider.select((s) => s.gameView(appState.viewMode)));

    return Scaffold(
      body: GamesButtons(
        child: Column(
          children: [
            Header(
              consoles: appState.consolesList,
              selectedConsole: appState.selectedConsole,
              onConsoleSelect: appStateNotifier.selectConsole,
            ),
            Expanded(
              child: appState.consolesList.isEmpty && !appState.loading
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.dataset_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(height: 16),
                            const Text('No catalog configured', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            const SizedBox(height: 8),
                            const Text(
                              'Add a console catalog to get started: import a JSON file or load one from a URL.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SettingsScreen(consoleId: null)),
                              ),
                              icon: const Icon(Icons.settings),
                              label: const Text('Open Settings'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : appState.loading
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              HammerLoader(),
                              SizedBox(height: 16),
                              Text(loadingStatus.isEmpty ? 'Loading (this can take a while)...' : '$loadingStatus...'),
                            ],
                          ),
                        )
                      : errorMessage.isNotEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                                    const SizedBox(height: 12),
                                    Text(errorMessage, textAlign: TextAlign.center),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: appState.selectedConsole == null ? null : () => ref.read(catalogProvider.notifier).loadCatalog(appState.selectedConsole!),
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Retry'),
                                        ),
                                        // Never a dead end: a console that fails to load
                                        // leads back to the console list.
                                        OutlinedButton.icon(
                                          autofocus: true,
                                          onPressed: () => Navigator.maybePop(context),
                                          icon: const Icon(Icons.arrow_back),
                                          label: const Text('Choose another console'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : LetterJump(
                              // The card style's own layout, unless a Classic view is picked
                              // (AppStyle.gameView): those draw from the style's tokens.
                              child: (view == null ? cardStyleKit(cards)?.gameList(context) : null) ??
                                  switch (view ?? appState.viewMode) {
                                    ViewMode.grid => GameGrid(),
                                    ViewMode.coverflow => const GameCoverFlow(),
                                    ViewMode.list => GameList(),
                                  },
                            ),
            ),
            Footer(),
          ],
        ),
      ),
    );
  }
}

/// Gamepad buttons for the games screen, wherever focus is on it: Start
/// downloads the selected games (only when the header button would be enabled;
/// otherwise it defers to the enclosing Start action, DpadScope's press of the
/// focused control). Filters are behind the header's button; Select opens the task manager
/// (app-wide, see DpadScope.onOptions).
class GamesButtons extends ConsumerWidget {
  const GamesButtons({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Actions(
      actions: {
        // Not isEnabled-gated: the nearest Start binding wins even when
        // disabled (the key would be dropped), so defer explicitly.
        PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(onInvoke: (intent) {
          if (!canDownloadSelected(ref)) return Actions.maybeInvoke(context, intent);
          downloadSelected(ref, context, ref.read(appStateProvider).selectedConsole?.id);
          return null;
        }),
      },
      child: child,
    );
  }
}
