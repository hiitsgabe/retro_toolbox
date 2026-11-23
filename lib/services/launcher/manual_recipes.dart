import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/desktop_finder.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';

/// The Android recipes of [presets] that fit [package], in file order. The
/// native detect, asked about every recipe's activity in that one package,
/// answers for each one the package exports, so a fork under another
/// package is matched by what it really has. None when the channel fails,
/// as detect answers then.
Future<List<LaunchPreset>> androidRecipesFor(LauncherChannel channel, List<LaunchPreset> presets, String package) async {
  final android = [for (final preset in presets) if (preset.android != null) preset];
  if (android.isEmpty) return const [];
  final facts = await channel.detect([
    for (final preset in android) {'id': preset.id, 'packages': [package], 'activity': preset.android!.activity},
  ]);
  final fit = {
    for (final f in facts)
      if (f['package'] == package) f['id'],
  };
  return [for (final preset in android) if (fit.contains(preset.id)) preset];
}

/// The recipes of [presets] with a block for [os], the ones whose find rules
/// name [picked]'s file first (a `path` rule's name, or the file name of a
/// `static` or `app` path, a `*` matching anything, case aside), each group
/// in file order.
List<LaunchPreset> desktopRecipesFor(List<LaunchPreset> presets, String os, String picked) {
  final ctx = os == 'windows' ? p.windows : p.posix;
  final file = ctx.basename(picked).toLowerCase();
  bool like(String pattern) => RegExp('^${ctx.basename(pattern).toLowerCase().split('*').map(RegExp.escape).join('.*')}\$').hasMatch(file);
  bool names(LaunchPreset preset) => preset.desktopFor(os)!.find.any((r) => r.names.any((n) => n.toLowerCase() == file) || r.paths.any(like));
  final here = [for (final preset in presets) if (preset.desktopFor(os) != null) preset];
  return [...here.where(names), ...here.where((preset) => !names(preset))];
}

/// What runs for [picked]. On macOS a picked `.app` is a bundle, and the
/// binary its Info.plist names is what runs, read as the `app` find rule
/// reads it. Anything else, or a bundle that names none, is itself.
Future<String> executableFor(String picked, String os) async {
  if (os != 'macos' || !picked.toLowerCase().endsWith('.app')) return picked;
  final hit = await DesktopFinder(os: os).find([FindRule(type: FindType.app, paths: [picked])]);
  return hit?.exe ?? picked;
}
