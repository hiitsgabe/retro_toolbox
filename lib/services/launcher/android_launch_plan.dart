import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/launcher/launch_target.dart';
import 'package:retro_toolbox/services/pick.dart';

const _externalStorage = 'com.android.externalstorage.documents';

/// The mode a launch hands the ROM over in. Only this result crosses the
/// channel; the native side never derives it again.
RomMode effectiveMode(LaunchPreset preset, DetectedEmulator detected, LaunchTarget target) {
  final rom = preset.android!.rom;
  final base = !detected.pathAccess && rom.scopedMode != null ? rom.scopedMode! : rom.mode;
  if (!target.multiFile) return base;
  // A provider URI reaches one file, never the bins beside a cue.
  return rom.multiFileMode ?? (base == RomMode.provider ? RomMode.saf : base);
}

/// The external-storage document URI for [docId], encoded as Android's
/// `Uri.encode` does it (`Uri.encodeComponent` keeps the same characters).
String safDocumentUri(String docId) => 'content://$_externalStorage/document/${Uri.encodeComponent(docId)}';

/// The `launch` arguments for [target], or why nothing may be launched. Every
/// value is rendered here except `{rom}` and `{rom.uri}` in provider mode,
/// which only the native side can build (`FileProvider.getUriForFile`).
({Map<String, Object?>? args, LaunchResult? failure}) planAndroidLaunch({
  required LaunchPreset preset,
  required PresetSystem system,
  required DetectedEmulator detected,
  required LaunchTarget target,
  required LaunchChoice choice,
  required String primary,
}) {
  final android = preset.android!;
  final path = target.path!;
  final mode = effectiveMode(preset, detected, target);
  // No other app can read our Android/data folder; only our own provider can
  // serve a file from there.
  if (mode != RomMode.provider && p.posix.isWithin('$primary/Android/data', path)) {
    return (args: null, failure: const LaunchResult(LaunchCode.romPrivate));
  }
  String? uri;
  if (mode == RomMode.saf) {
    final docId = strictDocId(path, primary);
    if (docId == null) return (args: null, failure: const LaunchResult(LaunchCode.romUnreadable));
    uri = safDocumentUri(docId);
  }
  final core = choice.core ?? (system.cores.isEmpty ? '' : system.cores.first);
  final values = {
    'rom': switch (mode) {
      RomMode.path => path,
      RomMode.saf => uri!,
      RomMode.provider => '{rom}',
    },
    'rom.path': path,
    'rom.uri': switch (mode) {
      RomMode.path => '',
      RomMode.saf => uri!,
      RomMode.provider => '{rom.uri}',
    },
    'retroarch.core': detected.dataDir == null ? core : '${detected.dataDir}/cores/${core}_libretro_android.so',
    // The Play builds cannot read it, and RetroArch derives its own when the
    // extra is absent.
    'retroarch.config': detected.pathAccess ? '$primary/Android/data/${detected.variant}/files/retroarch.cfg' : '',
  };
  String render(String template) => template.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (m) => values[m[1]] ?? m[0]!);

  final extras = <Map<String, Object?>>[];
  for (final e in android.extras) {
    final Object value = switch (e.value) {
      final String s => render(s),
      final List<String> l => [for (final s in l) render(s)],
      final other => other,
    };
    // An empty rendered value is left out, not sent empty.
    if (value is String && value.isEmpty) continue;
    if (value is List<String> && value.every((s) => s.isEmpty)) continue;
    extras.add({'key': e.key, 'type': e.type.name, 'value': value});
  }
  final clipDataDiscs = mode == RomMode.provider && android.rom.clipDataDiscs && target.discs.isNotEmpty;
  return (
    args: {
      'package': detected.variant,
      'activity': android.activity,
      'action': android.action,
      'categories': android.categories,
      'mimeType': android.mimeType,
      'flags': [for (final f in android.flags) f.name],
      'rom': {
        'path': path,
        'mode': mode.name,
        'uri': uri,
        'extra': android.rom.extra,
        'clipDataDiscs': clipDataDiscs,
        'discPaths': clipDataDiscs ? target.discs : const <String>[],
      },
      'extras': extras,
    },
    failure: null,
  );
}
