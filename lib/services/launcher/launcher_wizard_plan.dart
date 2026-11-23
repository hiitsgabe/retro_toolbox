import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/android_launch_plan.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_target.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';

/// Up to three presets to install when nothing was detected: those with a
/// block for [os] that open the most of [slugs], the file's order breaking
/// ties (the file lists the preferred emulator first).
List<LaunchPreset> suggestEmulators(List<LaunchPreset> presets, Set<String> slugs, String os) {
  bool runsHere(LaunchPreset preset) => os == 'android' ? preset.android != null : preset.desktopFor(os) != null;
  int covered(LaunchPreset preset) => preset.systems.keys.where(slugs.contains).length;
  final ranked = [
    for (final (i, preset) in presets.indexed)
      if (runsHere(preset) && covered(preset) > 0) (i: i, preset: preset, covered: covered(preset)),
  ]..sort((a, b) => b.covered != a.covered ? b.covered.compareTo(a.covered) : a.i.compareTo(b.i));
  return [for (final r in ranked.take(3)) r.preset];
}

/// The choice a Systems row starts on for a console of [slug]: its saved
/// [existing] default while that emulator is detected and opens [slug],
/// with the variant detected now; else the first detected emulator that
/// opens it, in preset file order. Null when none does.
LaunchChoice? preselect(LauncherSession session, String? slug, LaunchChoice? existing) {
  final covering = session.covering(slug);
  if (existing != null) {
    for (final d in covering) {
      if (d.presetId == existing.presetId) return LaunchChoice(presetId: d.presetId, variant: d.variant, core: existing.core);
    }
  }
  return covering.isEmpty ? null : covering.first.choice;
}

/// Whether a launch of [system] with [preset] can hand over a `saf` URI, so
/// the emulator needs its own grant on the folder: a single file in `saf`,
/// or an m3u, cue or gdi when [system] takes one and the multi-file mode is
/// `saf`. Android only.
bool needsFolderAccess(LaunchPreset preset, DetectedEmulator detected, PresetSystem system) {
  if (preset.android == null) return false;
  if (effectiveMode(preset, detected, const LaunchTarget('/rom')) == RomMode.saf) return true;
  final multiFile = system.extensions.any(const {'m3u', 'cue', 'gdi'}.contains);
  return multiFile && effectiveMode(preset, detected, const LaunchTarget('/rom.m3u')) == RomMode.saf;
}

/// Whether [dir] is in this app's own `Android/data` folder, which no
/// other app can read: a `path` or `saf` launch from there is romPrivate.
bool isAppPrivateDir(String dir, String primary) => p.posix.isWithin('$primary/Android/data', dir);

/// How a choice reads: the emulator's name, with its core when it has one.
String choiceName(LauncherSession? session, LaunchChoice choice) {
  final name = session?.detectedFor(choice.presetId)?.label ?? session?.preset(choice.presetId)?.name ?? choice.presetId;
  return choice.core == null ? name : '$name (${choice.core})';
}
