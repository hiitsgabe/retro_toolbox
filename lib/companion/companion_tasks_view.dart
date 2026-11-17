import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/dual_screen/companion_payload.dart';
import 'package:retro_toolbox/widgets/footer/task_list_view.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';

/// One Task Manager row as the main screen sent it (see tasksPayload).
typedef CompanionTask = ({GameState state, bool favorite});

/// The payload's tab keys, in [taskTabs] order.
const _tabKeys = ['downloading', 'extracting', 'queued', 'completed', 'failed'];

/// The tasks payload's tabs, in [taskTabs] order. Throws on a payload that is
/// not tasksPayload's shape.
List<List<CompanionTask>> companionTaskTabs(Map<String, dynamic> payload) {
  final tabs = payload['tabs'] as Map<String, dynamic>;
  return [
    for (final key in _tabKeys)
      [
        for (final row in (tabs[key] as List? ?? const []))
          (state: gameStateFromJson(row as Map<String, dynamic>), favorite: (row['favorite'] as bool?) ?? false),
      ],
  ];
}

/// The main screen's Task Manager, drawn here from what it sent: the same
/// tabs and rows, and the rows' buttons send their press back to it.
class CompanionTasksView extends StatelessWidget {
  const CompanionTasksView({super.key, required this.tabs, required this.onRequest});

  /// One list per [taskTabs] entry.
  final List<List<CompanionTask>> tabs;

  /// A press, as gameActionRequest or favoriteRequest builds it.
  final ValueChanged<Map<String, dynamic>> onRequest;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: TaskPanelFrame(
        counts: [for (final t in tabs) t.length],
        tabs: [
          for (var i = 0; i < taskTabs.length; i++)
            tabs[i].isEmpty
                ? TaskListEmpty(message: taskTabs[i].empty, icon: taskTabs[i].emptyIcon)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: tabs[i].length,
                    itemBuilder: (context, index) {
                      final (:state, :favorite) = tabs[i][index];
                      final gameId = state.game.gameId;
                      // Like the main Task Manager's rows (TaskListView).
                      return GameRowBody(
                        key: ValueKey(gameId),
                        game: state.game,
                        gameState: state,
                        selectable: false,
                        isNarrow: true,
                        statusColumnWidth: 80,
                        actionsColumnWidth: 100,
                        actions: GameActionButtonsView(
                          gameState: state,
                          isFavorite: favorite,
                          isNarrow: true,
                          onFavorite: () => onRequest(favoriteRequest(gameId)),
                          onAction: (action) => onRequest(gameActionRequest(gameId, action)),
                        ),
                      );
                    },
                  ),
        ],
      ),
    );
  }
}
