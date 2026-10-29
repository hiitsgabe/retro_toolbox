import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';

final taskQueueProvider = StateNotifierProvider<TaskQueueNotifier, TaskQueueState>((ref) {
  return TaskQueueNotifier(ref);
});

class TaskQueueNotifier extends StateNotifier<TaskQueueState> {
  final Ref _ref;
  Timer? _processingTimer;

  TaskQueueNotifier(this._ref) : super(const TaskQueueState()) {
    // No timer until there's work: enqueue starts it.
    restored = _restoreQueuedDownloads();
    addListener(_saveQueuedDownloads, fireImmediately: false);
  }

  /// Completes once downloads queued before the last exit are back in the queue.
  late final Future<void> restored;

  // Running downloads survive a crash in the downloader's own database; the
  // ones still waiting for a slot only live here, so keep them in prefs too.
  static const _queuedDownloadsKey = 'queued_downloads';
  bool _restoreDone = false;
  String? _savedQueue;

  void _saveQueuedDownloads(TaskQueueState s) {
    if (!_restoreDone) return; // don't overwrite the saved queue before reading it
    final json = jsonEncode([
      for (final t in s.tasks)
        if (t.type == TaskType.download && t.status == TaskQueueStatus.waiting) {'id': t.id, 'params': t.params},
    ]);
    if (json == _savedQueue) return;
    _savedQueue = json;
    SharedPreferences.getInstance().then((p) => p.setString(_queuedDownloadsKey, json));
  }

  Future<void> _restoreQueuedDownloads() async {
    try {
      await _ref.read(settingsProvider.notifier).loaded; // respect the parallel-download limit
      final raw = (await SharedPreferences.getInstance()).getString(_queuedDownloadsKey);
      _savedQueue = raw;
      for (final e in raw == null ? const [] : jsonDecode(raw) as List) {
        final id = e['id'] as String;
        if (!mounted || state.tasks.any((t) => t.id == id)) continue;
        enqueue(id, TaskType.download, Map<String, dynamic>.from(e['params'] as Map));
      }
    } catch (e) {
      debugPrint('Could not restore queued downloads: $e');
    }
    _restoreDone = true;
    if (mounted) _saveQueuedDownloads(state);
  }

  void enqueue(String taskId, TaskType type, Map<String, dynamic> params) {
    final task = QueuedTask(
      id: taskId,
      type: type,
      params: params,
      createdAt: DateTime.now(),
    );

    // A retry supersedes the failed attempt; don't leave it lingering.
    final updatedTasks = [...state.tasks.where((t) => !(t.id == taskId && t.status == TaskQueueStatus.failed)), task];
    state = state.copyWith(tasks: updatedTasks);

    final gameStateManager = _ref.read(gameStateManagerProvider.notifier);
    // The task manager lists game states, and only the loaded catalog's games
    // have one. A download of any other game (the sport patcher's library
    // match, a queue restored after a restart) gets its row here.
    if (type == TaskType.download) gameStateManager.registerTransientGame(Game.fromJson(Map<String, dynamic>.from(params['game'] as Map)));
    gameStateManager.updateQueueState(taskId, type);

    _startTimerIfNeeded();
    _processQueue();
  }

  void updateTaskStatus(String taskId, TaskQueueStatus status, {String? error}) {
    final updatedTasks = state.tasks.map((currentTask) {
      // A download and its follow-up (extract/NSZ) share the game's id; only
      // touch the live entry so finished siblings don't flip back to running.
      if (currentTask.id == taskId && !currentTask.status.isCompleted) {
        return currentTask.copyWith(
          status: status,
          startedAt: status == TaskQueueStatus.running ? DateTime.now() : currentTask.startedAt,
          completedAt: status.isCompleted ? DateTime.now() : currentTask.completedAt,
          error: error,
        );
      }
      return currentTask;
    }).toList();

    final runningCounts = <TaskType, int>{};
    for (final task in updatedTasks) {
      if (task.status == TaskQueueStatus.running) {
        runningCounts[task.type] = (runningCounts[task.type] ?? 0) + 1;
      }
    }

    state = state.copyWith(
      tasks: updatedTasks,
      runningCounts: runningCounts,
    );

    _processQueue();
  }

  void _startProcessing() {
    _processingTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _processQueue());
  }

  void _stopProcessing() {
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  void _startTimerIfNeeded() {
    if (_processingTimer == null) {
      _startProcessing();
    }
  }

  void _processQueue() async {
    if (state.isProcessing) return;
    debugPrint('Processing task queue...');
    state = state.copyWith(isProcessing: true);

    try {
      final settingsNotifier = _ref.read(settingsProvider.notifier);
      final maxDownloads = settingsNotifier.getMaxParallelDownloads();
      final maxExtractions = settingsNotifier.getMaxParallelExtractions();

      final limits = {
        TaskType.download: maxDownloads,
        TaskType.extraction: maxExtractions,
      };

      for (final type in TaskType.values) {
        final runningCount = state.runningCounts[type] ?? 0;
        final maxCount = limits[type] ?? 1;
        final availableSlots = maxCount - runningCount;

        if (availableSlots > 0) {
          final waitingTasks = state.tasks.where((task) => task.type == type && task.status == TaskQueueStatus.waiting).take(availableSlots);

          for (final task in waitingTasks) {
            updateTaskStatus(task.id, TaskQueueStatus.running);

            TaskQueueService.executeTask(_ref, this, task).catchError((e) {
              updateTaskStatus(task.id, TaskQueueStatus.failed, error: e.toString());
            });
          }
        }
      }

      if (!_hasPendingTasks()) {
        _stopProcessing();
      }
    } finally {
      state = state.copyWith(isProcessing: false);
    }
  }

  void cancelQueuedTask(String taskId) {
    final remaining = state.tasks
        .where((t) => !(t.id == taskId && (t.status == TaskQueueStatus.waiting || t.status == TaskQueueStatus.failed || t.status == TaskQueueStatus.cancelled)))
        .toList();
    final runningCounts = Map<TaskType, int>.from(state.runningCounts);

    state = state.copyWith(tasks: remaining, runningCounts: runningCounts);

    final gameStateManager = _ref.read(gameStateManagerProvider.notifier);
    gameStateManager.resetAfterCancel(taskId);

    if (_hasPendingTasks()) {
      _startTimerIfNeeded();
    }
  }

  bool _hasPendingTasks() {
    return state.tasks.any((task) => task.status == TaskQueueStatus.waiting || task.status == TaskQueueStatus.running);
  }

  @override
  void dispose() {
    _processingTimer?.cancel();
    super.dispose();
  }
}

extension on TaskQueueStatus {
  bool get isCompleted => this == TaskQueueStatus.completed || this == TaskQueueStatus.failed || this == TaskQueueStatus.cancelled;
}
