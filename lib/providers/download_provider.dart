import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:background_downloader/background_downloader.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/download_model.dart';
import 'package:roms_downloader/models/task_queue_model.dart';
import 'package:roms_downloader/providers/library_snapshot_provider.dart';
import 'package:roms_downloader/services/download_service.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/game_state_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/providers/task_queue_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/utils/network.dart';

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>((ref) {
  final catalogNotifier = ref.read(catalogProvider.notifier);
  final gameStateManager = ref.read(gameStateManagerProvider.notifier);
  return DownloadNotifier(ref, catalogNotifier, gameStateManager);
});

class DownloadNotifier extends StateNotifier<DownloadState> {
  final Ref _ref;
  final Map<String, DownloadTask> _tasks = {};
  StreamSubscription<TaskUpdate>? _updateSubscription;

  final DownloadService downloadService = DownloadService();
  final CatalogNotifier catalogNotifier;
  final GameStateManager gameStateManager;

  DownloadNotifier(this._ref, this.catalogNotifier, this.gameStateManager) : super(const DownloadState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    final fileDownloader = await downloadService.initialize();

    _updateSubscription = fileDownloader.updates.listen((update) {
      switch (update) {
        case TaskStatusUpdate():
          _handleStatusUpdate(update);
        case TaskProgressUpdate():
          _handleProgressUpdate(update);
      }
    });

    await fileDownloader.resumeFromBackground();

    await _syncWithBackgroundTasks();

    await _resumeInterruptedNsz();
  }

  /// A crash/kill mid-batch (e.g. the app dying during decompression) leaves a
  /// downloaded `.nsz` on disk that never got processed. background_downloader
  /// resumes the downloads themselves, but nothing re-drives decompression, so
  /// on startup we scan the download dirs and re-queue any leftover `.nsz`.
  Future<void> _resumeInterruptedNsz() async {
    try {
      final settings = _ref.read(settingsProvider.notifier);
      if (!settings.getNszDecompressEnabled()) return;
      final keysPath = settings.getNszKeysPath() ?? '';
      if (keysPath.isEmpty) return; // can't decompress without keys

      final consoles = await CatalogService().getConsoles();
      final queueNotifier = _ref.read(taskQueueProvider.notifier);
      final scanned = <String>{};

      for (final consoleId in consoles.keys) {
        final dir = settings.getDownloadDir(consoleId);
        if (dir.isEmpty || !scanned.add(dir)) continue;
        final directory = Directory(dir);
        if (!await directory.exists()) continue;

        await for (final entity in directory.list()) {
          if (entity is! File || !entity.path.toLowerCase().endsWith('.nsz')) continue;

          final filename = p.basename(entity.path);
          final taskId = '$consoleId/$filename';

          // Skip anything still downloading or already queued.
          final status = state.taskStatus[taskId];
          if (status == TaskStatus.running || status == TaskStatus.enqueued) continue;
          if (_ref.read(taskQueueProvider).tasks.any((t) => t.id == taskId)) continue;

          debugPrint('Resuming interrupted NSZ decompression: ${entity.path}');
          queueNotifier.enqueue(taskId, TaskType.nszDecompression, {
            'taskId': taskId,
            'nszFilePath': entity.path,
            'outputDir': dir,
            'keysPath': keysPath,
          });
        }
      }
    } catch (e) {
      debugPrint('Resume interrupted NSZ scan failed: $e');
    }
  }

