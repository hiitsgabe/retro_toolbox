import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';

/// What the companion screen shows: one of these, sent as JSON.
Map<String, dynamic> detailsPayload(Game game) => {'mode': 'details', 'game': game.toJson()};

const _maxTaskRows = 30;

/// The Task Manager in short: active, queued, failed and just completed rows
/// in that order (use classifyTasks), each {title, status, progress (0..1 or
/// null), state ('active'|'queued'|'failed'|'done')}. At most 30 rows.
Map<String, dynamic> tasksPayload(Iterable<GameState> states) {
  final tabs = classifyTasks(states);
  final seen = <String>{};
  final rows = <Map<String, dynamic>>[];
  void add(List<GameState> bucket, String state) {
    for (final s in bucket) {
      if (rows.length == _maxTaskRows) return;
      // A queued download is in the downloading tab too: keep its first place.
      if (!seen.add(s.game.gameId)) continue;
      rows.add({
        'title': s.game.displayTitle,
        'status': s.statusText,
        'progress': s.showProgressBar ? s.currentProgress : null,
        'state': state,
      });
    }
  }

  add([...tabs.downloading, ...tabs.extracting], 'active');
  add(tabs.queued, 'queued');
  add(tabs.failed, 'failed');
  add(tabs.completed, 'done');
  return {'mode': 'tasks', 'tasks': rows};
}
