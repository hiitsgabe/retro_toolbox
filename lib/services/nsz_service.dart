import 'package:roms_downloader/services/python_worker.dart';

/// NSZ decompression and 3DS→CIA conversion, run on the shared embedded-Python
/// worker (see [PythonWorker] for the single-interpreter constraint).
class NszService {
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
      PythonWorker.runJob(
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
      PythonWorker.runJob(
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
}
