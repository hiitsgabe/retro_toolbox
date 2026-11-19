import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/disc_sets.dart';
import 'package:retro_toolbox/services/filtering_service.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';

/// Test seam: replaces [runGameAction] so tests can observe the dispatch.
@visibleForTesting
Future<void> Function(WidgetRef ref, BuildContext context, Game game, GameState gameState, GameAction action)? debugRunGameAction;

/// Test seam: replaces [TaskQueueService.startDownloads] for [downloadGames].
@visibleForTesting
Future<void> Function(WidgetRef ref, BuildContext context, List<Game> games, String? consoleId)? debugStartGameDownloads;

/// What Download on [game] queues: for a box set, every game in it in the
/// version the list would show for it (the one the user has, then the
/// filter's regions, else the default order, under the same filters),
/// skipping what is already on disk, queued or done; a multi-disc version's
/// other discs too when Settings says so (see [discsToDownload]). [catalog]:
/// the console's games, to find the set of a [game] that does not carry it.
Future<List<Game>> gamesToDownload(WidgetRef ref, Game game, {Iterable<Game>? catalog}) async {
  final all = ref.read(settingsProvider.notifier).downloadAllDiscs(game.consoleId);
  final group = game.group;
  if (group != null && group.isBoxSet) {
    // The owned games the list is ordered by (disk and in flight), and the
    // session's own states (a download that finished since).
    final onDisk = await ref.read(catalogProvider.notifier).ownedGameIds();
    final states = ref.read(gameStateManagerProvider);
    GameStatus? statusOf(String id) => states[id]?.status;
    bool wants(Game g) => !onDisk.contains(g.gameId) && wantsDownload(statusOf(g.gameId));
    final catalogState = ref.read(catalogProvider);
    final input = FilterInput(
      games: catalogState.games,
      filterText: '',
      filter: catalogState.filter,
      limit: 0,
      favoriteGameIds: catalogState.filter.showFavoritesOnly ? ref.read(favoritesProvider).gameIds : null,
      groupVersions: true,
      ownedGameIds: {...onDisk, for (final g in group.files) if (!wantsDownload(statusOf(g.gameId))) g.gameId},
    );
    return [
      for (final member in group.members)
        if (FilteringService.entryFor(member, input) case final entry?)
          for (final d in discsToDownload(entry, all: all, statusOf: statusOf))
            if (wants(d)) d,
    ];
  }
  // Discs on disk have their state only once something watches them: the
  // disk set stands in for it.
  final onDisk = all ? await ref.read(catalogProvider.notifier).ownedGameIds() : const <String>{};
  final states = ref.read(gameStateManagerProvider);
  return discsToDownload(game, all: all, catalog: catalog, statusOf: (id) => onDisk.contains(id) ? GameStatus.extracted : states[id]?.status);
}

/// The one place a [GameAction] turns into a task-queue call; used by the row
/// buttons and the game action menu.
Future<void> runGameAction(WidgetRef ref, BuildContext context, Game game, GameState gameState, GameAction action) async {
  if (debugRunGameAction != null) return debugRunGameAction!(ref, context, game, gameState, action);
  switch (action) {
    case GameAction.retryDownload when gameState.isTransfer:
      TaskQueueService.retryTransfer(ref, game.gameId);
    case GameAction.download:
    case GameAction.retryDownload:
      await downloadGames(ref, context, [game], game.consoleId);
    case GameAction.pause:
      TaskQueueService.pauseDownloadTask(ref, game.gameId);
    case GameAction.resume:
      TaskQueueService.resumeDownloadTask(ref, game.gameId);
    case GameAction.cancel:
      TaskQueueService.cancelTask(ref, game, gameState);
    case GameAction.extract when gameState.isTransfer && gameState.outputPath != null:
      TaskQueueService.enqueueArchiveExtraction(ref, context, gameState.outputPath!);
    case GameAction.extract:
    case GameAction.retryExtraction:
      TaskQueueService.startExtraction(ref, game.gameId);
    case GameAction.loading:
    case GameAction.none:
      break;
  }
}

