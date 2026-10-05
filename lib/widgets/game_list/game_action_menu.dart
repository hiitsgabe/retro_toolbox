import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';

const _labels = {
  GameAction.download: 'Download',
  GameAction.pause: 'Pause',
  GameAction.resume: 'Resume',
  GameAction.cancel: 'Cancel',
  GameAction.extract: 'Extract',
  GameAction.retryDownload: 'Retry download',
  GameAction.retryExtraction: 'Retry extraction',
};

/// Gamepad buttons for a focused game card: X marks it (where the checkbox
/// would work), Y opens its menu.
class GameCardActions extends ConsumerWidget {
  const GameCardActions({super.key, required this.game, required this.selectable, required this.child});

  final Game game;
  final bool selectable;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Actions(
      actions: {
        MarkIntent: CallbackAction<MarkIntent>(onInvoke: (_) {
          if (selectable && (ref.read(gameStateProvider(game)).isInteractable || ref.read(gameSelectionProvider(game.gameId)))) {
            ref.read(catalogProvider.notifier).toggleGameSelection(game.gameId);
          }
          return null;
        }),
        ItemActionsIntent: CallbackAction<ItemActionsIntent>(
          onInvoke: (_) => showGameActionMenu(context, game, selectable: selectable),
        ),
      },
      child: child,
    );
  }
}

/// The per-game menu a card opens: everything the row's small buttons and
/// checkbox do, as big focusable tiles. Actions run with the sheet's own ref
/// and context (the card may unmount while the sheet is open) and the sheet
/// closes once they finish. Back/Escape is ignored while an action runs
/// (closing would dispose the sheet's ref mid-action and drop it).
Future<void> showGameActionMenu(BuildContext context, Game game, {bool selectable = true}) {
  // ponytail: not disposed — a touch drag can close the sheet mid-action and
  // the finally block still writes to it; it's tiny and goes with the closure.
  final busy = ValueNotifier(false);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => ValueListenableBuilder<bool>(
      valueListenable: busy,
      builder: (_, isBusy, child) => PopScope(canPop: !isBusy, child: child!),
      child: Consumer(
        builder: (_, ref, __) {
          final gameState = ref.watch(gameStateProvider(game));
          final isFavorite = ref.watch(favoritesProvider).isFavorite(game.gameId);
          final isSelected = ref.watch(gameSelectionProvider(game.gameId));
          final actions = [
            for (final a in gameState.availableActions)
              if (_labels.containsKey(a)) a,
          ];
          return ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.displayTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(gameState.statusText, style: Theme.of(sheetContext).textTheme.bodySmall),
                    if (gameState.errorMessage != null)
                      Text(
                        gameState.errorMessage!,
                        style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
                      ),
                  ],
                ),
              ),
              for (final a in actions)
                ListTile(
                  autofocus: a == actions.first,
                  title: Text(_labels[a]!),
                  onTap: () async {
                    busy.value = true;
                    try {
                      await runGameAction(ref, sheetContext, game, gameState, a);
                    } finally {
                      busy.value = false;
                    }
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              ListTile(
                autofocus: actions.isEmpty,
                title: Text(isFavorite ? 'Remove from favourites' : 'Add to favourites'),
                onTap: () => ref.read(favoritesProvider.notifier).toggleFavorite(game.gameId),
              ),
              if (selectable && (gameState.isInteractable || isSelected))
                ListTile(
                  title: Text(isSelected ? 'Unselect' : 'Select'),
                  onTap: () => ref.read(catalogProvider.notifier).toggleGameSelection(game.gameId),
                ),
              if (game.boxart != null)
                ListTile(
                  title: const Text('View box art'),
                  onTap: () => showBoxartViewer(sheetContext, game),
                ),
            ],
          );
        },
      ),
    ),
  );
}
