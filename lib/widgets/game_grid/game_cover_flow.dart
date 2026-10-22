import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';
import 'package:retro_toolbox/widgets/game_list/letter_jump.dart';
import 'package:retro_toolbox/widgets/menu_grid/cover_flow.dart';

/// Cover Flow view of the filtered games, reusing the interactive
/// [GameGridItem] card as each face (selection/actions still work on center).
class GameCoverFlow extends ConsumerWidget {
  const GameCoverFlow({super.key});

  static const double _aspectRatio = 0.72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(catalogProvider.select((s) => s.paginatedFilteredGames));
    if (games.isEmpty) {
      return const Center(child: Text('No games to show'));
    }
    // An L1/R1 jump: the flow animates to that game, and the jump is taken.
    final jumpId = ref.watch(gameJumpProvider);
    final jumpIndex = jumpId == null ? -1 : games.indexWhere((g) => g.gameId == jumpId);
    if (jumpId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(gameJumpProvider) == jumpId) ref.read(gameJumpProvider.notifier).state = null;
      });
    }
    return CoverFlow(
      aspectRatio: _aspectRatio,
      jumpTo: jumpIndex >= 0 ? jumpIndex : null,
      items: [
        for (final game in games)
          CoverFlowItem(
            face: GameGridItem(game: game, aspectRatio: _aspectRatio, jumpTarget: false),
            label: game.displayTitle,
            onTap: () => showGameActionMenu(context, game),
            wrapFocus: (focus) => GameCardActions(game: game, selectable: true, child: focus),
          ),
      ],
    );
  }
}
