import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, MethodChannel;
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
  static const _nativeChannel = MethodChannel('retrotoolbox/native');

  /// Resolves a usable chdman path. On Android it must be a binary shipped as a
  /// jniLib (libchdman.so) and run from the read-only nativeLibraryDir, since
  /// exec from writable app dirs is blocked. Elsewhere: configured path →
  /// bundled asset → system PATH. Returns null if none is available.
  static Future<String?> resolveChdman(String? configuredPath) async {
    if (configuredPath != null && configuredPath.isNotEmpty && File(configuredPath).existsSync()) {
      return configuredPath;
    }
    if (Platform.isAndroid) return _androidNativeChdman();
    final bundled = await _bundledChdman();
    if (bundled != null) return bundled;
    return _chdmanOnPath();
  }

  static Future<String?> _androidNativeChdman() async {
    try {
      final dir = await _nativeChannel.invokeMethod<String>('nativeLibDir');
      if (dir == null) return null;
      final f = File(p.join(dir, 'libchdman.so'));
      return f.existsSync() ? f.path : null;
    } catch (_) {
      return null;
    }
  }

  /// If a chdman for this platform ships in assets, extract it (and any sibling
  /// libraries listed in its manifest) to the support dir once, mark the binary
  /// executable, and return its path. Returns null when nothing is bundled.
  ///
  /// Layout: `assets/chdman/<os>/manifest.txt` lists the files to extract, the
  /// binary (`chdman`/`chdman.exe`) first, then any bundled dynamic libraries.
  /// The libraries are loaded via `@loader_path`, so they must land next to the
  /// binary — which they do, since everything extracts into the same `bin` dir.
  static Future<String?> _bundledChdman() async {
    if (_resolvedBundled != null) return _resolvedBundled;
    final os = Platform.operatingSystem; // android, macos, linux, windows
    final base = 'assets/chdman/$os';
    try {
      final manifest = (await rootBundle.loadString('$base/manifest.txt'))
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (manifest.isEmpty) return null;

      final binDir = Directory(p.join((await getApplicationSupportDirectory()).path, 'chdman'));
      await binDir.create(recursive: true);

      String? binaryPath;
      for (final name in manifest) {
        final data = await rootBundle.load('$base/$name');
        final dest = File(p.join(binDir.path, name));
        if (!dest.existsSync() || dest.lengthSync() != data.lengthInBytes) {
          await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
          if (!Platform.isWindows) await Process.run('chmod', ['+x', dest.path]);
        }
        if (name == 'chdman' || name == 'chdman.exe') binaryPath = dest.path;
      }
      _resolvedBundled = binaryPath;
      return binaryPath;
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
