import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python/serious_python.dart';

class NszService {
  /// Decompresses an NSZ file to [outputDir] using the bundled Python library.
  ///
  /// Throws an [Exception] on decompression failure.
  /// [onProgress] is called with values 0.0–1.0 as decompression proceeds.
  static Future<void> decompressNsz({
    required String nszFilePath,
    required String outputDir,
    String? keysPath,
    required void Function(double progress) onProgress,
  }) async {
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
      final env = <String, String>{
        'NSZ_FILE': nszFilePath,
        'OUTPUT_DIR': outputDir,
        'PROGRESS_FILE': progressFile.path,
      };
      if (keysPath != null && keysPath.isNotEmpty) {
        env['KEYS_PATH'] = keysPath;
      }

      // Intentionally not awaited — completer/pollTimer handle synchronisation.
      // ignore: unawaited_futures
      SeriousPython.run(environmentVariables: env).then(
        (_) {},
        onError: (Object e) {
          if (!completer.isCompleted) {
            pollTimer?.cancel();
            completer.completeError(e);
          }
        },
      );

      await completer.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw Exception('NSZ decompression timed out after 30 minutes'),
      );
    } finally {
      pollTimer?.cancel();
      try {
        if (await progressFile.exists()) await progressFile.delete();
      } catch (_) {}
    }
  }
}
