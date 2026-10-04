import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/task_queue_model.dart';
import 'package:roms_downloader/providers/task_queue_provider.dart';
import 'package:roms_downloader/providers/download_provider.dart';
import 'package:roms_downloader/providers/extraction_provider.dart';
import 'package:roms_downloader/providers/game_state_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/game_state_model.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/file_ops.dart';
import 'package:roms_downloader/utils/remote_tree.dart';

class TaskQueueService {
  /// Returns a human-readable reason downloads can't start, or null when OK.
  static Future<String?> _downloadBlockReason(WidgetRef ref, List<Game> games, String? consoleId) async {
    final console = (await CatalogService().getConsoles())[consoleId];
    if (console == null) return null;

    if (console.hasTokenAuth) {
      final settings = ref.read(settingsProvider);
      final token = settings.consoleSettings[console.id]?.authToken ?? console.auth?['token'] as String? ?? '';
      if (token.isEmpty) {
        return console.authMessage ?? 'This system requires authentication. Sign in from the system settings first.';
      }
    }

    final settingsNotifier = ref.read(settingsProvider.notifier);
    if (settingsNotifier.getNszDecompressEnabled() &&
        (settingsNotifier.getNszKeysPath() ?? '').isEmpty &&
        games.any((g) => g.filename.toLowerCase().endsWith('.nsz'))) {
      return 'NSZ decompression is enabled but no keys file is set. Add prod.keys in the system settings (or disable NSZ decompression).';
    }

    return null;
  }