  void _handleStatusUpdate(TaskStatusUpdate update, [String? error]) {
    final taskStatus = Map<String, TaskStatus>.from(state.taskStatus);
    taskStatus[update.task.taskId] = update.status;

    if (!_tasks.containsKey(update.task.taskId) && update.task is DownloadTask) {
      _tasks[update.task.taskId] = update.task as DownloadTask;
      debugPrint('Registered background task ${update.task.taskId} with status ${update.status}');
    }

    final queueNotifier = _ref.read(taskQueueProvider.notifier);
    final completedTasks = Set<String>.from(state.completedTasks);
    if (update.status == TaskStatus.complete) {
      completedTasks.add(update.task.taskId);
      catalogNotifier.deselectGame(update.task.taskId);
      debugPrint('Download completed for ${update.task.taskId}');
      queueNotifier.updateTaskStatus(update.task.taskId, TaskQueueStatus.completed);

      final game = gameStateManager.state[update.task.taskId]?.game;
      if (game != null) {
        final dir = _ref.read(settingsProvider.notifier).getDownloadDir(game.consoleId);
        if (dir.isNotEmpty) {
          _ref.read(librarySnapshotProvider(dir).notifier).markFileAdded(game.filename);
        }
      }

      _triggerAutoExtraction(update.task.taskId);
    } else if (update.status == TaskStatus.failed) {
      debugPrint('Download failed for ${update.task.taskId}: ${update.exception?.description ?? error ?? 'unknown'}');
      queueNotifier.updateTaskStatus(update.task.taskId, TaskQueueStatus.failed, error: error ?? update.exception?.description);
    } else if (update.status == TaskStatus.canceled) {
      queueNotifier.updateTaskStatus(update.task.taskId, TaskQueueStatus.cancelled);
    }

    state = state.copyWith(
      taskStatus: taskStatus,
      completedTasks: completedTasks,
    );

    gameStateManager.updateDownloadState(
      update.task.taskId,
      update.status,
      state.taskProgress[update.task.taskId],
      update.status == TaskStatus.complete,
      error: error ?? update.exception?.description,
    );

    _updateDownloadingState();
  }

  void _handleProgressUpdate(TaskProgressUpdate update) {
    final taskProgress = Map<String, TaskProgressUpdate>.from(state.taskProgress);
    final taskStatus = state.taskStatus[update.task.taskId];

    if (!_tasks.containsKey(update.task.taskId) && update.task is DownloadTask) {
      _tasks[update.task.taskId] = update.task as DownloadTask;
      debugPrint('Registered background task ${update.task.taskId} from progress update');
    }

    if (taskStatus == TaskStatus.paused || update.progress <= 0.0) {
      final lastProgress = state.taskProgress[update.task.taskId];
      if (lastProgress != null && lastProgress.progress > 0.0) {
        update = TaskProgressUpdate(lastProgress.task, lastProgress.progress);
      }
    }

    taskProgress[update.task.taskId] = update;

    state = state.copyWith(
      taskProgress: taskProgress,
    );

    gameStateManager.updateDownloadState(
      update.task.taskId,
      taskStatus,
      update,
      false,
    );
  }

  void _updateDownloadingState() {
    final hasActiveDownloads = state.taskStatus.values.any((status) => status == TaskStatus.running || status == TaskStatus.enqueued);

    if (state.downloading != hasActiveDownloads) {
      state = state.copyWith(downloading: hasActiveDownloads);
    }
  }

  void _triggerAutoExtraction(String taskId) {
    final gameState = gameStateManager.state[taskId];
    if (gameState == null) return;

    final game = gameState.game;
    final settingsNotifier = _ref.read(settingsProvider.notifier);

    // NSZ files require Python decompression — not ZIP extraction.
    if (game.filename.toLowerCase().endsWith('.nsz')) {
      if (settingsNotifier.getNszDecompressEnabled()) {
        final downloadDir = settingsNotifier.getDownloadDir(game.consoleId);
        final keysPath = settingsNotifier.getNszKeysPath() ?? '';
        final queueNotifier = _ref.read(taskQueueProvider.notifier);
        debugPrint('Auto-decompressing NSZ for task: $taskId');
        Future.microtask(() => queueNotifier.enqueue(taskId, TaskType.nszDecompression, {
          'taskId': taskId,
          'nszFilePath': p.join(downloadDir, game.filename),
          'outputDir': downloadDir,
          'keysPath': keysPath,
        }));
      }
      return; // Never ZIP-extract a .nsz file
    }

    final autoExtract = settingsNotifier.getAutoExtract(game.consoleId);
    if (!autoExtract) return;

    debugPrint('Auto-extracting for task: $taskId');
    final queueNotifier = _ref.read(taskQueueProvider.notifier);
    Future.microtask(() => queueNotifier.enqueue(taskId, TaskType.extraction, {'taskId': taskId}));
  }

  bool isTaskDownloadable(String taskId) {
    if (state.completedTasks.contains(taskId)) return false;
    final taskStatus = state.taskStatus[taskId];
    switch (taskStatus) {
      case null:
      case TaskStatus.canceled:
      case TaskStatus.complete:
      case TaskStatus.failed:
        return true;
      default:
        return false;
    }
  }

