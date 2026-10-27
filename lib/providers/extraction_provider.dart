import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/archive_extract_service.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/services/file_ops.dart';
import 'package:retro_toolbox/services/extraction_service.dart';
import 'package:retro_toolbox/services/nsz_service.dart';
import 'package:retro_toolbox/services/chd_service.dart';
import 'package:retro_toolbox/services/catalog_service.dart';

final extractionProvider = StateNotifierProvider<ExtractionNotifier, ExtractionState>((ref) {
  final gameStateManager = ref.read(gameStateManagerProvider.notifier);
  return ExtractionNotifier(ref, gameStateManager);
});

class ExtractionNotifier extends StateNotifier<ExtractionState> {
  final Ref _ref;
  final GameStateManager gameStateManager;

  ExtractionNotifier(this._ref, this.gameStateManager) : super(const ExtractionState());

  /// Running file-browser jobs (fileTask, archiveExtract) by task id; completed
  /// by [cancel].
  final _cancels = <String, Completer<void>>{};

  /// Stops a running file-browser job: it leaves the queue at once, and the
  /// job stops (deleting its partial output) as soon as it can. Copies and
  /// downloads stop at their next progress report, zips and desktop ZIP
  /// extraction right away, Android ZIP extraction at its next entry.
  void cancel(String taskId) {
    final c = _cancels.remove(taskId);
    if (c == null) return;
    c.complete();
    removeTask(taskId);
    // The notification ends with the job itself (it may still be stopping).
    final queue = _ref.read(taskQueueProvider.notifier);
    queue.updateTaskStatus(taskId, TaskQueueStatus.cancelled); // frees the slot
    queue.cancelQueuedTask(taskId);
  }

  Future<void> extractFile(String taskId) async {
    final gameState = gameStateManager.state[taskId];
    if (gameState == null) {
      debugPrint('Game state not found for taskId: $taskId');
      return;
    }

    final game = gameState.game;
    final settingsNotifier = _ref.read(settingsProvider.notifier);
    final downloadDir = settingsNotifier.getDownloadDir(game.consoleId);
    final filePath = path.join(downloadDir, game.filename);
    final extractionDir = settingsNotifier.getExtractToFolder(game.consoleId)
        ? path.join(path.dirname(filePath), path.basenameWithoutExtension(filePath))
        : path.dirname(filePath);

    if (!DirectoryService.isCompressedFile(filePath)) {
      debugPrint('File is not compressed: $filePath');
      return;
    }

    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    tasks[taskId] = ExtractionTaskState(
      taskId: taskId,
      status: ExtractionStatus.extracting,
      progress: 0.0,
    );

    state = state.copyWith(
      tasks: tasks,
      isExtracting: _hasActiveExtractions(tasks),
    );

    gameStateManager.updateExtractionState(taskId, ExtractionStatus.extracting, 0.0);

    // Check for sufficient disk space before extraction
    final freeSpace = await DirectoryService.getFreeSpace(downloadDir);
    if (freeSpace < game.size) {
      debugPrint('Insufficient disk space for extraction: available $freeSpace bytes, need ${game.size} bytes');
      return Future.delayed(const Duration(milliseconds: 100), () => _updateError(taskId, 'Insufficient disk space', extractionDir));
    }

    debugPrint('Starting extraction for: $filePath');

    // should_unzip archives should yield only the console's file_format payload
    // (e.g. .3ds/.cia); drop bundled junk during extraction.
    final allowed = CatalogService.consoleByIdSync(game.consoleId)?.fileFormat?.map((e) => e.toLowerCase()).toList() ?? const [];

    try {
      ExtractionService.startExtraction(
        taskId: taskId,
        filePath: filePath,
        extractionDir: extractionDir,
        allowedExtensions: allowed,
        onProgress: _updateProgress,
        onError: _updateError,
        onComplete: _updateCompleted,
      );
    } catch (e) {
      debugPrint('Extraction error: $e');
      _updateError(taskId, e.toString(), extractionDir);
    }
  }

  Future<void> nszDecompress({
    required String taskId,
    required String nszFilePath,
    required String outputDir,
    required String keysPath,
  }) async {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    tasks[taskId] = ExtractionTaskState(
      taskId: taskId,
      status: ExtractionStatus.extracting,
      progress: 0.0,
    );
    state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
    gameStateManager.updateExtractionState(taskId, ExtractionStatus.extracting, 0.0);

    final fileName = path.basename(nszFilePath);
    await ExtractionService.startNotification(taskId, 'Decompressing', 'Decompressing $fileName...');

    try {
      await NszService.decompressNsz(
        nszFilePath: nszFilePath,
        outputDir: outputDir,
        keysPath: keysPath.isNotEmpty ? keysPath : null,
        onProgress: (progress) {
          _updateProgress(taskId, progress);
          ExtractionService.updateNotification('Decompressing $fileName... ${(progress * 100).round()}%');
        },
      );
      await _onNszCompleted(taskId, nszFilePath, outputDir);
    } catch (e) {
      debugPrint('NSZ decompression error: $e');
      _onNszError(taskId, e.toString());
    } finally {
      ExtractionService.endNotification(taskId);
    }
  }

