import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';

/// What the companion screen shows: one of these, sent as JSON. Details also
/// say which LaunchBox import the game's data came from (null with metadata
/// off), so the companion knows when its own copy of that import is stale.
Map<String, dynamic> detailsPayload(Game game, {String? launchboxVersion}) =>
    {'mode': 'details', 'game': game.toJson(), 'launchbox': launchboxVersion};

const _maxTaskRows = 30;

/// The Task Manager in short: running, queued, failed and just completed rows
/// in that order (from classifyTasks), each {title, status, progress (0..1 or
/// null), state ('active'|'queued'|'failed'|'done')}. At most 30 rows.
Map<String, dynamic> tasksPayload(Iterable<GameState> states) {
  final tabs = classifyTasks(states);
  final rows = <Map<String, dynamic>>[];
  void add(List<GameState> bucket, String state) {
    for (final s in bucket) {
      if (rows.length == _maxTaskRows) return;
      rows.add({
        'title': s.game.displayTitle,
        'status': s.statusText,
        'progress': s.showProgressBar ? s.currentProgress : null,
        'state': state,
      });
    }
  }

  // The downloading and extracting tabs list queued tasks too; here they are queued.
  final queued = tabs.queued.toSet();
  add([...tabs.downloading, ...tabs.extracting].where((s) => !queued.contains(s)).toList(), 'active');
  add(tabs.queued, 'queued');
  add(tabs.failed, 'failed');
  add(tabs.completed, 'done');
  return {'mode': 'tasks', 'tasks': rows};
}
