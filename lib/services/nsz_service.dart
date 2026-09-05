import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python/serious_python.dart';

class NszService {
  // serious_python corrupts process memory if the embedded interpreter is
  // initialized a second time, so SeriousPython.run() must be called at most
  // ONCE per process. We start a persistent Python worker on the first
  // decompression and hand every later job over as a file in [_jobsDir].
  static bool _workerStarted = false;
  static String? _jobsDir;

  static Future<String> _ensureWorker() async {
    _jobsDir ??= path.join(Directory.systemTemp.path, 'nsz_worker');
    await Directory(_jobsDir!).create(recursive: true);

    if (!_workerStarted) {
      _workerStarted = true;
      // Not awaited: the worker loops forever, so this future never completes.
      // ignore: unawaited_futures
      SeriousPython.run(environmentVariables: {'JOBS_DIR': _jobsDir!}).then(
        (_) {
          // Worker returned unexpectedly; allow a restart on the next job.
          _workerStarted = false;
        },
        onError: (Object e) {
          debugPrint('NSZ worker failed: $e');
          _workerStarted = false;
        },
      );
    }
    return _jobsDir!;
  }

  /// Decompresses an NSZ file to [outputDir] using the persistent Python worker.
  ///
  /// Throws an [Exception] on decompression failure.
  /// [onProgress] is called with values 0.0–1.0 as decompression proceeds.
  static Future<void> decompressNsz({
    required String nszFilePath,
    required String outputDir,
    String? keysPath,
    required void Function(double progress) onProgress,
  }) =>
      _runJob(
        tag: 'nsz_${nszFilePath.hashCode.abs()}',
        job: {
          'nsz_file': nszFilePath,
          'output_dir': outputDir,
          'keys_path': (keysPath != null && keysPath.isNotEmpty) ? keysPath : null,
        },
        onProgress: onProgress,
      );

  /// Converts a .3ds/.cci to .cia via the bundled 3dsconv worker job.
  /// [boot9Path] is needed for encrypted dumps. Throws on failure.
  static Future<void> convert3dsToCia({
    required String inputFile,
    required String outputDir,
    String? boot9Path,
    bool ignoreEncryption = false,
    required void Function(double progress) onProgress,
  }) =>
      _runJob(
        tag: 'cia_${inputFile.hashCode.abs()}',
        job: {
          'type': '3dsconv',
          'input_file': inputFile,
          'output_dir': outputDir,
          'boot9_path': (boot9Path != null && boot9Path.isNotEmpty) ? boot9Path : null,
          'ignore_encryption': ignoreEncryption,
        },
        onProgress: onProgress,
      );

  /// Submits [job] to the persistent worker and resolves when it reports DONE,
  /// forwarding PROGRESS to [onProgress]; throws on ERROR or a long stall.
  static Future<void> _runJob({
    required String tag,
    required Map<String, dynamic> job,
    required void Function(double progress) onProgress,
  }) async {
    final jobsDir = await _ensureWorker();

    final progressFile = File(path.join(Directory.systemTemp.path, 'worker_progress_$tag.txt'));
    await progressFile.writeAsString('');

    final completer = Completer<void>();
    int readPosition = 0;
    Timer? pollTimer;
    Timer? watchdog;
    var lastActivity = DateTime.now();

    Future<void> checkFile() async {
      if (completer.isCompleted) return;
      try {
        if (!await progressFile.exists()) return;
        final content = await progressFile.readAsString();
        if (content.length <= readPosition) return;

        final newContent = content.substring(readPosition);
        readPosition = content.length;
        lastActivity = DateTime.now();

        for (final line in newContent.split('\n').where((l) => l.isNotEmpty)) {
          if (completer.isCompleted) break;
          if (line.startsWith('PROGRESS:')) {
            final pct = int.tryParse(line.substring(9)) ?? 0;
            onProgress(pct / 100.0);
          } else if (line == 'DONE') {
            pollTimer?.cancel();
            onProgress(1.0);
            completer.complete();
            return;
          } else if (line.startsWith('ERROR:')) {
            pollTimer?.cancel();
            completer.completeError(Exception(line.substring(6)));
            return;
          }
        }
      } catch (e) {
        debugPrint('NSZ progress poll error: $e');
      }
    }

    pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => checkFile());

    try {
      // Hand the job to the worker. It picks up job_*.json files, decompresses
      // one at a time, and writes PROGRESS/DONE/ERROR into progressFile.
      final jobId = '${tag}_${DateTime.now().microsecondsSinceEpoch}';
      final jobFile = File(path.join(jobsDir, 'job_$jobId.json'));
      await jobFile.writeAsString(jsonEncode({...job, 'progress_file': progressFile.path}));

      // No fixed total timeout: a big NSZ on a slow SD legitimately runs for
      // hours. Fail only if the worker goes silent (no new progress) for a
      // while, which catches a genuine hang without killing a slow-but-working
      // decompression.
      const inactivityLimit = Duration(minutes: 15);
      watchdog = Timer.periodic(const Duration(seconds: 30), (_) {
        if (completer.isCompleted) return;
        if (DateTime.now().difference(lastActivity) > inactivityLimit) {
          watchdog?.cancel();
          completer.completeError(Exception(
              'NSZ decompression stalled: no progress for ${inactivityLimit.inMinutes} minutes'));
        }
      });

      await completer.future;
    } finally {
      pollTimer.cancel();
      watchdog?.cancel();
      try {
        if (await progressFile.exists()) await progressFile.delete();
      } catch (_) {}
    }
  }
}