  Future<void> chdConvert({
    required String taskId,
    required String inputPath,
    required String outputDir,
    String? chdmanPath,
  }) async {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    tasks[taskId] = ExtractionTaskState(taskId: taskId, status: ExtractionStatus.extracting, progress: 0.0);
    state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
    gameStateManager.updateExtractionState(taskId, ExtractionStatus.extracting, 0.0);

    final fileName = path.basename(inputPath);
    final verb = ChdService.modeForInput(inputPath) == ChdMode.extract ? 'Extracting' : 'Compressing';
    await ExtractionService.startNotification(taskId, verb, '$verb $fileName...');

    try {
      await ChdService().convert(
        inputPath: inputPath,
        outputDir: outputDir,
        chdmanPath: chdmanPath,
        onProgress: (progress) {
          _updateProgress(taskId, progress);
          ExtractionService.updateNotification('$verb $fileName... ${(progress * 100).round()}%');
        },
      );
      _onConversionCompleted(taskId);
    } catch (e) {
      debugPrint('CHD conversion error: $e');
      _onNszError(taskId, e.toString());
    } finally {
      ExtractionService.endNotification(taskId);
    }
  }

  Future<void> cia3dsConvert({
    required String taskId,
    required String inputPath,
    required String outputDir,
    String? boot9Path,
    bool ignoreEncryption = false,
  }) async {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    tasks[taskId] = ExtractionTaskState(taskId: taskId, status: ExtractionStatus.extracting, progress: 0.0);
    state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
    gameStateManager.updateExtractionState(taskId, ExtractionStatus.extracting, 0.0);

    final fileName = path.basename(inputPath);
    await ExtractionService.startNotification(taskId, 'Converting', 'Converting $fileName to CIA...');

    try {
      await NszService.convert3dsToCia(
        inputFile: inputPath,
        outputDir: outputDir,
        boot9Path: boot9Path,
        ignoreEncryption: ignoreEncryption,
        onProgress: (progress) {
          _updateProgress(taskId, progress);
          ExtractionService.updateNotification('Converting $fileName... ${(progress * 100).round()}%');
        },
      );
      _onConversionCompleted(taskId);
    } catch (e) {
      debugPrint('3DS→CIA conversion error: $e');
      _onNszError(taskId, e.toString());
    } finally {
      ExtractionService.endNotification(taskId);
    }
  }

  /// The archive tool's extraction (.zip or .rar to any folder), run as a
  /// background task with progress in the task manager and notification.
  /// Unlike a downloaded game's auto-extract, the archive is kept.
  Future<void> archiveExtract({
    required String taskId,
    required String archivePath,
    required String outputDir,
  }) async {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    tasks[taskId] = ExtractionTaskState(taskId: taskId, status: ExtractionStatus.extracting, progress: 0.0);
    state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
    gameStateManager.updateExtractionState(taskId, ExtractionStatus.extracting, 0.0);
    final cancel = _cancels[taskId] = Completer<void>();
    // outputDir is a fresh folder made for this task, so a cancel removes it whole.
    Future<void> discard() async {
      try {
        await Directory(outputDir).delete(recursive: true);
      } catch (_) {}
    }

    // Every path ends with done/failed even after a cancel (a killed isolate
    // and the Android service report an error, RAR runs to the end): then
    // nothing is kept.
    void done() {
      if (cancel.isCompleted) {
        discard();
        return;
      }
      _cancels.remove(taskId);
      _onConversionCompleted(taskId);
    }

    void failed(String error) {
      if (cancel.isCompleted) {
        discard();
        return;
      }
      _cancels.remove(taskId);
      _onNszError(taskId, error);
    }

    final fileName = path.basename(archivePath);
    if (ArchiveExtractService.archiveKind(archivePath) == ArchiveKind.zip) {
      // Same background path as game auto-extract (foreground service on
      // Android, an isolate elsewhere), which already reports progress.
      await ExtractionService.startExtraction(
        taskId: taskId,
        filePath: archivePath,
        extractionDir: outputDir,
        onProgress: (id, progress) {
          if (!cancel.isCompleted) _updateProgress(id, progress);
        },
        onComplete: (_, __) => done(),
        onError: (_, error, __) => failed(error),
        cancelled: cancel.future,
      );
      return;
    }

    await ExtractionService.startNotification(taskId, 'Extracting', 'Extracting $fileName...');
    try {
      // ponytail: the RAR plugin can't be stopped, so a cancelled RAR runs to
      // the end in the background and its output is deleted then.
      await ArchiveExtractService().extract(archivePath, outputDir, onProgress: (progress) {
        if (cancel.isCompleted) return;
        _updateProgress(taskId, progress);
        ExtractionService.updateNotification('Extracting $fileName... ${(progress * 100).round()}%');
      });
      done();
    } catch (e) {
      debugPrint('Archive extraction error: $e');
      failed(e.toString());
    } finally {
      ExtractionService.endNotification(taskId);
    }
  }

