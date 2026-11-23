import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/widgets/card_styles/selected_mark.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/game_list/game_title.dart';
import 'package:retro_toolbox/widgets/game_list/game_tags.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_progress_bar.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/game_list/letter_jump.dart';

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

class _GameRowState extends ConsumerState<GameRow> with JumpTarget<GameRow> {
  @override
  Widget build(BuildContext context) {
    final catalogNotifier = ref.read(catalogProvider.notifier);

    final gameId = widget.game.gameId;
    watchJump(gameId);
    final gameState = ref.watch(gameStateProvider(widget.game));
    final isSelected = ref.watch(gameSelectionProvider(gameId));
    final shown = widget.selectable && ref.watch(shownOnSecondScreenProvider(gameId));
    final launcherMode = ref.watch(launcherModeProvider);

    // One focus stop per card (A opens the menu); inner controls are
    // ExcludeFocus'd so the d-pad skips them but touch still hits them.
    return Material(
      type: MaterialType.transparency,
      child: GameCardActions(
        game: widget.game,
        selectable: widget.selectable,
        child: InkWell(
          focusNode: jumpFocus,
          focusColor: Colors.transparent, // DpadScope draws the one outline
          autofocus: widget.autofocus,
          onTap: () => tapGameCard(context, ref, widget.game, selectable: widget.selectable, focus: jumpFocus),
          // In launcher mode a tap launches: a long press is the way to the page.
          onLongPress: launcherMode ? () => showGameActionMenu(context, widget.game, selectable: widget.selectable) : null,
          child: SecondScreenHighlight(
            shown: shown,
            // In launcher mode a long press opens the page: a tooltip under
            // the finger would take it.
            child: TooltipVisibility(
              visible: !launcherMode,
              child: GameRowBody(
                game: widget.game,
                gameState: gameState,
                isSelected: isSelected,
                selectable: widget.selectable,
                isNarrow: widget.isNarrow,
                sizeColumnWidth: widget.sizeColumnWidth,
                statusColumnWidth: widget.statusColumnWidth,
                actionsColumnWidth: widget.actionsColumnWidth,
                onToggleSelected: () => catalogNotifier.toggleGameSelection(gameId),
                actions: GameActionButtons(
                  game: widget.game,
                  gameState: gameState,
                  isNarrow: widget.isNarrow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row's look, from data: [GameRow] feeds it the app's state, the second
/// screen's Task Manager what the main screen sent.
class GameRowBody extends StatelessWidget {
  const GameRowBody({
    super.key,
    required this.game,
    required this.gameState,
    required this.actions,
    this.isSelected = false,
    this.selectable = true,
    this.isNarrow = false,
    this.sizeColumnWidth = 100,
    this.statusColumnWidth = 100,
    this.actionsColumnWidth = 100,
    this.onToggleSelected,
  });

  final Game game;
  final GameState gameState;
  final Widget actions;
  final bool isSelected;
  final bool selectable;
  final bool isNarrow;
  final double sizeColumnWidth;
  final double statusColumnWidth;
  final double actionsColumnWidth;
  final VoidCallback? onToggleSelected;

  @override
  Widget build(BuildContext context) {
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
          if (selectable) ...[
            SizedBox(
              width: 20,
              child: ExcludeFocus(
                child: Checkbox(
                  value: isSelected,
                  onChanged: gameState.isInteractable && onToggleSelected != null ? (_) => onToggleSelected!() : null,
                ),
              ),
            ),
            SizedBox(width: 6),
          ],
          if (PlayBadges.of(context) && (gameState.status == GameStatus.downloaded || gameState.status == GameStatus.extracted)) ...[
            Icon(Icons.play_arrow_rounded, key: const ValueKey('row-play'), size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
          ],
          // The style's mark too, as its grid cards wear it: the checkbox
          // alone says nothing of the style.
          SelectedMark(
            selected: isSelected,
            size: 14,
            child: GameBoxart(
              game: game,
              size: (isNarrow ? 50 : 60) + (selectable ? 0 : 20),
            ),
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
                              game: game,
                              gameState: gameState,
                            ),
                            Row(
                              children: [
                                // No Status column on a phone: the state goes after the size.
                                if (isNarrow)
                                  Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: formatBytes(game.size)),
                                      const TextSpan(text: '  ·  '),
                                      TextSpan(text: gameState.statusText, style: TextStyle(color: getStatusColor(context, gameState.status), fontWeight: FontWeight.w500)),
                                    ]),
                                    key: const ValueKey('row-size-status'),
                                    style: TextStyle(
                                      fontSize: DeviceClass.of(context).textFloor,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (isNarrow) SizedBox(width: 8),
                                Expanded(child: GameTags(game: game)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!isNarrow)
                        SizedBox(
                          width: sizeColumnWidth,
                          child: Text(
                            formatBytes(game.size),
                            style: TextStyle(
                              fontSize: DeviceClass.of(context).textFloor,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (!isNarrow)
                        SizedBox(
                          width: statusColumnWidth,
                          child: Tooltip(
                            message: gameState.errorMessage ?? '',
                            child: Text(
                              gameState.statusText,
                              style: TextStyle(
                                fontSize: DeviceClass.of(context).textFloor,
                                color: getStatusColor(context, gameState.status),
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: actionsColumnWidth,
                        child: ExcludeFocus(child: actions),
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
