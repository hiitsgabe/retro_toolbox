import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum ChdMode { compress, extract }

/// A chdman invocation plan: the subcommand and the output extension.
typedef ChdPlan = ({String command, String outExt});

/// Converts disc images to/from MAME's CHD format by driving the `chdman`
/// binary. chdman is resolved from (1) a user-set path, (2) a binary bundled in
/// assets for the current platform (Phase 2 — dropped in later), or (3) the
/// system PATH. There is no Dart/Python library that *creates* CHDs — only
/// chdman does — so this shells out, mirroring how CHDroid works on Android.
class ChdService {
  static const _cdInputs = {'.cue', '.gdi', '.toc'};
  static const _dvdInputs = {'.iso'};

  static ChdMode modeForInput(String path) =>
      p.extension(path).toLowerCase() == '.chd' ? ChdMode.extract : ChdMode.compress;

  /// The chdman subcommand and resulting extension for [inputPath], or null if
  /// the extension isn't handled.
  static ChdPlan? planFor(String inputPath) {
    final ext = p.extension(inputPath).toLowerCase();
    if (ext == '.chd') return (command: 'extractcd', outExt: '.cue');
    if (_cdInputs.contains(ext)) return (command: 'createcd', outExt: '.chd');
    // ponytail: .iso -> createdvd heuristic. PS2/PSP/GC ISOs are DVD/UMD; PS1
    // discs come as .cue not .iso in practice. Revisit if CD-sized ISOs appear.
    if (_dvdInputs.contains(ext)) return (command: 'createdvd', outExt: '.chd');
    return null;
  }

  /// Extracts the 0.0–1.0 progress from a chdman output line, or null.
  static double? parseProgress(String line) {
    final m = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(line);
    if (m == null) return null;
    return (double.tryParse(m.group(1)!) ?? 0) / 100.0;
  }

  // --- binary resolution --------------------------------------------------

  static String? _resolvedBundled;

  /// Resolves a usable chdman path: configured path → bundled asset → PATH.
  /// Returns null if none is available.
  static Future<String?> resolveChdman(String? configuredPath) async {
    if (configuredPath != null && configuredPath.isNotEmpty && File(configuredPath).existsSync()) {
      return configuredPath;
    }
    final bundled = await _bundledChdman();
    if (bundled != null) return bundled;
    return _chdmanOnPath();
  }

  /// Phase 2: if a chdman binary for this platform ships in assets, extract it
  /// to the support dir once, mark it executable, and return its path. Returns
  /// null when no such asset is bundled (the current default).
  static Future<String?> _bundledChdman() async {
    if (_resolvedBundled != null) return _resolvedBundled;
    final os = Platform.operatingSystem; // android, macos, linux, windows
    final assetName = 'assets/chdman/$os/chdman${Platform.isWindows ? '.exe' : ''}';
    try {
      final data = await rootBundle.load(assetName);
      final dir = await getApplicationSupportDirectory();
      final dest = File(p.join(dir.path, 'bin', 'chdman${Platform.isWindows ? '.exe' : ''}'));
      await dest.parent.create(recursive: true);
      if (!dest.existsSync() || dest.lengthSync() != data.lengthInBytes) {
        await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', dest.path]);
        }
      }
      _resolvedBundled = dest.path;
      return dest.path;
    } catch (_) {
      // No bundled binary for this platform — fall through to PATH.
      return null;
    }
  }

  static Future<String?> _chdmanOnPath() async {
    try {
      final which = Platform.isWindows ? 'where' : 'which';
      final r = await Process.run(which, ['chdman']);
      if (r.exitCode == 0) {
        final out = (r.stdout as String).trim().split('\n').first.trim();
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    return null;
  }

  // --- conversion ---------------------------------------------------------

  /// Runs a conversion for [inputPath] into [outputDir]. Streams chdman output
  /// to [onProgress] (0.0–1.0). Throws if chdman is missing or exits non-zero.
  Future<String> convert({
    required String inputPath,
    required String outputDir,
    String? chdmanPath,
    required void Function(double progress) onProgress,
  }) async {
    final plan = planFor(inputPath);
    if (plan == null) {
      throw UnsupportedError('Unsupported file type: ${p.extension(inputPath)}');
    }
    final chdman = await resolveChdman(chdmanPath);
    if (chdman == null) {
      throw StateError('chdman not found. Set its path in the tool, or install mame-tools.');
    }

    final base = p.basenameWithoutExtension(inputPath);
    final outPath = p.join(outputDir, '$base${plan.outExt}');
    await Directory(outputDir).create(recursive: true);

    final process = await Process.start(chdman, [plan.command, '-i', inputPath, '-o', outPath, '-f']);

    void handle(String line) {
      final pct = parseProgress(line);
      if (pct != null) onProgress(pct);
    }

    process.stdout.transform(const SystemEncoding().decoder).transform(const LineSplitter()).listen(handle);
    final errBuffer = StringBuffer();
    process.stderr.transform(const SystemEncoding().decoder).transform(const LineSplitter()).listen((line) {
      handle(line);
      errBuffer.writeln(line);
    });

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('chdman failed (exit $exitCode): ${errBuffer.toString().trim()}');
    }
    onProgress(1.0);
    return outPath;
  }

  /// Whether a chdman is available right now (for gating the UI).
  static Future<bool> isAvailable(String? configuredPath) async =>
      (await resolveChdman(configuredPath)) != null;

  static void debugReset() => _resolvedBundled = null; // for tests
}
