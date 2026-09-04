import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:rar/rar.dart';

enum ArchiveKind { zip, rar, unsupported }

/// Extracts a single archive to a folder. ZIP is handled in pure Dart (all
/// platforms); RAR uses the `rar` plugin, which only ships native code for
/// Android/iOS/macOS. Ported from the console_utilities extract utilities.
class ArchiveExtractService {
  static ArchiveKind archiveKind(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.zip':
        return ArchiveKind.zip;
      case '.rar':
        return ArchiveKind.rar;
      default:
        return ArchiveKind.unsupported;
    }
  }

  /// The `rar` plugin bundles native code only for these platforms.
  static bool rarSupported({String? overrideOs}) {
    final os = overrideOs ?? Platform.operatingSystem;
    return os == 'android' || os == 'ios' || os == 'macos';
  }

  /// Extracts [path] into [outDir]. Throws [UnsupportedError] for RAR on
  /// unsupported platforms or unknown types, and [Exception] on RAR failure.
  Future<void> extract(String path, String outDir, {String? overrideOs}) async {
    switch (archiveKind(path)) {
      case ArchiveKind.zip:
        await extractFileToDisk(path, outDir);
        return;
      case ArchiveKind.rar:
        if (!rarSupported(overrideOs: overrideOs)) {
          throw UnsupportedError('RAR extraction is not supported on this platform yet.');
        }
        final res = await Rar.extractRarFile(rarFilePath: path, destinationPath: outDir);
        if (res['success'] != true) {
          throw Exception(res['message'] ?? 'RAR extraction failed');
        }
        return;
      case ArchiveKind.unsupported:
        throw UnsupportedError('Unsupported archive type: ${p.extension(path)}');
    }
  }
}
