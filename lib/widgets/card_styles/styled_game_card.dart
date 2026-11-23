import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/widgets/card_styles/selected_mark.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_menu_card.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/game_list/letter_jump.dart';

/// The behaviour of a classic game card (letter jump target, X/Y/hold-A,
/// tap or A opens the game, the second screen outline) around a style's [face].
class StyledGameCard extends ConsumerStatefulWidget {
  const StyledGameCard({
    super.key,
    required this.game,
    required this.face,
    this.autofocus = false,
    this.radius = 4,
    this.onFocusChange,
    this.tapFocus = TapFocus.none,
  });

  final Game game;

  /// The style's look: [selected] when marked, [focused] only when focus
  /// should show (see [FocusedLook]).
  final Widget Function(BuildContext context, GameState state, bool selected, bool focused) face;
  final bool autofocus;

  /// Corner radius of the ink and of the second screen outline.
  final double radius;
  final ValueChanged<bool>? onFocusChange;
  final TapFocus tapFocus;

  @override
  ConsumerState<StyledGameCard> createState() => _StyledGameCardState();
}

class _StyledGameCardState extends ConsumerState<StyledGameCard> with JumpTarget<StyledGameCard>, FocusedLook<StyledGameCard> {
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    watchJump(game.gameId);
    final state = ref.watch(gameStateProvider(game));
    final selected = ref.watch(gameSelectionProvider(game.gameId));
    final shown = ref.watch(shownOnSecondScreenProvider(game.gameId));
    final launcherMode = ref.watch(launcherModeProvider);
    // One focus stop per card, as GameGridItem.
    return Material(
      type: MaterialType.transparency,
      child: GameCardActions(
        game: game,
        selectable: true,
        child: InkWell(
          focusNode: jumpFocus,
          // The style's face draws focus (or DpadScope's outline does): no wash.
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(widget.radius),
          onTap: () {
            if (tapFocus(widget.tapFocus, jumpFocus)) tapGameCard(context, ref, game, focus: jumpFocus);
          },
          // In launcher mode a tap launches: a long press is the way to the page.
          onLongPress: launcherMode ? () => showGameActionMenu(context, game) : null,
          onFocusChange: (v) {
            setFocused(v);
            widget.onFocusChange?.call(v);
          },
          child: SecondScreenHighlight(
            shown: shown,
            radius: widget.radius,
            child: widget.face(context, state, selected, focusedLook),
          ),
        ),
      ),
    );
  }
}

/// The game's state as small badges, for the styles' faces: downloading/
/// extracting (progress ring), downloaded/extracted (check icon in the classic
/// card's border colour), failed (warning). Selection is not here: the style
/// marks it round the whole card (see [SelectedMark]).
class GameStateBadges extends StatelessWidget {
  const GameStateBadges({super.key, required this.state, this.size = 20});

  final GameState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = state.status;
    final badges = [
      if (state.isActive)
        _badge(
          const ValueKey('badge-progress'),
          Padding(
            padding: EdgeInsets.all(size * 0.15),
            child: CircularProgressIndicator(
              value: state.showProgressBar ? state.currentProgress : null,
              strokeWidth: size * 0.12,
              color: scheme.primary,
            ),
          ),
        ),
      if (status == GameStatus.downloaded || status == GameStatus.extracted)
        _badge(
          const ValueKey('badge-done'),
          Icon(Icons.check, size: size * 0.75, color: status == GameStatus.downloaded ? scheme.secondaryContainer : scheme.inversePrimary),
        ),
      if (state.hasError) _badge(const ValueKey('badge-failed'), Icon(Icons.warning_rounded, size: size * 0.75, color: scheme.tertiary)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, b) in badges.indexed) ...[if (i > 0) SizedBox(width: size * 0.2), b],
      ],
    );
  }

  /// A dark disc, so the badge reads over any box art.
  Widget _badge(Key key, Widget child) => Container(
        key: key,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: child,
      );
}
