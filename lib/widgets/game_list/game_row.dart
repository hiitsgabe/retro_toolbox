import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/widgets/game_list/game_title.dart';
import 'package:retro_toolbox/widgets/game_list/game_tags.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_progress_bar.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';

class GameRow extends ConsumerStatefulWidget {
  final Game game;
  final bool isNarrow;
  final double sizeColumnWidth;
  final double statusColumnWidth;
  final double actionsColumnWidth;
  final bool selectable;
  final bool autofocus;

  const GameRow({
    super.key,
    required this.game,
    this.isNarrow = false,
    this.sizeColumnWidth = 100,
    this.statusColumnWidth = 100,
    this.actionsColumnWidth = 100,
    this.selectable = true,
    this.autofocus = false,
  });

  @override
  ConsumerState<GameRow> createState() => _GameRowState();
}

class _GameRowState extends ConsumerState<GameRow> {
  @override
  Widget build(BuildContext context) {
    final catalogNotifier = ref.read(catalogProvider.notifier);

    final gameId = widget.game.gameId;
    final gameState = ref.watch(gameStateProvider(widget.game));
    final isSelected = ref.watch(gameSelectionProvider(gameId));

    // One focus stop per card (A opens the menu); inner controls are
    // ExcludeFocus'd so the d-pad skips them but touch still hits them.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        focusColor: Colors.transparent, // DpadScope draws the one outline
        autofocus: widget.autofocus,
        onTap: () => showGameActionMenu(context, widget.game, selectable: widget.selectable),
        child: _card(context, gameState, isSelected, catalogNotifier, gameId),
      ),
    );
  }

  Widget _card(BuildContext context, GameState gameState, bool isSelected, CatalogNotifier catalogNotifier, String gameId) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withAlpha(50) : null,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.selectable) ...[
            SizedBox(
              width: 20,
              child: ExcludeFocus(
                child: Checkbox(
                  value: isSelected,
                  onChanged: gameState.isInteractable ? (_) => catalogNotifier.toggleGameSelection(gameId) : null,
                ),
              ),
            ),
            SizedBox(width: 6),
          ],
          GameBoxart(
            game: widget.game,
            size: (widget.isNarrow ? 50 : 60) + (widget.selectable ? 0 : 20),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GameTitle(
                              game: widget.game,
                              gameState: gameState,
                            ),
                            Row(
                              children: [
                                if (widget.isNarrow)
                                  Text(
                                    formatBytes(widget.game.size),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (widget.isNarrow) SizedBox(width: 8),
                                Expanded(child: GameTags(game: widget.game)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!widget.isNarrow)
                        SizedBox(
                          width: widget.sizeColumnWidth,
                          child: Text(
                            formatBytes(widget.game.size),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      SizedBox(
                        width: widget.statusColumnWidth,
                        child: Tooltip(
                          message: gameState.errorMessage ?? '',
                          child: Text(
                            gameState.statusText,
                            style: TextStyle(
                              fontSize: 12,
                              color: getStatusColor(context, gameState.status),
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: widget.actionsColumnWidth,
                        child: ExcludeFocus(
                          child: GameActionButtons(
                            game: widget.game,
                            gameState: gameState,
                            isNarrow: widget.isNarrow,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (gameState.showProgressBar)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: GameProgressBar(gameState: gameState),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
