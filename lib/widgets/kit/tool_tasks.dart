import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/widgets/kit/status_panel.dart';
import 'package:retro_toolbox/widgets/kit/slot.dart';

/// How many finished tasks stay listed beside the running ones.
const _finishedShown = 3;

/// The status panel of a tool whose work runs in the task list: the tasks of
/// [type] there, as the task list has them. Running or waiting ones are the
/// work (progress from [work]); once all are finished, the newest result, with
/// what failed or was cancelled and why. Cleared from the task list, they are
/// gone from here too.
StatusPanel toolTaskStatus(
  TaskQueueState queue,
  ExtractionState work,
  TaskType type, {
  required String Function(QueuedTask task) name,
  required String Function(QueuedTask task) saved,
  String failed = 'Could not convert',
}) {
  final mine = [for (final t in queue.tasks) if (t.type == type) t];
  if (mine.isEmpty) return const StatusPanel.hidden();
  bool active(QueuedTask t) => t.status == TaskQueueStatus.waiting || t.status == TaskQueueStatus.running;
  if (mine.any(active)) {
    final finished = mine.where((t) => !active(t)).toList();
    final shown = finished.skip(finished.length > _finishedShown ? finished.length - _finishedShown : 0).toSet();
    return StatusPanel.working(items: [
      for (final t in mine)
        if (active(t) || shown.contains(t))
          switch (t.status) {
            TaskQueueStatus.waiting => WorkItem(name(t), state: WorkState.queued),
            TaskQueueStatus.running => WorkItem(name(t), progress: _progress(work, t.id)),
            TaskQueueStatus.completed => WorkItem(name(t), state: WorkState.done),
            TaskQueueStatus.cancelled => WorkItem(name(t), state: WorkState.failed, note: 'cancelled'),
            TaskQueueStatus.failed => WorkItem(name(t), state: WorkState.failed),
          },
    ]);
  }
  final ok = mine.where((t) => t.status == TaskQueueStatus.completed).toList();
  final bad = mine.where((t) => t.status != TaskQueueStatus.completed).toList();
  if (ok.isEmpty) {
    if (bad.length == 1) return StatusPanel.error(line: '$failed ${name(bad.single)}', details: bad.single.error ?? _reason(bad.single));
    return StatusPanel.error(line: '$failed ${bad.length} files', details: [for (final t in bad) '${name(t)}: ${_reason(t)}'].join('\n'));
  }
  final more = ok.length - 1;
  return StatusPanel.done(
    summary: more == 0 ? saved(ok.last) : '${saved(ok.last)}, and $more more',
    problems: [for (final t in bad) Problem(name(t), _reason(t), failed: t.status == TaskQueueStatus.failed)],
  );
}

double? _progress(ExtractionState work, String id) {
  final v = work.getTaskState(id)?.progress ?? 0;
  return v > 0 ? v : null;
}

/// The first line of a task's error, or why it stopped.
String _reason(QueuedTask t) {
  if (t.status == TaskQueueStatus.cancelled) return 'Cancelled';
  final e = t.error?.trim() ?? '';
  return e.isEmpty ? 'Failed' : e.split('\n').first.trim();
}

/// "Saved Crash Bandicoot (USA).chd in ROMs › psx": [file] and its folder, the
/// folder from its known root.
String savedIn(String file, String dir) => 'Saved $file in ${pathParts(dir).join(pathSeparator)}';

/// Queues [type] for [input] as the converters do: a transient game gives the
/// task its row in the task manager, and its id is the task key. Returns the
/// task id.
String enqueueToolTask(WidgetRef ref, TaskType type, String input, Map<String, dynamic> params) {
  final name = p.basename(input);
  int size = 0;
  try {
    size = File(input).lengthSync();
  } catch (_) {}
  final game = Game(title: name, url: 'https://manual/${Uri.encodeComponent(name)}', size: size, consoleId: 'manual');
  ref.read(gameStateManagerProvider.notifier).registerTransientGame(game);
  ref.read(taskQueueProvider.notifier).enqueue(game.gameId, type, {'taskId': game.gameId, ...params});
  return game.gameId;
}
