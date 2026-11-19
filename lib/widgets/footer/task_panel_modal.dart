import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/widgets/footer/task_list_view.dart';

/// Splits task states over the task manager's tabs. A running network transfer
/// ([GameState.isTransfer]) reports as `extracting` (it shares the file-task
/// machinery), but belongs under Downloads, not Extractions.
({List<GameState> downloading, List<GameState> extracting, List<GameState> queued, List<GameState> completed, List<GameState> failed}) classifyTasks(
  Iterable<GameState> states,
) {
  final downloading = <GameState>[], extracting = <GameState>[], queued = <GameState>[], completed = <GameState>[], failed = <GameState>[];
  for (final state in states) {
    // Queued work is only under Queue: listed in Downloads or Extractions too,
    // it counted twice in the badges.
    if (state.status == GameStatus.downloadQueued || state.status == GameStatus.extractionQueued) {
      queued.add(state);
    }
    if (state.status == GameStatus.downloading || state.status == GameStatus.downloadPaused) {
      downloading.add(state);
    }
    if (state.status == GameStatus.extracting) {
      if (state.isTransfer) {
        downloading.add(state);
      } else {
        extracting.add(state);
      }
    }
    if (state.hasJustCompleted && (state.status == GameStatus.downloaded || state.status == GameStatus.extracted)) {
      completed.add(state);
    }
    if (state.status == GameStatus.downloadFailed || state.status == GameStatus.extractionFailed) {
      failed.add(state);
    }
  }
  return (downloading: downloading, extracting: extracting, queued: queued, completed: completed, failed: failed);
}

class TaskPanelModal extends ConsumerStatefulWidget {
  const TaskPanelModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width * 0.9,
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (context) => const TaskPanelModal(),
    );
  }

  @override
  ConsumerState<TaskPanelModal> createState() => _TaskPanelModalState();
}

class _TaskPanelModalState extends ConsumerState<TaskPanelModal> {
  @override
  Widget build(BuildContext context) {
    final tabs = classifyTasks(ref.watch(gameStateManagerProvider).values);
    return TaskPanelFrame(
      onClose: () => Navigator.of(context).pop(),
      counts: [tabs.downloading.length, tabs.extracting.length, tabs.queued.length, tabs.completed.length, tabs.failed.length],
      tabs: [
        TaskListView(games: tabs.downloading, emptyMessage: taskTabs[0].empty, emptyIcon: taskTabs[0].emptyIcon),
        TaskListView(games: tabs.extracting, emptyMessage: taskTabs[1].empty, emptyIcon: taskTabs[1].emptyIcon),
        TaskListView(games: tabs.queued, emptyMessage: taskTabs[2].empty, emptyIcon: taskTabs[2].emptyIcon),
        TaskListView(games: tabs.completed, emptyMessage: taskTabs[3].empty, emptyIcon: taskTabs[3].emptyIcon),
        TaskListView(games: tabs.failed, emptyMessage: taskTabs[4].empty, emptyIcon: taskTabs[4].emptyIcon),
      ],
    );
  }
}

/// The Task Manager's tabs, in order, and what each shows when empty.
const taskTabs = [
  (label: 'Downloads', icon: Icons.download, empty: 'No active downloads', emptyIcon: Icons.download_outlined),
  (label: 'Extractions', icon: Icons.archive, empty: 'No active extractions', emptyIcon: Icons.archive_outlined),
  (label: 'Queue', icon: Icons.queue, empty: 'No queued tasks', emptyIcon: Icons.queue_outlined),
  (label: 'Completed', icon: Icons.history, empty: 'No completed tasks', emptyIcon: Icons.history_outlined),
  (label: 'Failed', icon: Icons.error, empty: 'No failed tasks', emptyIcon: Icons.error_outline),
];

/// The Task Manager's look: its header, the [taskTabs] buttons with their
/// [counts], and one list per tab in [tabs]. The main screen's sheet and the
/// second screen both draw it, each with its own rows. [onClose] null: no
/// close button (the second screen has nothing to close to).
class TaskPanelFrame extends StatefulWidget {
  const TaskPanelFrame({super.key, required this.counts, required this.tabs, this.onClose});

  final List<int> counts;
  final List<Widget> tabs;
  final VoidCallback? onClose;

  @override
  State<TaskPanelFrame> createState() => _TaskPanelFrameState();
}

class _TaskPanelFrameState extends State<TaskPanelFrame> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: taskTabs.length, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.task_alt,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Task Manager',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    icon: Icon(Icons.close, size: 20),
                    onPressed: widget.onClose,
                    constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < taskTabs.length; i++) ...[
                    if (i > 0) SizedBox(width: 6),
                    _buildTabButton(i, taskTabs[i].label, taskTabs[i].icon, widget.counts[i]),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: widget.tabs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon, int count) {
    final isSelected = _tabController.index == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _tabController.animateTo(index),
        autofocus: isSelected,
        borderRadius: BorderRadius.circular(16),
        focusColor: Colors.transparent,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (count > 0) ...[
                SizedBox(width: 4),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
