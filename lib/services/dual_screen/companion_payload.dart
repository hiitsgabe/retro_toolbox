import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';

/// What the companion screen shows: one of these, sent as JSON. Details also
/// say which LaunchBox import the game's data came from (null with metadata
/// off), so the companion knows when its own copy of that import is stale,
/// and carry the game's state, so its page can show the status and buttons.
Map<String, dynamic> detailsPayload(Game game, {String? launchboxVersion, GameState? state}) => {
      'mode': 'details',
      'game': game.toJson(),
      // A box set is shown by the box's name, which the game's own JSON lacks.
      'displayTitle': game.displayTitle,
      'launchbox': launchboxVersion,
      if (state != null) 'state': gameStateJson(state),
    };

/// Rows past this in one tab are left out: the JSON goes over a platform
/// channel on every update.
const maxTaskRowsPerTab = 200;

/// The Task Manager's tabs as classifyTasks splits them, each a list of
/// [gameStateJson] rows plus 'favorite'. At most [maxTaskRowsPerTab] rows a tab.
Map<String, dynamic> tasksPayload(Iterable<GameState> states, {bool Function(String gameId)? isFavorite}) {
  final tabs = classifyTasks(states);
  List<Map<String, dynamic>> rows(List<GameState> bucket) => [
        for (final s in bucket.take(maxTaskRowsPerTab))
          {...gameStateJson(s), 'favorite': isFavorite?.call(s.game.gameId) ?? false},
      ];
  return {
    'mode': 'tasks',
    'tabs': {
      'downloading': rows(tabs.downloading),
      'extracting': rows(tabs.extracting),
      'queued': rows(tabs.queued),
      'completed': rows(tabs.completed),
      'failed': rows(tabs.failed),
    },
  };
}

/// What a row or the details page reads from a [GameState]: enough for the
/// companion to rebuild one with [gameStateFromJson].
Map<String, dynamic> gameStateJson(GameState s) => {
      'game': s.game.toJson(),
      'status': s.status.name,
      'actions': [for (final a in s.availableActions) a.name],
      'interactable': s.isInteractable,
      'showProgress': s.showProgressBar,
      'progress': s.currentProgress,
      'speed': s.networkSpeed,
      'remainingMs': s.timeRemaining.inMilliseconds,
      'error': s.errorMessage,
      'transfer': s.isTransfer,
      'moving': s.movingToDestination,
      'justCompleted': s.hasJustCompleted,
    };

/// Throws on a map that is not [gameStateJson]'s shape. Unknown action
/// names (a newer main app) are skipped.
GameState gameStateFromJson(Map<String, dynamic> json) {
  final actions = GameAction.values.asNameMap();
  return GameState(
    game: Game.fromJson(json['game'] as Map<String, dynamic>),
    status: GameStatus.values.byName(json['status'] as String),
    availableActions: {
      for (final name in (json['actions'] as List? ?? const []))
        if (actions[name] case final a?) a,
    },
    isInteractable: json['interactable'] as bool? ?? true,
    showProgressBar: json['showProgress'] as bool? ?? false,
    currentProgress: (json['progress'] as num?)?.toDouble() ?? 0,
    networkSpeed: (json['speed'] as num?)?.toDouble() ?? 0,
    timeRemaining: Duration(milliseconds: (json['remainingMs'] as num?)?.toInt() ?? 0),
    errorMessage: json['error'] as String?,
    isTransfer: json['transfer'] as bool? ?? false,
    movingToDestination: json['moving'] as bool? ?? false,
    hasJustCompleted: json['justCompleted'] as bool? ?? false,
  );
}

/// What the companion asks the main app to do, sent back as JSON:
/// {kind: 'game', gameId, action} runs a [GameAction] on a game,
/// {kind: 'favorite', gameId} toggles its favourite.
Map<String, dynamic> gameActionRequest(String gameId, GameAction action) => {'kind': 'game', 'gameId': gameId, 'action': action.name};

Map<String, dynamic> favoriteRequest(String gameId) => {'kind': 'favorite', 'gameId': gameId};
