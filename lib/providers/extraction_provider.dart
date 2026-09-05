import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/extraction_model.dart';
import 'package:roms_downloader/models/task_queue_model.dart';
import 'package:roms_downloader/providers/game_state_provider.dart';
import 'package:roms_downloader/providers/library_snapshot_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/task_queue_provider.dart';
import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/services/extraction_service.dart';
import 'package:roms_downloader/services/nsz_service.dart';
import 'package:roms_downloader/services/chd_service.dart';

final extractionProvider = StateNotifierProvider<ExtractionNotifier, ExtractionState>((ref) {
  final gameStateManager = ref.read(gameStateManagerProvider.notifier);
  return ExtractionNotifier(ref, gameStateManager);
});

class ExtractionNotifier extends StateNotifier<ExtractionState> {
  final Ref _ref;
  final GameStateManager gameStateManager;

  ExtractionNotifier(this._ref, this.gameStateManager) : super(const ExtractionState());

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

    try {
      ExtractionService.startExtraction(
        taskId: taskId,
        filePath: filePath,
        extractionDir: extractionDir,
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

    gameStateManager.updateExtractionState(taskId, ExtractionStatus.failed, 0.0);
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

    gameStateManager.updateExtractionState(taskId, ExtractionStatus.failed, 0.0);
  }

  bool _hasActiveExtractions(Map<String, ExtractionTaskState> tasks) {
    return tasks.values.any((task) => task.status == ExtractionStatus.extracting);
  }
}
