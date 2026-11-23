import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_group_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/disc_sets.dart';
import 'package:retro_toolbox/services/dual_screen/companion_files.dart';
import 'package:retro_toolbox/services/filtering_service.dart';
import 'package:retro_toolbox/services/game_groups.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/game_details/game_details_view.dart';
import 'package:retro_toolbox/widgets/game_details/launch_picker.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/utils/formatters.dart';

/// A game's page: its details plus everything the card can do, as buttons.
/// Actions run with the page's own ref and context (the card may unmount
/// while the page is open) and the page closes once they finish. Back is
/// ignored while an action runs (closing would dispose the ref mid-action
/// and drop it).
class GameDetailsPage extends ConsumerStatefulWidget {
  const GameDetailsPage({super.key, required this.game, this.selectable = true});

  final Game game;
  final bool selectable;

  /// Test seam: images without the network or the image cache plugin.
  @visibleForTesting
  static DetailsImageBuilder? debugImageBuilder;

  @override
  ConsumerState<GameDetailsPage> createState() => _GameDetailsPageState();
}

class _GameDetailsPageState extends ConsumerState<GameDetailsPage> {
  LaunchboxGame? _launchbox;
  bool _lookingUp = false;
  bool _busy = false;

  /// The emulator a launch is starting, for the Play button's label.
  String? _starting;
  final _scroll = ScrollController();

  /// The Game of each addon (update, DLC, mod), by the addon itself, built once: Game has no ==, and
  /// gameStateProvider keeps an entry per Game it has seen, so a new Game on
  /// every rebuild would leave an entry behind each time.
  final _addonGames = <GameAddon, Game>{};

  /// The same for each version of a multi-disc game: its entry is a copy.
  final _versionGames = <GameVersion, Game>{};