  static Future<void> startDownloads(WidgetRef ref, BuildContext context, List<Game> games, String? consoleId) async {
    final blockReason = await _downloadBlockReason(ref, games, consoleId);
    if (blockReason != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(blockReason), duration: const Duration(seconds: 5)),
        );
      }
      return;
    }

    final settingsNotifier = ref.read(settingsProvider.notifier);
    final downloadDir = settingsNotifier.getDownloadDir(consoleId);
    final queueNotifier = ref.read(taskQueueProvider.notifier);

    for (final game in games) {
      queueNotifier.enqueue(game.gameId, TaskType.download, {
        'game': game.toJson(),
        'downloadDir': downloadDir,
        'group': consoleId ?? 'default',
      });
    }
  }

  /// Queues a network transfer (SMB/FTP download or zip) as a background
  /// task with a task-manager row titled [title]. [run] is held in memory
  /// with the task; it isn't persisted.
  static void enqueueTransfer(
    WidgetRef ref,
    BuildContext context, {
    required String title,
    required String verb,
    required String label,
    required TransferJob run,
  }) {
    // Unique per job: the task key comes from the URL's file name.
    final game = Game(title: title, url: 'https://manual/net-${DateTime.now().microsecondsSinceEpoch}.task', size: 0, consoleId: 'manual');
    ref.read(gameStateManagerProvider.notifier).registerTransientGame(game);
    ref.read(taskQueueProvider.notifier).enqueue(game.gameId, TaskType.remoteTransfer, {
      'taskId': game.gameId,
      'verb': verb,
      'label': label,
      'run': run,
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title added to the task list')));
  }

  static void startExtraction(WidgetRef ref, String taskId) {
    final queueNotifier = ref.read(taskQueueProvider.notifier);
    queueNotifier.enqueue(taskId, TaskType.extraction, {'taskId': taskId});
  }

  static void cancelTask(WidgetRef ref, Game game, GameState gameState) {
    final taskId = game.gameId;

    if (gameState.status == GameStatus.downloading || gameState.status == GameStatus.downloadPaused || gameState.status == GameStatus.downloadFailed) {
      final downloadNotifier = ref.read(downloadProvider.notifier);
      downloadNotifier.cancelTask(taskId);
      return;
    }

    final queueState = ref.read(taskQueueProvider);
    final hasQueued = queueState.tasks.any((t) => t.id == taskId && (t.status == TaskQueueStatus.waiting || t.status == TaskQueueStatus.failed));
    if (!hasQueued) return;

    final queueNotifier = ref.read(taskQueueProvider.notifier);
    queueNotifier.cancelQueuedTask(taskId);
  }

  static void pauseDownloadTask(WidgetRef ref, String taskId) {
    final downloadNotifier = ref.read(downloadProvider.notifier);
    downloadNotifier.pauseTask(taskId);
  }

  static void resumeDownloadTask(WidgetRef ref, String taskId) {
    final downloadNotifier = ref.read(downloadProvider.notifier);
    downloadNotifier.resumeTask(taskId);
  }

  static Future<void> executeTask(Ref ref, TaskQueueNotifier notifier, QueuedTask task) async {
    try {
      switch (task.type) {
        case TaskType.download:
          await _executeDownloadTask(ref, task, notifier);
          break;
        case TaskType.extraction:
          await _executeExtractionTask(ref, task, notifier);
          break;
        case TaskType.nszDecompression:
          await _executeNszDecompressionTask(ref, task, notifier);
          break;
        case TaskType.chdConversion:
          await _executeChdConversionTask(ref, task, notifier);
          break;
        case TaskType.cia3dsConversion:
          await _executeCia3dsConversionTask(ref, task, notifier);
          break;
        case TaskType.fileCopy:
          final move = task.params['move'] as bool? ?? false;
          ref.read(extractionProvider.notifier).fileTask(
                taskId: task.params['taskId'] as String,
                verb: move ? 'Moving' : 'Copying',
                label: task.params['label'] as String,
                run: (onProgress) => FileOps.copyInto(
                  (task.params['sources'] as List).cast<String>(),
                  task.params['destDir'] as String,
                  move: move,
                  onProgress: onProgress,
                ),
              );
          break;
        case TaskType.fileZip:
          ref.read(extractionProvider.notifier).fileTask(
                taskId: task.params['taskId'] as String,
                verb: 'Zipping',
                label: task.params['label'] as String,
                run: (onProgress) => FileOps.zip(
                  (task.params['sources'] as List).cast<String>(),
                  task.params['outZip'] as String,
                  onProgress: onProgress,
                ),
              );
          break;
        case TaskType.remoteTransfer:
          ref.read(extractionProvider.notifier).fileTask(
                taskId: task.params['taskId'] as String,
                verb: task.params['verb'] as String,
                label: task.params['label'] as String,
                run: task.params['run'] as TransferJob,
              );
          break;
        case TaskType.archiveExtraction:
          // Fire and forget — archiveExtract manages its own queue-status updates.
          ref.read(extractionProvider.notifier).archiveExtract(
                taskId: task.params['taskId'] as String,
                archivePath: task.params['archivePath'] as String,
                outputDir: task.params['outputDir'] as String,
              );
          break;
      }
    } catch (e) {
      debugPrint('Task execution error for ${task.id}: $e');
      notifier.updateTaskStatus(task.id, TaskQueueStatus.failed, error: e.toString());
    }
  }

  static Future<void> _executeDownloadTask(Ref ref, QueuedTask task, TaskQueueNotifier notifier) async {
    final downloadNotifier = ref.read(downloadProvider.notifier);
    final game = Game.fromJson(task.params['game']);
    final downloadDir = task.params['downloadDir'] as String;
    final group = task.params['group'] as String;

    downloadNotifier.executeDownload(game, downloadDir, group);
  }

  static Future<void> _executeExtractionTask(Ref ref, QueuedTask task, TaskQueueNotifier notifier) async {
    final extractionNotifier = ref.read(extractionProvider.notifier);
    final taskId = task.params['taskId'] as String;

    extractionNotifier.extractFile(taskId);
  }

  static Future<void> _executeNszDecompressionTask(Ref ref, QueuedTask task, TaskQueueNotifier notifier) async {
    final extractionNotifier = ref.read(extractionProvider.notifier);

    // Fire and forget — nszDecompress manages its own queue-status updates.
    extractionNotifier.nszDecompress(
      taskId: task.params['taskId'] as String,
      nszFilePath: task.params['nszFilePath'] as String,
      outputDir: task.params['outputDir'] as String,
      keysPath: task.params['keysPath'] as String? ?? '',
    );
  }

  static Future<void> _executeChdConversionTask(Ref ref, QueuedTask task, TaskQueueNotifier notifier) async {
    final extractionNotifier = ref.read(extractionProvider.notifier);

    // Fire and forget — chdConvert manages its own queue-status updates.
    extractionNotifier.chdConvert(
      taskId: task.params['taskId'] as String,
      inputPath: task.params['inputPath'] as String,
      outputDir: task.params['outputDir'] as String,
      chdmanPath: task.params['chdmanPath'] as String?,
    );
  }

  static Future<void> _executeCia3dsConversionTask(Ref ref, QueuedTask task, TaskQueueNotifier notifier) async {
    final extractionNotifier = ref.read(extractionProvider.notifier);

    // Fire and forget — cia3dsConvert manages its own queue-status updates.
    extractionNotifier.cia3dsConvert(
      taskId: task.params['taskId'] as String,
      inputPath: task.params['inputPath'] as String,
      outputDir: task.params['outputDir'] as String,
      boot9Path: task.params['boot9Path'] as String?,
      ignoreEncryption: task.params['ignoreEncryption'] as bool? ?? false,
    );
  }
}
