import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive_io.dart' as virtual_archive;
import 'package:flutter_archive/flutter_archive.dart';
import 'dart:async';

class ExtractionService {
  static const String progressDataType = 'extraction_progress';
  static const String errorDataType = 'extraction_error';
  static const String completionDataType = 'extraction_completed';
  static final Set<String> _activeTasks = {};
  static final Map<String, Function(String taskId, double progress)> _onProgressCallbacks = {};
  static final Map<String, Function(String taskId, String error, String extractionDir)> _onErrorCallbacks = {};
  static final Map<String, Function(String taskId, String extractionDir)> _onCompleteCallbacks = {};
  static Timer? _serviceStopTimer;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.initCommunicationPort();

    FlutterForegroundTask.init(
      iosNotificationOptions: const IOSNotificationOptions(),
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'extraction_foreground_service',
        channelName: 'Extraction Service',
        channelDescription: 'Foreground service for file extraction',
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.once(),
      ),
    );

    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  static void _cleanup(String taskId) {
    _activeTasks.remove(taskId);
    _onProgressCallbacks.remove(taskId);
    _onErrorCallbacks.remove(taskId);
    _onCompleteCallbacks.remove(taskId);
    _debouncedStopServiceIfAllDone();
  }

  static void _debouncedStopServiceIfAllDone() {
    if (_activeTasks.isEmpty) {
      _serviceStopTimer?.cancel();
      _serviceStopTimer = Timer(const Duration(seconds: 30), () {
        FlutterForegroundTask.stopService();
        debugPrint('Foreground service stopped');
      });
    } else {
      _serviceStopTimer?.cancel();
      debugPrint('Cannot stop service, active tasks: ${_activeTasks.length}');
    }
  }

  static void _onReceiveTaskData(Object data) {
    if (data is Map) {
      final type = data['type'] as String?;
      final taskId = data['taskId'] as String?;
      final extractionDir = data['extractionDir'] ?? '';
      if (taskId == null) return;

      switch (type) {
        case ExtractionService.progressDataType:
          final progress = data['value'] as double?;
          if (progress != null) _onProgressCallbacks[taskId]?.call(taskId, progress);
          break;
        case ExtractionService.errorDataType:
          final error = data['message'] as String?;
          if (error != null) {
            _onErrorCallbacks[taskId]?.call(taskId, error, extractionDir);
            _cleanup(taskId);
          }
          break;
        case ExtractionService.completionDataType:
          _onCompleteCallbacks[taskId]?.call(taskId, extractionDir);
          _cleanup(taskId);
          break;
      }
    }
  }

  static Future<void> startExtraction({
    required String taskId,
    required String filePath,
    required String extractionDir,
    required Function(String taskId, double progress) onProgress,
    required Function(String taskId, String extractionDir) onComplete,
    required Function(String taskId, String error, String extractionDir) onError,
  }) async {
    // Foreground service is only supported on Android, so we use an isolate for extraction on other platforms.
    // Also Android is the only platform that supports native unzip, the other platforms must use virtual
    if (!Platform.isAndroid) {
      return extractInIsolate(
        taskId,
        filePath,
        extractionDir,
        onProgress: onProgress,
        onComplete: onComplete,
        onError: onError,
      );
    }

    _activeTasks.add(taskId);
    _onProgressCallbacks[taskId] = onProgress;
    _onErrorCallbacks[taskId] = onError;
    _onCompleteCallbacks[taskId] = onComplete;

    // Reset the stop timer avoiding closing the background service too early
    _serviceStopTimer?.cancel();

    final fileName = path.basename(filePath);

    // If first task, (re)start foreground service
    if (_activeTasks.length == 1) {
      await FlutterForegroundTask.startService(
        serviceId: 1,
        notificationTitle: 'Extracting Archive',
        notificationText: 'Extracting $fileName...',
        notificationIcon: const NotificationIcon(metaDataName: 'ic_notification'),
        callback: extractionTaskCallback,
      );
    } else {
      // if not the first task, just update the notification
      FlutterForegroundTask.updateService(notificationText: 'Extracting $fileName...');
    }

    debugPrint('Sending extraction task to foreground service: $filePath');

    FlutterForegroundTask.sendDataToTask({
      'action': 'extract',
      'taskId': taskId,
      'filePath': filePath,
      'extractionDir': extractionDir,
    });
  }

  // NSZ decompression runs in the main isolate (serious_python worker), not the
  // extraction foreground task. These drive the same foreground-service
  // notification so it shows live progress AND keeps the process alive in the
  // background during a long decompression.
  static Future<void> startNotification(String taskId, String title, String text) async {
    if (!Platform.isAndroid) return;
    _activeTasks.add(taskId);
    _serviceStopTimer?.cancel();
    if (_activeTasks.length == 1) {
      await FlutterForegroundTask.startService(
        serviceId: 1,
        notificationTitle: title,
        notificationText: text,
        notificationIcon: const NotificationIcon(metaDataName: 'ic_notification'),
        callback: extractionTaskCallback,
      );
    } else {
      FlutterForegroundTask.updateService(notificationText: text);
    }
  }

  static void updateNotification(String text) {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.updateService(notificationText: text);
  }

  static void endNotification(String taskId) {
    if (!Platform.isAndroid) return;
    _cleanup(taskId);
  }

  static Future<void> extractInIsolate(
    String taskId,
    String filePath,
    String extractionDir, {
    required Function(String taskId, double progress) onProgress,
    required Function(String taskId, String extractionDir) onComplete,
    required Function(String taskId, String error, String extractionDir) onError,
  }) async {
    final receivePort = ReceivePort();

    receivePort.listen((message) {
      if (message['type'] == 'progress') {
        onProgress(taskId, message['value']);
      } else if (message['type'] == 'error') {
        onError(taskId, message['message'], extractionDir);
        receivePort.close();
      } else if (message['type'] == 'complete') {
        onComplete(taskId, extractionDir);
        receivePort.close();
      }
    });

    await Isolate.spawn(_extractInIsolate, {
      'taskId': taskId,
      'filePath': filePath,
      'extractionDir': extractionDir,
      'sendPort': receivePort.sendPort,
    });
  }

  static Future<void> _extractInIsolate(Map<String, dynamic> params) async {
    final sendPort = params['sendPort'] as SendPort;
    try {
      sendPort.send({'type': 'progress', 'value': 0.1});
      var extractedFiles = 0;
      await virtual_archive.extractFileToDisk(params['filePath'], params['extractionDir'], callback: (archiveFile) {
        final progress = (0.1 + (++extractedFiles / 4) * 0.85).clamp(0.1, 0.95);
        sendPort.send({'type': 'progress', 'value': progress});
      });
      await _flattenSingleTopLevelDir(params['extractionDir']);
      // Zips can carry mode-000 entries; make extracted files readable.
      if (!Platform.isWindows) {
        await Process.run('chmod', ['-R', 'u+rwX,go+rX', params['extractionDir']]);
      }
      sendPort.send({'type': 'complete'});
    } catch (e) {
      debugPrint('Extraction error: $e');
      sendPort.send({'type': 'error', 'message': 'Failed to extract: $e'});
    }
  }
}