  /// The hero has scrolled away: the app bar gets a background and the title,
  /// or the sheet would scroll under a bare back button.
  final _pastHero = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    // The hero is only as tall as it needs on a handheld: the page scrolls
    // under the app bar as soon as it moves.
    _scroll.addListener(() => _pastHero.value = _scroll.offset > 48);
    // The catalog only carries the fields lists sort and filter on; the
    // rest is read from the platform file now, while the page already shows.
    final details = widget.game.details;
    final platform = details?.launchboxPlatform;
    final id = details?.launchboxId;
    if (platform != null && id != null) {
      _lookingUp = true;
      ref.read(launchboxServiceProvider).lookup(platform, id).then((lb) {
        if (!mounted) return;
        setState(() {
          _launchbox = lb;
          _lookingUp = false;
        });
      }, onError: (Object e) {
        debugPrint('LaunchBox lookup failed: $e');
        if (mounted) setState(() => _lookingUp = false);
      });
    }
    if (ref.read(launcherAvailableProvider)) ref.read(presetRefreshProvider);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pastHero.dispose();
    super.dispose();
  }

  Future<void> _run(GameState gameState, GameAction action) async {
    setState(() => _busy = true);
    try {
      await runGameAction(ref, context, widget.game, gameState, action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Launches with the resolved choice; with none (several emulators cover
  /// the system and no override was kept), asks which.
  Future<void> _play() async {
    await ref.read(launcherSessionProvider.future);
    final choice = ref.read(resolveChoiceProvider(widget.game));
    if (choice == null) return _openWith();
    await _launch(choice);
  }

  Future<void> _openWith() async {
    final session = await ref.read(launcherSessionProvider.future);
    if (!mounted) return;
    final emulators = session.covering(ref.read(gameSystemProvider(widget.game.consoleId)).slug);
    if (emulators.isEmpty) return;
    final picked = await showLaunchPicker(context, session, emulators);
    if (picked == null || !mounted) return;
    if (picked.always) ref.read(launchOverridesProvider.notifier).set(widget.game.gameId, picked.emulator.choice);
    await _launch(picked.emulator.choice);
  }

  Future<void> _launch(LaunchChoice choice) async {
    final session = await ref.read(launcherSessionProvider.future);
    final name = session.detectedFor(choice.presetId)?.label ?? session.preset(choice.presetId)?.name ?? choice.presetId;
    if (!mounted) return;
    setState(() => _starting = name);
    LaunchResult result;
    try {
      final owned = await ref.read(ownedGameProvider(widget.game).future);
      final launcher = await ref.read(gameLauncherProvider.future);
      result = owned == null ? const LaunchResult(LaunchCode.romUnreadable) : await launcher.launch(owned, choice);
    } finally {
      if (mounted) setState(() => _starting = null);
    }
    if (mounted) _report(result, name);
  }

  void _report(LaunchResult result, String emulator) {
    final (:text, :fix) = result.describe(emulator);
    if (text == null) return;
    final action = switch (fix) {
      LaunchFix.none => null,
      LaunchFix.detectAgain => SnackBarAction(label: 'Detect again', onPressed: () => ref.read(detectEmulatorsProvider)()),
      LaunchFix.chooseAnother => SnackBarAction(label: 'Choose another', onPressed: _openWith),
      LaunchFix.chooseFolder => SnackBarAction(label: 'Choose folder', onPressed: _chooseFolder),
    };
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// The library folder, as the setup wizard sets it.
  Future<void> _chooseFolder() async {
    final picked = await pickDirectory(context, title: 'Select download folder');
    if (picked == null) return;
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.saveDownloadDirectory(picked);
    await notifier.setGeneralSetting(AppSettings.downloadDir, picked);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final group = game.group;
    final gameState = ref.watch(gameStateProvider(game));
    final isFavorite = ref.watch(favoritesProvider).isFavorite(game.gameId);
    final isSelected = ref.watch(gameSelectionProvider(game.gameId));
    final actions = [
      for (final a in gameState.availableActions)
        if (gameActionLabels.containsKey(a)) a,
    ];

    // Play only for a game on disk, and only where launching works.
    final launcher = ref.watch(launcherAvailableProvider) && (gameState.status == GameStatus.downloaded || gameState.status == GameStatus.extracted);
    final system = ref.watch(gameSystemProvider(game.consoleId));
    final session = launcher ? ref.watch(launcherSessionProvider).valueOrNull : null;
    final noEmulator = session != null && session.covering(system.slug).isEmpty;
    final choice = launcher ? ref.watch(resolveChoiceProvider(game)) : null;
    final safChoice = choice != null && ref.watch(launchModeProvider(game)).valueOrNull == RomMode.saf ? session?.detectedFor(choice.presetId) : null;
    // The folder a saf emulator needs a grant for: the console's library folder.
    final safFolder = safChoice == null ? null : ref.read(settingsProvider.notifier).getDownloadDir(game.consoleId);

    (String, Widget) section(String title, List<GameAddon> list) {
      final games = [for (final a in list) _addonGames.putIfAbsent(a, () => a.toGame(game))];
      return (title, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (games.length >= 2) _DownloadAll(games: games, consoleId: game.consoleId),
        for (final (i, a) in list.indexed) GameFileRow(game: games[i], label: a.label),
      ]));
    }

    final error = gameState.errorMessage;
    // The bar: Start runs the primary, Y favourites, X selects; the other
    // actions sit beside them. For a game on disk where launching works the
    // primary is Play and the first action moves beside the others. The box
    // art opens from the cover. Focus starts in the page, at its top, so Down
    // reads it through to the bar.
    final bar = ActionBar(
      primary: launcher
          ? KitAction(
              _starting != null ? 'Starting $_starting' : (noEmulator ? 'No emulator for ${system.name}' : 'Play'),
              _starting != null || noEmulator ? null : _play,
              icon: Icons.play_arrow_rounded,
            )
          : actions.isEmpty
              ? null
              : KitAction(gameActionLabels[actions.first]!, () => _run(gameState, actions.first), icon: gameActionIcons[actions.first]),
      more: [
        // With no emulator for the system Open with has nothing to list, so
        // Detect again takes its place: the saved detection may predate an
        // emulator installed since, and with launcher mode off no resume
        // detects again.
        if (launcher)
          noEmulator
              ? KitAction('Detect again', () => ref.read(detectEmulatorsProvider)(), icon: Icons.refresh_rounded)
              : KitAction('Open with…', _starting != null ? null : _openWith, icon: Icons.apps_rounded),
        if (safChoice != null) KitAction('Open ${safChoice.label}', () => ref.read(launcherChannelProvider).openApp(safChoice.variant), icon: Icons.open_in_new_rounded),
        for (final a in actions.skip(launcher ? 0 : 1)) KitAction(gameActionLabels[a]!, () => _run(gameState, a), icon: gameActionIcons[a]),
        if (widget.selectable && (gameState.isInteractable || isSelected))
          KitAction(
            isSelected ? 'Unselect' : 'Select',
            () => ref.read(catalogProvider.notifier).toggleGameSelection(game.gameId),
            icon: isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            button: PadButton.x,
          ),
      ],
      secondary: KitAction(
        isFavorite ? 'Unfavourite' : 'Favourite',
        () => ref.read(favoritesProvider.notifier).toggleFavorite(game.gameId),
        icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        button: PadButton.y,
      ),
    );
    // "Ready" is every game not on disk yet: no line for it.
    final showStatus = error != null || gameState.status != GameStatus.ready;
    return PopScope(
      canPop: !_busy,
      child: KitArea(
        area: AppArea.games,
        child: KitBarActions(
          bar: bar,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: ValueListenableBuilder<bool>(
                valueListenable: _pastHero,
                builder: (context, past, _) => AppBar(
                  // Not a focus stop: once the focused control scrolls off the top,
                  // Down would land on it and the rest of the page is unreachable.
                  // B and touch still go back.
                  leading: const ExcludeFocus(child: BackButton()),
                  // Past the hero the page scrolls under it: the solid panel, not the
                  // transparent scaffold.
                  backgroundColor: past ? StyleTokens.of(context).solidPanel : null,
                  title: past ? Text(game.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                ),
              ),
            ),
            body: DpadFirstFocus(
              child: GameDetailsView(
                game: game,
                launchbox: _launchbox,
                launchboxPending: _lookingUp,
                scrollController: _scroll,
                imageBuilder: GameDetailsPage.debugImageBuilder,
                // The cover is the box art: its viewer, with the title and size.
                onOpenImage: (url) => url == game.boxart ? showBoxartViewer(context, game) : showImageViewer(context, url),
                status: !showStatus
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(gameState.statusText),
                          if (error != null) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          // A saf launch carries no grant: an emulator without a folder
                          // grant fails in its own UI, where we cannot see it.
                          if (safChoice != null) Text('If ${safChoice.label} says it cannot open the file, give it access to $safFolder'),
                        ],
                      ),
                discs: game.discs.length >= 2 ? GameDiscList(discs: game.discs) : null,
                sections: [
                  if (group != null && group.isBoxSet) ('Contents', GameContentsList(group: group)),
                  if (group != null && group.versions.length >= 2)
                    ('Versions', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final v in group.versions)
                        GameFileRow(game: _versionGames.putIfAbsent(v, () => v.entry), label: v.label, main: v.first.gameId == game.gameId),
                    ])),
                  if (group != null && group.extras.isNotEmpty)
                    ('Extras', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final e in group.extras) GameFileRow(game: e, label: extraLabel(e)),
                    ])),
                  if (game.updates.isNotEmpty) section('Updates', game.updates),
                  if (game.dlcs.isNotEmpty) section('DLC', game.dlcs),
                  if (game.mods.isNotEmpty) section('Mods', game.mods),
                ],
              ),
            ),
            bottomNavigationBar: bar,
          ),
        ),
      ),
    );
  }
}

