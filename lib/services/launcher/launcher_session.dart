import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';

/// The presets in use and what of them is installed, kept for the session.
class LauncherSession {
  const LauncherSession({required this.presets, required this.detected});

  final List<LaunchPreset> presets;

  /// In preset file order.
  final List<DetectedEmulator> detected;

  LaunchPreset? preset(String id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The detection for [presetId]. The variant comes from it, not from a
  /// saved choice, so moving to another build of the same emulator keeps
  /// the choice working.
  DetectedEmulator? detectedFor(String presetId) {
    for (final d in detected) {
      if (d.presetId == presetId) return d;
    }
    return null;
  }

  /// The detected emulators whose preset opens [slug].
  List<DetectedEmulator> covering(String? slug) => slug == null ? const [] : [for (final d in detected) if (d.systems.contains(slug)) d];
}
