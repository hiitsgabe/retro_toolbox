import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/android_launch_plan.dart';
import 'package:retro_toolbox/services/launcher/desktop_finder.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/launcher/launch_target.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/services/pick.dart';

/// Starts an owned game in the emulator a [LaunchChoice] names.
class GameLauncher {
  GameLauncher({
    required this.session,
    required this.systemSlugFor,
    LauncherChannel? channel,
    ProcessRunner? runner,
    Future<String> Function()? primaryRoot,
    String? os,
    Map<String, String>? env,
    this.window = const Duration(seconds: 3),
  })  : _channel = channel ?? const LauncherChannel(),
        _runner = runner ?? const IoProcessRunner(),
        _primaryRoot = primaryRoot ?? primaryStorageRoot,
        _os = os ?? Platform.operatingSystem,
        _env = env ?? Platform.environment;

  final LauncherSession session;

  /// The console art slug of a catalog console id, or null.
  final String? Function(String consoleId) systemSlugFor;

  /// Desktop: how long a started emulator is watched for an early exit.
  final Duration window;

  final LauncherChannel _channel;
  final ProcessRunner _runner;
  final Future<String> Function() _primaryRoot;
  final String _os;
  final Map<String, String> _env;

  Future<LaunchResult> launch(OwnedGame game, LaunchChoice choice) async {
    final preset = session.preset(choice.presetId);
    final detected = session.detectedFor(choice.presetId);
    if (preset == null || detected == null) return const LaunchResult(LaunchCode.notInstalled);
    final system = preset.systems[systemSlugFor(game.game.consoleId)];
    final target = system == null ? LaunchTarget.unsupported(_ext(game.paths.firstOrNull)) : resolveLaunchTarget(game, system);
    if (!target.supported) {
      if (game.paths.isEmpty) return const LaunchResult(LaunchCode.romUnreadable);
      return LaunchResult(LaunchCode.unsupportedFile, extension: target.unsupportedExtension);
    }
    if (!File(target.path!).existsSync()) return const LaunchResult(LaunchCode.romUnreadable);
    if (_os == 'android') {
      final plan = planAndroidLaunch(preset: preset, system: system!, detected: detected, target: target, choice: choice, primary: await _primaryRoot());
      return plan.failure ?? await _channel.launch(plan.args!);
    }
    return _desktop(preset, system!, detected, target, choice);
  }

  /// The mode an Android launch of [game] would use, for the details page's
  /// folder-access hint; null on desktop or when nothing would launch.
  RomMode? modeFor(OwnedGame game, LaunchChoice choice) {
    if (_os != 'android') return null;
    final preset = session.preset(choice.presetId);
    final detected = session.detectedFor(choice.presetId);
    final system = preset?.systems[systemSlugFor(game.game.consoleId)];
    if (preset?.android == null || detected == null || system == null) return null;
    final target = resolveLaunchTarget(game, system);
    return target.supported ? effectiveMode(preset!, detected, target) : null;
  }

  Future<LaunchResult> _desktop(LaunchPreset preset, PresetSystem system, DetectedEmulator detected, LaunchTarget target, LaunchChoice choice) async {
    final block = preset.desktopFor(_os);
    final exe = detected.exe;
    if (block == null || exe == null) return const LaunchResult(LaunchCode.notInstalled);
    String? corePath;
    if (block.args.any((a) => a.contains('{retroarch.core}'))) {
      final core = choice.core ?? system.cores.first;
      corePath = _retroarchCore(detected, core);
      if (corePath == null) return LaunchResult(LaunchCode.unsupportedFile, core: core);
    }
    final values = {'rom': target.path!, 'rom.path': target.path!, 'rom.uri': Uri.file(target.path!).toString(), 'retroarch.core': corePath ?? '', 'retroarch.config': ''};
    final args = [
      ...detected.prefixArgs,
      for (final a in block.args) a.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (m) => values[m[1]] ?? m[0]!),
    ];
    return _watch(exe, args);
  }

  /// The core file under the detected RetroArch's cores folder, or null.
  String? _retroarchCore(DetectedEmulator detected, String core) {
    final home = _env['HOME'] ?? _env['USERPROFILE'] ?? '';
    final (dirs, suffix) = switch (_os) {
      'windows' => ([p.windows.join(p.windows.dirname(detected.exe!), 'cores')], 'dll'),
      'macos' => (['$home/Library/Application Support/RetroArch/cores'], 'dylib'),
      _ => (
          detected.prefixArgs.isNotEmpty
              ? ['$home/.var/app/${detected.variant}/config/retroarch/cores']
              : ['$home/.config/retroarch/cores', '/usr/lib/x86_64-linux-gnu/libretro', '/usr/lib/libretro'],
          'so',
        ),
    };
    final ctx = _os == 'windows' ? p.windows : p.posix;
    for (final dir in dirs) {
      final file = ctx.join(dir, '${core}_libretro.$suffix');
      if (File(file).existsSync()) return file;
    }
    return null;
  }

  /// Starts [exe] and watches it for [window]. Exit codes come only from a
  /// process that is not detached, so both pipes are drained for its whole
  /// life (a full pipe would block the emulator) and stderr keeps its last
  /// 20 lines. Emulators print paths in the local code page and binary
  /// noise, so stderr decodes leniently, and the end of stderr comes from
  /// onDone because asFuture cancels the drain on the first error.
  Future<LaunchResult> _watch(String exe, List<String> args) async {
    final Process process;
    try {
      process = await _runner.start(exe, args);
    } on ProcessException catch (e) {
      return LaunchResult(LaunchCode.notInstalled, message: e.message);
    }
    final tail = <String>[];
    process.stdout.listen((_) {}, onError: (_) {});
    final stderrDone = Completer<void>();
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(
      (line) {
        tail.add(line);
        if (tail.length > 20) tail.removeAt(0);
      },
      onError: (_) {},
      onDone: stderrDone.complete,
    );
    final code = await process.exitCode.then<int?>((c) => c).timeout(window, onTimeout: () => null);
    if (code == null || code == 0) return LaunchResult.ok;
    await stderrDone.future.timeout(const Duration(seconds: 1), onTimeout: () {});
    return LaunchResult(LaunchCode.crashed, message: tail.join('\n'));
  }
}

String? _ext(String? path) {
  if (path == null) return null;
  final e = p.extension(path).toLowerCase();
  return e.isEmpty ? null : e.substring(1);
}
