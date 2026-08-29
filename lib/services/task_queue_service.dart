import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/task_queue_model.dart';
import 'package:roms_downloader/providers/task_queue_provider.dart';
import 'package:roms_downloader/providers/download_provider.dart';
import 'package:roms_downloader/providers/extraction_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/game_state_model.dart';
import 'package:roms_downloader/services/catalog_service.dart';

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
}