/// If the extraction produced exactly one top-level directory (a common ZIP
/// wrapper like `GameName/`), moves its contents directly into [extractionDir]
/// and removes the wrapper. Files already at the root are left untouched.
Future<void> _flattenSingleTopLevelDir(String extractionDir) async {
  try {
    final dir = Directory(extractionDir);
    final contents = await dir.list().toList();
    if (contents.length != 1 || contents.first is! Directory) return;

    final wrapper = contents.first as Directory;
    await for (final entity in wrapper.list()) {
      await entity.rename(path.join(extractionDir, path.basename(entity.path)));
    }
    await wrapper.delete();
  } catch (e) {
    debugPrint('Warning: could not flatten extraction dir: $e');
  }
}

@pragma('vm:entry-point')
void extractionTaskCallback() {
  FlutterForegroundTask.setTaskHandler(ExtractionTaskHandler());
}

class ExtractionTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await FlutterForegroundTask.updateService(notificationText: 'Ready to extract...');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['action'] == 'extract') {
      final taskId = data['taskId'] as String;
      final filePath = data['filePath'] as String;
      final extractionDir = data['extractionDir'] as String;
      FlutterForegroundTask.updateService(notificationText: 'Extracting $taskId...');
      FlutterForegroundTask.sendDataToMain({
        'type': ExtractionService.progressDataType,
        'taskId': taskId,
        'value': 0.1,
      });

      final fileName = path.basename(filePath);
      int lastPct = -1;
      ZipFile.extractToDirectory(
        zipFile: File(filePath),
        destinationDir: Directory(extractionDir),
        onExtracting: (zipEntry, progress) {
          final pct = progress.round();
          if (pct != lastPct) {
            lastPct = pct;
            FlutterForegroundTask.updateService(notificationText: 'Extracting $fileName... $pct%');
            FlutterForegroundTask.sendDataToMain({
              'type': ExtractionService.progressDataType,
              'taskId': taskId,
              'value': (progress / 100.0).clamp(0.0, 1.0),
            });
          }
          return ZipFileOperation.includeItem;
        },
      ).then((_) => _flattenSingleTopLevelDir(extractionDir)).then((_) {
        FlutterForegroundTask.updateService(notificationText: 'Extraction completed for $taskId');
        FlutterForegroundTask.sendDataToMain({
          'type': ExtractionService.completionDataType,
          'taskId': taskId,
          'extractionDir': extractionDir,
        });
      }).catchError((e) {
        debugPrint('Extraction error: $e');
        FlutterForegroundTask.sendDataToMain({
          'type': ExtractionService.errorDataType,
          'taskId': taskId,
          'extractionDir': extractionDir,
          'message': 'Failed to extract: $e',
        });
        FlutterForegroundTask.updateService(notificationText: 'Extraction failed');
      });
    }
  }
}
