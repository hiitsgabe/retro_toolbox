import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python/serious_python.dart';

/// Outcome of parsing one worker progress line.
enum WorkerSignal { progress, status, done, error, none }

class WorkerLine {
  final WorkerSignal signal;

  /// 0.0–1.0 for [WorkerSignal.progress]; message for [WorkerSignal.error].
  final double progress;
  final String message;
  const WorkerLine(this.signal, {this.progress = 0, this.message = ''});
}

/// Parses one line of the worker's progress protocol (`PROGRESS:<int>` / `DONE`
/// / `ERROR:<msg>`). Pure and self-contained so it can be unit-tested without
/// the embedded interpreter.
WorkerLine parseWorkerLine(String line) {
  if (line.startsWith('PROGRESS:')) {
    return WorkerLine(WorkerSignal.progress, progress: (int.tryParse(line.substring(9)) ?? 0) / 100.0);
  }
  if (line.startsWith('STATUS:')) return WorkerLine(WorkerSignal.status, message: line.substring(7));
  if (line == 'DONE') return const WorkerLine(WorkerSignal.done, progress: 1.0);
  if (line.startsWith('ERROR:')) return WorkerLine(WorkerSignal.error, message: line.substring(6));
  return const WorkerLine(WorkerSignal.none);
}

/// Owns the single embedded-CPython worker.
///
/// serious_python corrupts process memory if the interpreter is initialized a
/// second time, so `SeriousPython.run()` is called at most ONCE per process.
/// Every caller (NSZ, 3DS conversion, sports patching) shares this one worker
/// and hands work over as `job_*.json` files in [_jobsDir]; the worker loop in
/// `python_app/main.py` dispatches by the job's `type`.
class PythonWorker {
  static bool _started = false;
  static String? _jobsDir;

  static Future<String> _ensure() async {
    _jobsDir ??= path.join(Directory.systemTemp.path, 'python_worker');
    await Directory(_jobsDir!).create(recursive: true);

    if (!_started) {
      _started = true;
      // Not awaited: the worker loops forever, so this future never completes.
      // ignore: unawaited_futures
      SeriousPython.run(environmentVariables: {'JOBS_DIR': _jobsDir!}).then(
        (_) {
          // Worker returned unexpectedly; allow a restart on the next job.
          _started = false;
        },
        onError: (Object e) {
          debugPrint('Python worker failed: $e');
          _started = false;
        },
      );
    }
    return _jobsDir!;
  }

  /// Submits [job] to the persistent worker and resolves when it reports DONE,
  /// forwarding PROGRESS (0.0–1.0) to [onProgress]; throws on ERROR or a stall.
  ///
  /// [tag] disambiguates this job's progress file. Data-returning jobs pass an
  /// `output_file` path in [job] and read it after this future completes.
  static Future<void> runJob({
    required String tag,
    required Map<String, dynamic> job,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    Duration inactivityLimit = const Duration(minutes: 15),
  }) async {
    final jobsDir = await _ensure();

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
          final parsed = parseWorkerLine(line);
          switch (parsed.signal) {
            case WorkerSignal.progress:
              onProgress?.call(parsed.progress);
            case WorkerSignal.status:
              onStatus?.call(parsed.message);
            case WorkerSignal.done:
              pollTimer?.cancel();
              onProgress?.call(1.0);
              completer.complete();
              return;
            case WorkerSignal.error:
              pollTimer?.cancel();
              completer.completeError(Exception(parsed.message));
              return;
            case WorkerSignal.none:
              break;
          }
        }
      } catch (e) {
        debugPrint('Python worker progress poll error: $e');
      }
    }

    pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => checkFile());

    try {
      final jobId = '${tag}_${DateTime.now().microsecondsSinceEpoch}';
      final jobFile = File(path.join(jobsDir, 'job_$jobId.json'));
      await jobFile.writeAsString(jsonEncode({...job, 'progress_file': progressFile.path}));

      // No fixed total timeout: a big job on slow storage legitimately runs for
      // a long time. Fail only if the worker goes silent (no new progress) for
      // a while, catching a genuine hang without killing slow-but-working jobs.
      watchdog = Timer.periodic(const Duration(seconds: 30), (_) {
        if (completer.isCompleted) return;
        if (DateTime.now().difference(lastActivity) > inactivityLimit) {
          watchdog?.cancel();
          completer.completeError(Exception(
              'Python job stalled: no progress for ${inactivityLimit.inMinutes} minutes'));
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