  /// A file explorer job (copy, move, zip) as a background task: progress in
  /// the task manager and the notification, like the conversions.
  Future<void> fileTask({
    required String taskId,
    required String verb,
    required String label,
    required Future<void> Function(FileOpsProgress onProgress) run,
  }) async {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    tasks[taskId] = ExtractionTaskState(taskId: taskId, status: ExtractionStatus.extracting, progress: 0.0);
    state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
    gameStateManager.updateExtractionState(taskId, ExtractionStatus.extracting, 0.0);
    final cancel = _cancels[taskId] = Completer<void>();

    await ExtractionService.startNotification(taskId, verb, '$verb $label...');
    var lastPct = -1;
    try {
      await run((done, total) {
        // Jobs stop (and clean up) when their progress callback throws.
        if (cancel.isCompleted) throw const TaskCancelledException();
        final progress = total > 0 ? done / total : 0.0;
        final pct = (progress * 100).floor();
        if (pct == lastPct) return; // byte-level callbacks; repaint per percent
        lastPct = pct;
        _updateProgress(taskId, progress);
        ExtractionService.updateNotification('$verb $label... $pct%');
      });
      if (cancel.isCompleted) return; // finished before it saw the cancel
      _onConversionCompleted(taskId);
    } catch (e) {
      if (cancel.isCompleted) return;
      debugPrint('$verb failed: $e');
      _onNszError(taskId, e is StateError ? e.message : e.toString());
    } finally {
      _cancels.remove(taskId);
      ExtractionService.endNotification(taskId);
    }
  }

