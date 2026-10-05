import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:rar/rar.dart';
// ignore: implementation_imports
import 'package:rar/src/rar_ffi.dart'; // the plugin only picks its FFI backend on Android; Linux needs it too
import 'package:retro_toolbox/services/rar_header.dart';

enum ArchiveKind { zip, rar, unsupported }

/// Extracts a single archive to a folder. ZIP is handled in pure Dart (all
/// platforms); RAR uses the `rar` plugin, which ships native code for
/// Android/iOS/macOS. On Linux CI compiles the plugin's libarchive-backed C
/// source into the bundle's lib/ (see [loadLinuxRar]). Ported from the
/// console_utilities extract utilities.
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

  /// The `rar` plugin bundles native code for android/ios/macos; Linux works
  /// when the CI-built library loaded.
  static bool rarSupported({String? overrideOs}) {
    final os = overrideOs ?? Platform.operatingSystem;
    if (os == 'linux') return linuxRar ??= loadLinuxRar(linuxRarPath);
    return os == 'android' || os == 'ios' || os == 'macos';
  }

  /// Cached Linux load result; null until first asked.
  @visibleForTesting
  static bool? linuxRar;

  /// `<exe dir>/lib/`: the desktop bundle, and the handheld port folder
  /// (flutter-pi sits beside the bundle's lib/).
  @visibleForTesting
  static String linuxRarPath = p.join(p.dirname(Platform.resolvedExecutable), 'lib', 'librar_native.so');

  /// Loads the library by absolute path. Its soname is librar_native.so, so the
  /// plugin's later by-name open resolves to this already-loaded copy; then
  /// switch the plugin to its FFI backend (the method channel has no Linux side).
  @visibleForTesting
  static bool loadLinuxRar(String path) {
    try {
      DynamicLibrary.open(path);
    } catch (_) {
      return false;
    }
    RarPlatform.instance = RarFfi();
    return true;
  }

  /// Extracts [path] into [outDir]. Throws [UnsupportedError] for RAR on
  /// unsupported platforms or unknown types, and [Exception] on RAR failure.
  ///
  /// [onProgress] (0.0–1.0) is reported for RAR only, by polling the bytes the
  /// listed files have reached against the unpacked total in the headers: the
  /// plugin itself reports nothing until it finishes.
  Future<void> extract(String path, String outDir, {String? overrideOs, void Function(double progress)? onProgress}) async {
    switch (archiveKind(path)) {
      case ArchiveKind.zip:
        await extractFileToDisk(path, outDir);
        return;
      case ArchiveKind.rar:
        if (!rarSupported(overrideOs: overrideOs)) {
          throw UnsupportedError('RAR extraction is not supported on this platform yet.');
        }
        final poll = onProgress == null ? null : await _pollRarProgress(path, outDir, onProgress);
        final Map<String, dynamic> res;
        try {
          res = await Rar.extractRarFile(rarFilePath: path, destinationPath: outDir);
        } finally {
          poll?.cancel();
        }
        if (res['success'] != true) {
          throw Exception(res['message'] ?? 'RAR extraction failed');
        }
        return;
      case ArchiveKind.unsupported:
        throw UnsupportedError('Unsupported archive type: ${p.extension(path)}');
    }
  }

  /// Polls extraction progress once a second; null when the total can't be
  /// read from the headers (then the caller just shows an indeterminate state).
  static Future<Timer?> _pollRarProgress(String path, String outDir, void Function(double) onProgress) async {
    final total = rarUnpackedSize(path);
    if (total == null || total <= 0) return null;
    final listed = await Rar.listRarContents(rarFilePath: path);
    final names = [for (final n in (listed['files'] as List? ?? const [])) '$n'.replaceAll('\\', '/')];
    if (names.isEmpty) return null;
    var last = -1.0;
    return Timer.periodic(const Duration(seconds: 1), (_) {
      var written = 0;
      for (final n in names) {
        try {
          written += File(p.joinAll([outDir, ...n.split('/')])).lengthSync();
        } catch (_) {} // not created yet, or a folder
      }
      // ponytail: capped below 1 — the plugin's own return marks completion.
      final fraction = min(written / total, 0.99);
      if (fraction != last) {
        last = fraction;
        onProgress(fraction);
      }
    });
  }
}
