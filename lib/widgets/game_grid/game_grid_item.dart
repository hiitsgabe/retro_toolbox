import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/card_styles/selected_mark.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/game_list/letter_jump.dart';

class GameGridItem extends ConsumerStatefulWidget {
  final Game game;
  final double aspectRatio;
  final bool selectable;
  final bool autofocus;

  /// Takes an L1/R1 jump to its game; off where the card cannot hold focus
  /// (a cover flow face).
  final bool jumpTarget;

  const GameGridItem({
    super.key,
    required this.game,
    this.aspectRatio = 0.75,
    this.selectable = true,
    this.autofocus = false,
    this.jumpTarget = true,
  });

  @override
  ConsumerState<GameGridItem> createState() => _GameGridItemState();
}

class _GameGridItemState extends ConsumerState<GameGridItem> with JumpTarget<GameGridItem> {
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    if (widget.jumpTarget) watchJump(game.gameId);
    final aspectRatio = widget.aspectRatio;
    final gameState = ref.watch(gameStateProvider(game));
    final isSelected = ref.watch(gameSelectionProvider(game.gameId));
    final shown = widget.selectable && ref.watch(shownOnSecondScreenProvider(game.gameId));
    final radius = StyleTokens.of(context).cardRadius;

    // One focus stop per card (A opens the game's page, X marks it, Start
    // downloads the marked ones). Nothing on the face takes a tap of its own:
    // favourite, download and select are on the page.
    return Material(
      type: MaterialType.transparency,
      child: GameCardActions(
        game: game,
        selectable: widget.selectable,
        child: InkWell(
          focusNode: jumpFocus,
          focusColor: Colors.transparent, // DpadScope draws the one outline
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(radius),
          onTap: () => tapGameCard(context, ref, game, selectable: widget.selectable, focus: jumpFocus),
          child: SecondScreenHighlight(
            shown: shown,
            radius: radius,
            child: SelectedMark(
              selected: isSelected,
              radius: radius,
              child: _card(context, game, aspectRatio, gameState, radius),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Game game, double aspectRatio, GameState gameState, double radius) {
    final tokens = StyleTokens.of(context);
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: tokens.panelLine),
        ),
        child: Tooltip(
          message: game.title,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - 1),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: GameBoxart(
                    game: game,
                    placeholder: _buildPlaceholder(context),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                    padding: EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (game.boxart != null) ...[
                          Text(
                            game.displayTitle,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: DeviceClass.of(context).textFloor,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 1)),
                                Shadow(color: Colors.black, blurRadius: 12, offset: Offset(0, 2)),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                        ],
                        // Chips at the text floor do not all fit across a small card.
                        Wrap(
                          runSpacing: 2,
                          children: [
                            if (game.discs.length >= 2 || game.metadata?.diskNumber.isNotEmpty == true) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  game.discs.length >= 2 ? '${game.discs.length} discs' : 'Disk ${game.metadata!.diskNumber}',
                                  style: TextStyle(
                                    fontSize: DeviceClass.of(context).textFloor,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (game.metadata?.revision.isNotEmpty == true) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'Rev ${game.metadata!.revision}',
                                  style: TextStyle(
                                    fontSize: DeviceClass.of(context).textFloor,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (game.metadata?.regions.isNotEmpty == true) ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.inversePrimary.withValues(alpha: 0.6),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    game.metadata?.regions.first ?? '',
                                    style: TextStyle(
                                      fontSize: DeviceClass.of(context).textFloor,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (gameState.showProgressBar) ...[
                          SizedBox(height: 4),
                          Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(1.5),
                              child: LinearProgressIndicator(
                                value: gameState.currentProgress,
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                minHeight: 3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // The state (progress, on disk, failed); the selected mark
                // holds the top left.
                Positioned(top: 6, right: 6, child: GameStateBadges(state: gameState)),
              ],
            ),
          ),
        ));
  }

  Widget _buildPlaceholder(BuildContext context) {
    final k = StyleTokens.of(context);
    // Opaque, tinted with the style's accent: a see-through face let the
    // cover flow's cards behind it show through.
    final base = k.solidPanel.withValues(alpha: 1);
    return Container(
      key: const ValueKey('game-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(k.accent.withValues(alpha: 0.26), base),
            Color.alphaBlend(k.accent.withValues(alpha: 0.10), base),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videogame_asset_rounded,
                size: 32,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              ),
              SizedBox(height: 8),
              // A short card clips the title rather than overflow.
              Flexible(
                child: Text(
                  widget.game.displayTitle,
                  style: TextStyle(
                    // Long titles shrink, never under the device's floor.
                    fontSize: widget.game.displayTitle.length > 20 ? DeviceClass.of(context).textFloor : 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
