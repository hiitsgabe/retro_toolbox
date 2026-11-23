import 'dart:io';

import 'package:retro_toolbox/services/launcher/launch_preset_check.dart';

/// Checks launch_presets/launch_presets.json (or the file given) strictly:
/// any problem, even one the app would survive by dropping a preset, exits 1.
void main(List<String> args) {
  final path = args.isEmpty ? 'launch_presets/launch_presets.json' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$path: not found');
    exitCode = 1;
    return;
  }
  final check = checkPresetFile(file.readAsStringSync());
  if (check.file == null || check.problems.isNotEmpty) {
    for (final p in check.problems) {
      stderr.writeln('$path: $p');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('$path: ${check.file!.presets.length} presets, schema ${check.file!.schema}, version ${check.file!.version}');
}