  Future<void> startDownloads(List<Game> games, String downloadDir, String? group) async {
    if (games.isEmpty) return;

    final queueNotifier = _ref.read(taskQueueProvider.notifier);

    for (final game in games) {
      final taskId = game.gameId;

      if (!isTaskDownloadable(taskId)) continue;

      queueNotifier.enqueue(taskId, TaskType.download, {
        'game': game.toJson(),
        'downloadDir': downloadDir,
        'group': group ?? 'default',
      });
    }
  }

  Future<void> startSelectedDownloads(String downloadDir, String? group) async {
    final catalogState = _ref.read(catalogProvider);
    if (catalogState.selectedGames.isEmpty) return;

    final games = catalogState.games.where((game) => catalogState.selectedGames.contains(game.gameId)).toList();

    await startDownloads(games, downloadDir, group);
  }

  Future<void> startSingleDownload(Game game) async {
    final settingsNotifier = _ref.read(settingsProvider.notifier);
    final downloadDir = settingsNotifier.getDownloadDir(game.consoleId);
    final queueNotifier = _ref.read(taskQueueProvider.notifier);

    queueNotifier.enqueue(game.gameId, TaskType.download, {
      'game': game.toJson(),
      'downloadDir': downloadDir,
      'group': game.consoleId,
    });

    catalogNotifier.deselectGame(game.gameId);
  }

  Future<void> pauseTask(String taskId) async {
    final task = _tasks[taskId];
    if (task != null) {
      await downloadService.pauseTask(task);
    }
  }

  Future<void> resumeTask(String taskId) async {
    final task = _tasks[taskId];
    if (task != null) {
      await downloadService.resumeTask(task);
    }
  }

  Future<void> cancelTask(String taskId) async {
    final task = _tasks[taskId];
    if (task != null) {
      await downloadService.cancelTask(task);
    } else {
      await downloadService.cancelTaskById(taskId);
    }

    final taskStatus = Map<String, TaskStatus>.from(state.taskStatus);
    final taskProgress = Map<String, TaskProgressUpdate>.from(state.taskProgress);

    taskStatus.remove(taskId);
    taskProgress.remove(taskId);
    _tasks.remove(taskId);

    catalogNotifier.deselectGame(taskId);

    state = state.copyWith(
      taskStatus: taskStatus,
      taskProgress: taskProgress,
    );

    gameStateManager.updateDownloadState(
      taskId,
      TaskStatus.canceled,
      null,
      false,
    );
  }

  bool hasDownloadableSelectedGames() {
    final catalogState = _ref.read(catalogProvider);
    return catalogState.selectedGames.any((taskId) => isTaskDownloadable(taskId));
  }