  /// Forgets a task's progress entry (a cancelled failed task).
  void removeTask(String taskId) {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks)..remove(taskId);
    state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
  }

  void _onConversionCompleted(String taskId) {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    final currentTask = tasks[taskId];
    if (currentTask != null) {
      tasks[taskId] = currentTask.copyWith(status: ExtractionStatus.completed, progress: 1.0);
      state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
    }
    _ref.read(taskQueueProvider.notifier).updateTaskStatus(taskId, TaskQueueStatus.completed);
    gameStateManager.updateExtractionState(taskId, ExtractionStatus.completed, 1.0);
    // ponytail: source file is kept — a conversion isn't a throwaway temp like a
    // downloaded .nsz. Add an opt-in "delete source" later if users ask.
  }

  Future<void> _onNszCompleted(String taskId, String nszFilePath, String outputDir) async {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    final currentTask = tasks[taskId];
    if (currentTask != null) {
      tasks[taskId] = currentTask.copyWith(status: ExtractionStatus.completed, progress: 1.0);
      state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
    }

    final queueNotifier = _ref.read(taskQueueProvider.notifier);
    queueNotifier.updateTaskStatus(taskId, TaskQueueStatus.completed);

    // Delete the source .nsz file
    try {
      final nszFile = File(nszFilePath);
      if (await nszFile.exists()) {
        await nszFile.delete();
        debugPrint('Deleted NSZ source: $nszFilePath');
      }
    } catch (e) {
      debugPrint('Failed to delete NSZ source: $e');
    }

    final game = gameStateManager.state[taskId]?.game;
    if (game != null) {
      final dir = _ref.read(settingsProvider.notifier).getDownloadDir(game.consoleId);
      if (dir.isNotEmpty) {
        _ref.read(librarySnapshotProvider(dir).notifier).markFileRemoved(game.filename);
      }
    }

    gameStateManager.updateExtractionState(taskId, ExtractionStatus.completed, 1.0);
  }

  void _onNszError(String taskId, String error) {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    final currentTask = tasks[taskId];
    if (currentTask != null) {
      tasks[taskId] = currentTask.copyWith(status: ExtractionStatus.failed, error: error);
      state = state.copyWith(tasks: tasks, isExtracting: _hasActiveExtractions(tasks));
    }

    final queueNotifier = _ref.read(taskQueueProvider.notifier);
    queueNotifier.updateTaskStatus(taskId, TaskQueueStatus.failed, error: error);

    gameStateManager.updateExtractionState(taskId, ExtractionStatus.failed, 0.0, error: error);
  }

  void retryExtraction(String taskId) {
    final taskState = state.getTaskState(taskId);
    if (taskState?.status == ExtractionStatus.failed) {
      final queueNotifier = _ref.read(taskQueueProvider.notifier);
      queueNotifier.enqueue(taskId, TaskType.extraction, {'taskId': taskId});
    }
  }

  void _updateProgress(String taskId, double progress) {
    debugPrint('Updating progress for task $taskId: $progress');
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    final currentTask = tasks[taskId];
    if (currentTask != null) {
      tasks[taskId] = currentTask.copyWith(progress: progress);
      state = state.copyWith(tasks: tasks);
    }

    gameStateManager.updateExtractionState(taskId, ExtractionStatus.extracting, progress);
  }

  void _updateCompleted(String taskId, String extractionDir) async {
    debugPrint('Marking task $taskId as completed');
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    final currentTask = tasks[taskId];
    if (currentTask != null) {
      tasks[taskId] = currentTask.copyWith(
        status: ExtractionStatus.completed,
        progress: 1.0,
      );
      state = state.copyWith(
        tasks: tasks,
        isExtracting: _hasActiveExtractions(tasks),
      );
    }

    final queueNotifier = _ref.read(taskQueueProvider.notifier);
    queueNotifier.updateTaskStatus(taskId, TaskQueueStatus.completed);

    try {
      await _deleteOriginalFile(taskId);
    } catch (e) {
      debugPrint('Error deleting original file for task $taskId: $e');
    }

    final game = gameStateManager.state[taskId]?.game;
    if (game != null) {
      final dir = _ref.read(settingsProvider.notifier).getDownloadDir(game.consoleId);
      if (dir.isNotEmpty) {
        final snap = _ref.read(librarySnapshotProvider(dir).notifier);
        snap.markFileRemoved(game.filename);
        final baseNoExt = path.basenameWithoutExtension(game.filename);
        if (_ref.read(settingsProvider.notifier).getExtractToFolder(game.consoleId)) {
          snap.markDirAdded(baseNoExt);
        } else {
          // Root extraction: register the extracted sibling files.
          try {
            await for (final entity in Directory(dir).list(followLinks: false)) {
              if (entity is File && path.basenameWithoutExtension(entity.path) == baseNoExt) {
                snap.markFileAdded(path.basename(entity.path));
              }
            }
          } catch (e) {
            debugPrint('Error indexing extracted files: $e');
          }
        }
      }
    }

    gameStateManager.updateExtractionState(taskId, ExtractionStatus.completed, 1.0);
  }

  Future<void> _deleteOriginalFile(String taskId) async {
    final gameState = gameStateManager.state[taskId];
    if (gameState == null) return;

    final game = gameState.game;
    final settingsNotifier = _ref.read(settingsProvider.notifier);
    final downloadDir = settingsNotifier.getDownloadDir(game.consoleId);
    final filePath = path.join(downloadDir, game.filename);

    if (await DirectoryService.deleteFile(filePath)) {
      debugPrint('Deleted original file: $filePath');
    } else {
      debugPrint('Failed to delete original file: $filePath');
    }
  }

  void _updateError(String taskId, String error, String extractionDir) {
    final tasks = Map<String, ExtractionTaskState>.from(state.tasks);
    final currentTask = tasks[taskId];
    if (currentTask != null) {
      tasks[taskId] = currentTask.copyWith(
        status: ExtractionStatus.failed,
        error: error,
      );
      state = state.copyWith(
        tasks: tasks,
        isExtracting: _hasActiveExtractions(tasks),
      );
    }

    final queueNotifier = _ref.read(taskQueueProvider.notifier);
    queueNotifier.updateTaskStatus(taskId, TaskQueueStatus.failed, error: error);

    try {
      // Only clean up per-game subfolders. In root-extraction mode the
      // extraction dir IS the console download folder — never delete it.
      final game = gameStateManager.state[taskId]?.game;
      final downloadDir = game != null ? _ref.read(settingsProvider.notifier).getDownloadDir(game.consoleId) : '';
      final isSubfolder = downloadDir.isNotEmpty && path.normalize(extractionDir) != path.normalize(downloadDir);
      final dir = Directory(extractionDir);
      if (isSubfolder && dir.existsSync()) {
        dir.deleteSync(recursive: true);
        final snap = _ref.read(librarySnapshotProvider(downloadDir).notifier);
        snap.markDirRemoved(path.basename(extractionDir));
      }
    } catch (_) {}

    gameStateManager.updateExtractionState(taskId, ExtractionStatus.failed, 0.0, error: error);
  }

  bool _hasActiveExtractions(Map<String, ExtractionTaskState> tasks) {
    return tasks.values.any((task) => task.status == ExtractionStatus.extracting);
  }
}

/// Thrown from a cancelled job's progress callback to stop it.
class TaskCancelledException implements Exception {
  const TaskCancelledException();
  @override
  String toString() => 'Cancelled';
}
