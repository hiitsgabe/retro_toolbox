import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/footer/task_list_view.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

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

/// The tab the Task Manager opens on: the first of Downloads, Extractions
/// and Queue with something in it, then Failed, then Completed; Downloads
/// when every tab is empty.
int taskTabWithWork(List<int> counts) {
  for (final i in const [0, 1, 2, 4, 3]) {
    if (i < counts.length && counts[i] > 0) return i;
  }
  return 0;
}

/// The Task Manager's look: its header, the [taskTabs] buttons with their
/// [counts], and one list per tab in [tabs]. The main screen's sheet and the
/// second screen both draw it, each with its own rows. [onClose] null: no
/// close button (the second screen has nothing to close to). It opens on the
/// tab that has work ([taskTabWithWork]), and moves there when work arrives
/// while the user has not picked a tab and the one shown is empty.
class TaskPanelFrame extends StatefulWidget {
  const TaskPanelFrame({super.key, required this.counts, required this.tabs, this.onClose});

  final List<int> counts;
  final List<Widget> tabs;
  final VoidCallback? onClose;

  @override
  State<TaskPanelFrame> createState() => _TaskPanelFrameState();
}

class _TaskPanelFrameState extends State<TaskPanelFrame> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: taskTabs.length, vsync: this, initialIndex: taskTabWithWork(widget.counts));

  /// The user chose a tab: work arriving elsewhere no longer moves it.
  bool _picked = false;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(TaskPanelFrame old) {
    super.didUpdateWidget(old);
    final i = _tabController.index;
    if (_picked || widget.counts[i] > 0) return;
    final next = taskTabWithWork(widget.counts);
    if (next != i) _tabController.index = next;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final total = widget.counts.fold(0, (a, b) => a + b);
    return KitArea(
      area: AppArea.tasks,
      child: Builder(builder: (context) {
        final k = StyleTokens.of(context);
        return Container(
          decoration: BoxDecoration(
            color: k.solidPanel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(k.panelRadius.clamp(0, 16).toDouble())),
            border: Border(top: BorderSide(color: k.panelLine)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
              child: Row(children: [
                const KitIconTile(icon: Icons.task_alt, glyph: PixelIcons.tasks, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('Task Manager', style: t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(total == 0 ? 'Nothing running' : '$total ${total == 1 ? 'task' : 'tasks'}', style: t.subtitle, maxLines: 1),
                  ]),
                ),
                if (widget.onClose != null) IconButton(icon: const Icon(Icons.close, size: 22), tooltip: 'Close', onPressed: widget.onClose),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < taskTabs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _tab(context, i, widget.counts[i]),
                  ],
                ]),
              ),
            ),
            Divider(height: 1, thickness: 1, color: k.panelLine),
            Expanded(child: TabBarView(controller: _tabController, children: widget.tabs)),
          ]),
        );
      }),
    );
  }

  Widget _tab(BuildContext context, int index, int count) {
    final t = KitType.of(context);
    final k = t.k;
    final selected = _tabController.index == index;
    final tab = taskTabs[index];
    final fg = selected ? k.accent : t.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _picked = true;
          _tabController.animateTo(index);
        },
        autofocus: selected,
        borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 18).toDouble()),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? k.accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 18).toDouble()),
            border: Border.all(color: selected ? k.accent.withValues(alpha: 0.5) : k.panelLine),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(tab.icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(tab.label, style: t.subtitle.copyWith(fontSize: t.size(13), fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? t.ink : t.muted)),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: selected ? k.accent : t.muted.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(9)),
                child: Text('$count', style: TextStyle(fontSize: t.size(12), fontWeight: FontWeight.w700, color: selected ? k.onAccent : t.ink)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
