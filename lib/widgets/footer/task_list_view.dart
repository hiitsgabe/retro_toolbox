import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';
import 'package:retro_toolbox/widgets/kit/empty_state.dart';

class TaskListView extends StatelessWidget {
  final List<GameState> games;
  final String emptyMessage;
  final IconData emptyIcon;

  const TaskListView({
    super.key,
    required this.games,
    required this.emptyMessage,
    required this.emptyIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) return TaskListEmpty(message: emptyMessage, icon: emptyIcon);

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final gameState = games[index];
        return GameRow(
          key: ValueKey(gameState.game.gameId),
          game: gameState.game,
          isNarrow: true,
          statusColumnWidth: 80,
          actionsColumnWidth: 100,
          selectable: false,
        );
      },
    );
  }
}

/// A Task Manager tab with nothing in it: the kit's empty state.
class TaskListEmpty extends StatelessWidget {
  const TaskListEmpty({super.key, required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => EmptyState(icon: icon, line: message);
}
