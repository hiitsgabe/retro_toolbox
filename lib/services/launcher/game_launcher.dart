import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/android_launch_plan.dart';
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
    Future<String> Function()? primaryRoot,
    String? os,
  })  : _channel = channel ?? const LauncherChannel(),
        _primaryRoot = primaryRoot ?? primaryStorageRoot,
        _os = os ?? Platform.operatingSystem;

  final LauncherSession session;

  /// The console art slug of a catalog console id, or null.
  final String? Function(String consoleId) systemSlugFor;

  final LauncherChannel _channel;
  final Future<String> Function() _primaryRoot;
  final String _os;

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
    // Desktop launches come with the process runner (desktop_finder.dart).
    return const LaunchResult(LaunchCode.unsupported);
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
}

String? _ext(String? path) {
  if (path == null) return null;
  final e = p.extension(path).toLowerCase();
  return e.isEmpty ? null : e.substring(1);
}