/// One row per disc of a grouped game: its number, size and state, and the
/// one thing it can do now. Each runs for that disc alone and the page stays.
class GameDiscList extends StatelessWidget {
  const GameDiscList({super.key, required this.discs});

  final List<Game> discs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, disc) in discs.indexed) _DiscRow(disc: disc, number: discNumber(disc) == 0 ? i + 1 : discNumber(disc)),
      ],
    );
  }
}

class _DiscRow extends ConsumerWidget {
  const _DiscRow({required this.disc, required this.number});

  final Game disc;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(disc));
    final action = fileRowAction(state);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text('Disc $number', style: const TextStyle(fontWeight: FontWeight.w600))),
          SizedBox(width: 88, child: Text(formatBytes(disc.size), style: TextStyle(color: muted))),
          Expanded(child: Text(state.statusText, style: TextStyle(color: muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (action != null)
            FilledButton.tonalIcon(
              onPressed: () => runGameAction(ref, context, disc, state, action),
              icon: Icon(gameActionIcons[action]),
              label: Text(gameActionLabels[action]!),
            ),
        ],
      ),
    );
  }
}

/// A section's Download all: queues each of [games] that offers Download now,
/// so what is on disk, queued or running is left alone.
class _DownloadAll extends ConsumerWidget {
  const _DownloadAll({required this.games, required this.consoleId});

