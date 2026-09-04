import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/widgets/game_grid/game_grid_item.dart';
import 'package:roms_downloader/widgets/menu_grid/cover_flow.dart';

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
    return CoverFlow(
      aspectRatio: _aspectRatio,
      items: [
        for (final game in games)
          CoverFlowItem(
            face: GameGridItem(game: game, aspectRatio: _aspectRatio),
            label: game.displayTitle,
          ),
      ],
    );
  }
}
