import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/disc_sets.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';

/// Test seam: replaces [runGameAction] so tests can observe the dispatch.
@visibleForTesting
Future<void> Function(WidgetRef ref, BuildContext context, Game game, GameState gameState, GameAction action)? debugRunGameAction;

/// Test seam: replaces [TaskQueueService.startDownloads] for [runGameAction].
@visibleForTesting
Future<void> Function(WidgetRef ref, BuildContext context, List<Game> games, String? consoleId)? debugStartGameDownloads;

/// What Download on [game] queues: a grouped multi-disc game's other discs
/// too when Settings says so (see [discsToDownload]). [catalog]: the
/// console's games, to find the set of a [game] that does not carry it.
List<Game> gamesToDownload(WidgetRef ref, Game game, {Iterable<Game>? catalog}) {
  final states = ref.read(gameStateManagerProvider);
  return discsToDownload(
    game,
    all: ref.read(settingsProvider.notifier).downloadAllDiscs(game.consoleId),
    catalog: catalog,
    statusOf: (id) => states[id]?.status,
  );
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
      await (debugStartGameDownloads ?? TaskQueueService.startDownloads)(ref, context, gamesToDownload(ref, game), game.consoleId);
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
            Padding(padding: pad, child: _favoriteButton()),
            for (final button in _actionButtons(context)) Padding(padding: pad, child: button),
          ],
        ),
      ),
    );
  }

  Widget _favoriteButton() {
    final buttonSize = isNarrow ? 18.0 : 24.0;
    return Tooltip(
      message: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      child: IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: buttonSize,
          color: isFavorite ? Colors.red : null,
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