/// Download on each of [games], queued as one batch: a page's Download all
/// gets one sign-in or keys check and one message, not one per file.
Future<void> downloadGames(WidgetRef ref, BuildContext context, List<Game> games, String? consoleId) async {
  final queue = <Game>[];
  for (final g in games) {
    queue.addAll(await gamesToDownload(ref, g));
  }
  if (!context.mounted) return;
  if (queue.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Already downloaded')));
    return;
  }
  await (debugStartGameDownloads ?? TaskQueueService.startDownloads)(ref, context, queue, consoleId);
}

/// The game page's (and the second screen's) button for each action it shows.
const gameActionLabels = {
  GameAction.download: 'Download',
  GameAction.pause: 'Pause',
  GameAction.resume: 'Resume',
  GameAction.cancel: 'Cancel',
  GameAction.extract: 'Extract',
  GameAction.retryDownload: 'Retry download',
  GameAction.retryExtraction: 'Retry extraction',
};

const gameActionIcons = {
  GameAction.download: Icons.download_rounded,
  GameAction.pause: Icons.pause_rounded,
  GameAction.resume: Icons.play_arrow_rounded,
  GameAction.cancel: Icons.close_rounded,
  GameAction.extract: Icons.unarchive_outlined,
  GameAction.retryDownload: Icons.refresh_rounded,
  GameAction.retryExtraction: Icons.refresh_rounded,
};

/// A row's small icon buttons, in [GameState.availableActions] order.
const _rowButtons = {
  GameAction.download: ('Download', Icons.download),
  GameAction.pause: ('Pause', Icons.pause),
  GameAction.resume: ('Resume', Icons.play_arrow),
  GameAction.cancel: ('Cancel', Icons.close),
  GameAction.extract: ('Extract', Icons.archive),
  GameAction.retryDownload: ('Retry Download', Icons.refresh),
  GameAction.retryExtraction: ('Retry Extraction', Icons.refresh),
};

/// A row's favourite and action buttons, with the app's providers.
class GameActionButtons extends ConsumerWidget {
  final Game game;
  final GameState gameState;
  final bool isNarrow;

  const GameActionButtons({
    super.key,
    required this.game,
    required this.gameState,
    this.isNarrow = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(favoritesProvider).isFavorite(game.gameId);
    return GameActionButtonsView(
      gameState: gameState,
      isFavorite: isFavorite,
      isNarrow: isNarrow,
      onFavorite: () => ref.read(favoritesProvider.notifier).toggleFavorite(game.gameId),
      onAction: (action) => runGameAction(ref, context, game, gameState, action),
    );
  }
}

/// A row's favourite and action buttons, drawn from data: the main screen
/// runs the presses itself, the second screen sends them to it.
class GameActionButtonsView extends StatelessWidget {
  const GameActionButtonsView({
    super.key,
    required this.gameState,
    required this.isFavorite,
    required this.onFavorite,
    required this.onAction,
    this.isNarrow = false,
  });

  final GameState gameState;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final ValueChanged<GameAction> onAction;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(horizontal: Platform.isAndroid ? 0 : 8);
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: pad, child: _favoriteButton(context)),
            for (final button in _actionButtons(context)) Padding(padding: pad, child: button),
          ],
        ),
      ),
    );
  }

  Widget _favoriteButton(BuildContext context) {
    final buttonSize = isNarrow ? 18.0 : 24.0;
    return Tooltip(
      message: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      child: IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: buttonSize,
          color: isFavorite ? StyleTokens.of(context).error : null,
        ),
        onPressed: onFavorite,
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  List<Widget> _actionButtons(BuildContext context) {
    final buttonSize = isNarrow ? 18.0 : 24.0;
    return [
      for (final action in gameState.availableActions)
        if (_rowButtons[action] case (final tooltip, final icon))
          Tooltip(
            message: tooltip,
            child: IconButton(
              icon: Icon(icon, size: buttonSize),
              onPressed: () => onAction(action),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          )
        else if (action == GameAction.loading)
          SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: SizedBox(
                width: buttonSize,
                height: buttonSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
    ];
  }
}
