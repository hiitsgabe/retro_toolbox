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
  }) async {
    final jobsDir = await _ensureWorker();

    final progressFile = File(path.join(
      Directory.systemTemp.path,
      'nsz_progress_${nszFilePath.hashCode.abs()}.txt',
    ));
    await progressFile.writeAsString('');

    final completer = Completer<void>();
    int readPosition = 0;
    Timer? pollTimer;

    Future<void> checkFile() async {
      if (completer.isCompleted) return;
      try {
        if (!await progressFile.exists()) return;
        final content = await progressFile.readAsString();
        if (content.length <= readPosition) return;

        final newContent = content.substring(readPosition);
        readPosition = content.length;

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
      final jobId = '${nszFilePath.hashCode.abs()}_${DateTime.now().microsecondsSinceEpoch}';
      final jobFile = File(path.join(jobsDir, 'job_$jobId.json'));
      await jobFile.writeAsString(jsonEncode({
        'nsz_file': nszFilePath,
        'output_dir': outputDir,
        'keys_path': (keysPath != null && keysPath.isNotEmpty) ? keysPath : null,
        'progress_file': progressFile.path,
      }));

      await completer.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw Exception('NSZ decompression timed out after 30 minutes'),
      );
    } finally {
      pollTimer.cancel();
      try {
        if (await progressFile.exists()) await progressFile.delete();
      } catch (_) {}
    }
  }
}