  final List<Game> games;
  final String? consoleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: () => downloadGames(ref, context, [
            for (final g in games)
              if (ref.read(gameStateProvider(g)).availableActions.contains(GameAction.download)) g,
          ], consoleId),
          icon: Icon(gameActionIcons[GameAction.download]),
          label: const Text('Download all'),
        ),
      ),
    );
  }
}

/// A box set's games, each opening its own page on the version the list
/// would pick: the owned one first, then the filter's regions.
class GameContentsList extends ConsumerStatefulWidget {
  const GameContentsList({super.key, required this.group});

  final GameGroup group;

  @override
  ConsumerState<GameContentsList> createState() => _GameContentsListState();
}

class _GameContentsListState extends ConsumerState<GameContentsList> {
  /// Read once; the rows do not wait for it, they ask it when tapped, so they
  /// (and the d-pad focus on them) stay as they are.
  late final Future<Set<String>> _owned = ref.read(catalogProvider.notifier).ownedGameIds();

  Future<void> _open(GameGroup member) async {
    final owned = await _owned;
    if (!mounted) return;
    final catalog = ref.read(catalogProvider);
    final input = FilterInput(
      games: catalog.games,
      filterText: '',
      filter: catalog.filter,
      limit: 0,
      groupVersions: true,
      ownedGameIds: owned,
    );
    final entry = FilteringService.entryFor(member, input) ?? groupEntry(member, (_) => true);
    if (entry == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameDetailsPage(game: entry)));
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final member in group.members)
          if (groupEntry(member, (_) => true) != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(memberLabel(group, member), style: const TextStyle(fontWeight: FontWeight.w600))),
                FilledButton.tonalIcon(
                  onPressed: () => _open(member),
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Open'),
                ),
              ]),
            ),
      ],
    );
  }
}

/// One file of a game's page (a version, an extra, an update): what it is,
/// its size and state, and the one thing it can do now. It runs for that file
/// alone and the page stays. [main]: the version the list shows.
class GameFileRow extends ConsumerWidget {
  const GameFileRow({super.key, required this.game, required this.label, this.main = false});

  final Game game;
  final String label;
  final bool main;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(game));
    final action = fileRowAction(state);
    final size = game.discs.length >= 2 ? game.discs.fold<int>(0, (sum, d) => sum + d.size) : game.size;
    return GameFileRowBody(
      label: label,
      size: size,
      status: state.statusText,
      main: main,
      action: action,
      onAction: action == null ? null : () => runGameAction(ref, context, game, state, action),
    );
  }
}

/// A file row's look, from data: [GameFileRow] feeds it the app's state, the
/// second screen what the main screen sent.
class GameFileRowBody extends StatelessWidget {
  const GameFileRowBody({super.key, required this.label, required this.size, required this.status, this.main = false, this.action, this.onAction});

  final String label;
  final int size;
  final String status;
  final bool main;
  final GameAction? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  if (main) ...[
                    const SizedBox(width: 8),
                    Text('Main', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ]),
                Text(
                  [formatBytes(size), if (status.isNotEmpty) status].join('  '),
                  style: TextStyle(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (action != null && gameActionLabels.containsKey(action))
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(gameActionIcons[action]),
              label: Text(gameActionLabels[action]!),
            ),
        ],
      ),
    );
  }
}
