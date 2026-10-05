import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';

/// Test seam: replaces [runGameAction] so tests can observe the dispatch.
@visibleForTesting
Future<void> Function(WidgetRef ref, BuildContext context, Game game, GameState gameState, GameAction action)? debugRunGameAction;

/// The one place a [GameAction] turns into a task-queue call; used by the row
/// buttons and the game action menu.
Future<void> runGameAction(WidgetRef ref, BuildContext context, Game game, GameState gameState, GameAction action) async {
  if (debugRunGameAction != null) return debugRunGameAction!(ref, context, game, gameState, action);
  switch (action) {
    case GameAction.retryDownload when gameState.isTransfer:
      TaskQueueService.retryTransfer(ref, game.gameId);
    case GameAction.download:
    case GameAction.retryDownload:
      await TaskQueueService.startDownloads(ref, context, [game], game.consoleId);
    case GameAction.pause:
      TaskQueueService.pauseDownloadTask(ref, game.gameId);
    case GameAction.resume:
      TaskQueueService.resumeDownloadTask(ref, game.gameId);
    case GameAction.cancel:
      TaskQueueService.cancelTask(ref, game, gameState);
    case GameAction.extract:
    case GameAction.retryExtraction:
      TaskQueueService.startExtraction(ref, game.gameId);
    case GameAction.loading:
    case GameAction.none:
      break;
  }
}

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
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.isFavorite(game.gameId);
    
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Platform.isAndroid ? 0 : 8),
              child: _buildFavoriteButton(context, ref, isFavorite),
            ),
            ..._buildActionButtons(context, ref)
                .map((button) => Padding(
                      padding: EdgeInsets.symmetric(horizontal: Platform.isAndroid ? 0 : 8),
                      child: button,
                    )),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteButton(BuildContext context, WidgetRef ref, bool isFavorite) {
    final buttonSize = isNarrow ? 18.0 : 24.0;
    
    return Tooltip(
      message: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      child: IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: buttonSize,
          color: isFavorite ? Colors.red : null,
        ),
        onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(game.gameId),
        constraints: BoxConstraints(minWidth: 18, minHeight: 18),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  List<Widget> _buildActionButtons(BuildContext context, WidgetRef ref) {
    final List<Widget> buttons = [];
    final buttonSize = isNarrow ? 18.0 : 24.0;
    final buttonConstraints = BoxConstraints(minWidth: 18, minHeight: 18);

    for (final action in gameState.availableActions) {
      switch (action) {
        case GameAction.download:
          buttons.add(
            Tooltip(
              message: 'Download',
              child: IconButton(
                icon: Icon(Icons.download, size: buttonSize),
                onPressed: () => runGameAction(ref, context, game, gameState, GameAction.download),
                constraints: buttonConstraints,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
          break;
        case GameAction.pause:
          buttons.add(
            Tooltip(
              message: 'Pause',
              child: IconButton(
                icon: Icon(Icons.pause, size: buttonSize),
                onPressed: () => runGameAction(ref, context, game, gameState, GameAction.pause),
                constraints: buttonConstraints,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
          break;
        case GameAction.resume:
          buttons.add(
            Tooltip(
              message: 'Resume',
              child: IconButton(
                icon: Icon(Icons.play_arrow, size: buttonSize),
                onPressed: () => runGameAction(ref, context, game, gameState, GameAction.resume),
                constraints: buttonConstraints,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
          break;
        case GameAction.cancel:
          buttons.add(
            Tooltip(
              message: 'Cancel',
              child: IconButton(
                icon: Icon(Icons.close, size: buttonSize),
                onPressed: () => runGameAction(ref, context, game, gameState, GameAction.cancel),
                constraints: buttonConstraints,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
          break;
        case GameAction.extract:
          buttons.add(
            Tooltip(
              message: 'Extract',
              child: IconButton(
                icon: Icon(Icons.archive, size: buttonSize),
                onPressed: () => runGameAction(ref, context, game, gameState, GameAction.extract),
                constraints: buttonConstraints,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
          break;
        case GameAction.retryDownload:
          buttons.add(
            Tooltip(
              message: 'Retry Download',
              child: IconButton(
                icon: Icon(Icons.refresh, size: buttonSize),
                onPressed: () => runGameAction(ref, context, game, gameState, GameAction.retryDownload),
                constraints: buttonConstraints,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
          break;
        case GameAction.retryExtraction:
          buttons.add(
            Tooltip(
              message: 'Retry Extraction',
              child: IconButton(
                icon: Icon(Icons.refresh, size: buttonSize),
                onPressed: () => runGameAction(ref, context, game, gameState, GameAction.retryExtraction),
                constraints: buttonConstraints,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
          break;
        case GameAction.loading:
          buttons.add(
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
          );
          break;
        case GameAction.none:
          break;
      }
    }

    return buttons;
  }
}