  // WARNING: This is tends to be problematic if keeps giving headaches:
  // just use downloadService.cancelTaskById in the allTasks loop instead of this whole control and call it a day
  Future<void> _syncWithBackgroundTasks() async {
    debugPrint('_syncWithBackgroundTasks: Starting sync with background tasks');
    try {
      final allTasks = await FileDownloader().allTasks(allGroups: true);
      debugPrint('_syncWithBackgroundTasks: Found ${allTasks.length} tasks from FileDownloader');

      final taskStatus = Map<String, TaskStatus>.from(state.taskStatus);
      final taskProgress = Map<String, TaskProgressUpdate>.from(state.taskProgress);

      for (final task in allTasks) {
        debugPrint('_syncWithBackgroundTasks: Inspecting task ${task.taskId} of type ${task.runtimeType}');
        if (task is DownloadTask) {
          _tasks[task.taskId] = task;
          debugPrint('_syncWithBackgroundTasks: Registered DownloadTask ${task.taskId}');

          if (!taskStatus.containsKey(task.taskId)) {
            taskStatus[task.taskId] = TaskStatus.running;
            debugPrint('_syncWithBackgroundTasks: Set status to running for ${task.taskId}');
          }
        } else {
          debugPrint('_syncWithBackgroundTasks: Skipped non-DownloadTask ${task.taskId}');
        }
      }

      // Cancel any paused tasks that are still in the database
      try {
        final pausedRecords = await FileDownloader().database.allRecordsWithStatus(TaskStatus.paused);
        debugPrint('_syncWithBackgroundTasks: Found ${pausedRecords.length} paused tasks from FileDownloader');
        for (final record in pausedRecords) {
          if (record.status == TaskStatus.paused) {
            debugPrint('_syncWithBackgroundTasks: Found paused task ${record.taskId} -> cancelling');

            try {
              await downloadService.cancelTaskById(record.taskId);
            } catch (e) {
              debugPrint('_syncWithBackgroundTasks: Error cancelling paused task ${record.taskId}: $e');
            }

            taskStatus.remove(record.taskId);
            taskProgress.remove(record.taskId);
            _tasks.remove(record.taskId);

            debugPrint('_syncWithBackgroundTasks: Paused task ${record.taskId} Cancelled and removed from tracking');
          }
        }
      } catch (e) {
        debugPrint('_syncWithBackgroundTasks: Could not process paused tasks: $e');
      }

      state = state.copyWith(
        taskStatus: taskStatus,
        taskProgress: taskProgress,
      );
      debugPrint('_syncWithBackgroundTasks: State updated with ${taskStatus.length} statuses');

      _updateDownloadingState();

      debugPrint('_syncWithBackgroundTasks: Finished updating downloading state');
    } catch (e, stack) {
      debugPrint('Error syncing with background tasks: $e');
      debugPrint('Stack trace: $stack');
    }
  }

  Future<void> executeDownload(Game game, String downloadDir, String group) async {
    final taskId = game.gameId;
    final fileName = game.filename;

    if (!isTaskDownloadable(taskId)) return;

    // Create the target dir first — free-space checks on a missing dir read 0.
    await Directory(downloadDir).create(recursive: true);

    // Check for sufficient disk space before downloading
    final freeSpace = await DirectoryService.getFreeSpace(downloadDir);
    if (freeSpace < game.size) {
      debugPrint('Insufficient disk space for download: available $freeSpace bytes, need ${game.size} bytes');
      return _handleStatusUpdate(
        TaskStatusUpdate(DownloadTask(taskId: taskId, url: game.url), TaskStatus.failed),
        'Insufficient disk space',
      );
    }

    debugPrint('Executing download task for: $taskId -> $downloadDir/$fileName');

    // Same auth as catalog fetches: console token (cookie/bearer) or IA S3 keys.
    final settings = _ref.read(settingsProvider);
    final console = (await CatalogService().getConsoles())[game.consoleId];
    final isIaUrl = game.url.contains('archive.org/download/');
    final headers = <String, String>{
      ...buildConsoleAuthHeaders(console?.auth, tokenOverride: settings.consoleSettings[game.consoleId]?.authToken),
      // Restricted ("loggedin") IA items only accept session cookies; S3 keys
      // are kept as a fallback for older flows.
      if (isIaUrl && (settings.iaCookies?.isNotEmpty ?? false))
        'Cookie': settings.iaCookies!
      else if (isIaUrl && (settings.iaAccessKey?.isNotEmpty ?? false) && (settings.iaSecretKey?.isNotEmpty ?? false))
        'Authorization': 'LOW ${settings.iaAccessKey}:${settings.iaSecretKey}',
    };

    // Authenticated downloads: enqueue against the final URL — the downloader
    // drops auth headers on cross-host redirects (archive.org data nodes).
    var url = game.url;
    if (headers.isNotEmpty) {
      try {
        url = await resolveRedirects(game.url, headers);
      } catch (e) {
        debugPrint('Redirect resolution failed for $taskId, using original URL: $e');
      }
    }

    final downloadTask = downloadService.createDownloadTask(
      taskId: taskId,
      url: url,
      fileName: fileName,
      directory: downloadDir,
      group: group,
      headers: headers.isEmpty ? null : headers,
    );

    _tasks[taskId] = downloadTask;

    final enqueued = await downloadService.enqueuedTask(downloadTask);
    if (enqueued) {
      final taskStatus = Map<String, TaskStatus>.from(state.taskStatus);
      taskStatus[taskId] = TaskStatus.enqueued;
      state = state.copyWith(taskStatus: taskStatus);
    }
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    super.dispose();
  }
}
